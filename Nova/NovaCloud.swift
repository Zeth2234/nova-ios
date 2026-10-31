import Foundation
import Security

// ════════════════════════════════════════════════════════════════════════════════════
//  Conexión con la cuenta Nova (Supabase): la MISMA cuenta, amigos y chat que Nova Windows
//  y la web. Sin librerías externas: autenticación (GoTrue), funciones RPC (PostgREST)
//  y almacenamiento de fotos (Storage) con URLSession.
// ════════════════════════════════════════════════════════════════════════════════════

enum NovaConfig {
    static let url = URL(string: "https://qxtlapdyajrtqwgiqgcr.supabase.co")!
    /// Clave pública: los datos los protegen las reglas de Supabase (igual que en la web).
    static let key = "sb_publishable_FN9mS8i5yTsKVpAZyGo9dA_0G5XDXKc"
    static let mediaBucket = "nova-profile-media"
    static let groupBucket = "nova-group-media"
}

// MARK: - JSON flexible

/// Envoltorio cómodo para leer las respuestas JSON de Supabase sin definir un tipo para cada una.
struct JSONValue {
    let raw: Any?
    init(_ raw: Any?) { self.raw = raw }

    subscript(key: String) -> JSONValue { JSONValue((raw as? [String: Any])?[key]) }
    var array: [JSONValue] { (raw as? [Any])?.map { JSONValue($0) } ?? [] }
    var dict: [String: Any]? { raw as? [String: Any] }
    var isNull: Bool { raw == nil || raw is NSNull }

    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }
    var str: String { string ?? "" }
    var int: Int? {
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s) }
        return nil
    }
    var double: Double? {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s) }
        return nil
    }
    var bool: Bool? {
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return s == "true" }
        return nil
    }
    var date: Date? {
        guard let s = string else { return nil }
        return NovaDates.parse(s)
    }
}

enum NovaDates {
    private static let f1: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let f2: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parse(_ s: String) -> Date? {
        if let d = f1.date(from: s) ?? f2.date(from: s) { return d }
        // Postgres puede devolver «2026-10-31 12:00:00.123456+00» o microsegundos.
        var t = s.replacingOccurrences(of: " ", with: "T")
        if let r = t.range(of: "\\.(\\d{3})\\d+", options: .regularExpression) {
            let ms = t[r].prefix(4)
            t.replaceSubrange(r, with: ms)
        }
        if t.hasSuffix("+00") { t += ":00" }
        return f1.date(from: t) ?? f2.date(from: t)
    }
}

// MARK: - Errores

enum NovaError: Error, LocalizedError {
    case offline
    case server(String, String)    // código, mensaje
    case notSignedIn
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "No se pudo conectar con Nova. Revisa tu conexión e inténtalo de nuevo."
        case .notSignedIn: return "Tu sesión ha caducado. Vuelve a iniciar sesión."
        case .invalid(let m): return m
        case .server(let code, let msg): return NovaError.friendly(code: code, message: msg)
        }
    }

    var code: String { if case .server(let c, _) = self { return c }; return "" }

    /// Mensajes en español como en la web y en Nova Windows.
    static func friendly(code: String, message: String) -> String {
        let m = (code + " " + message).lowercased()
        if m.contains("invalid login credentials") || m.contains("invalid_credentials") { return "Correo o contraseña incorrectos." }
        if m.contains("email not confirmed") || m.contains("email_not_confirmed") { return "Confirma tu correo antes de entrar." }
        if m.contains("already registered") || m.contains("user_already_exists") { return "Ya existe una cuenta con ese correo." }
        if m.contains("rate limit") || m.contains("over_email_send_rate_limit") || m.contains("429") { return "Demasiados intentos. Espera un momento e inténtalo de nuevo." }
        if m.contains("expired") || m.contains("otp") || m.contains("invalid") && m.contains("code") { return "El código no es correcto o ha caducado." }
        if m.contains("weak") || m.contains("password should") { return "La contraseña es demasiado débil. Usa al menos 8 caracteres." }
        if m.contains("same_password") || m.contains("should be different") { return "La contraseña nueva debe ser distinta de la anterior." }
        if m.contains("jwt") || m.contains("401") { return "Tu sesión ha caducado. Vuelve a iniciar sesión." }
        return message.isEmpty ? "Algo ha fallado. Inténtalo de nuevo." : message
    }
}

// MARK: - Sesión

struct NovaSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String
    var displayName: String
    var createdAt: Date?

    /// Nivel de seguridad del token (aal1 / aal2), leído del propio JWT.
    var aal: String {
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return "aal1" }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "aal1" }
        return obj["aal"] as? String ?? "aal1"
    }

    static func from(_ j: JSONValue) -> NovaSession? {
        guard let access = j["access_token"].string, let refresh = j["refresh_token"].string else { return nil }
        let expiresIn = j["expires_in"].double ?? 3600
        let expiresAt = j["expires_at"].double.map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(expiresIn)
        let user = j["user"]
        return NovaSession(accessToken: access, refreshToken: refresh, expiresAt: expiresAt,
                           userId: user["id"].str, email: user["email"].str,
                           displayName: user["user_metadata"]["display_name"].str,
                           createdAt: user["created_at"].date)
    }
}

/// La sesión se guarda en el llavero del iPhone (solo este dispositivo).
enum SessionKeychain {
    private static let service = "com.nova.browser.account"
    private static let account = "session"

    static func load() -> NovaSession? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(NovaSession.self, from: data)
    }

    static func save(_ s: NovaSession?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let s = s, let data = try? JSONEncoder().encode(s) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Cliente

actor NovaClient {
    static let shared = NovaClient()

    private(set) var session: NovaSession?
    private var refreshing: Task<NovaSession?, Never>?
    private let http: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init() { session = SessionKeychain.load() }

    func currentSession() -> NovaSession? { session }

    func setSession(_ s: NovaSession?) {
        session = s
        SessionKeychain.save(s)
    }

    // MARK: Petición base

    private func send(_ path: String, method: String = "POST", query: [URLQueryItem] = [], json: Any? = nil,
                      body: Data? = nil, contentType: String? = nil, extraHeaders: [String: String] = [:],
                      auth: Bool = true) async throws -> (Data, Int) {
        var comps = URLComponents(url: NovaConfig.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(NovaConfig.key, forHTTPHeaderField: "apikey")
        if auth, let token = try await validToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json = json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body = body {
            req.httpBody = body
            if let ct = contentType { req.setValue(ct, forHTTPHeaderField: "Content-Type") }
        }
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await http.data(for: req)
            return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw NovaError.offline
        }
    }

    private func parse(_ data: Data, _ status: Int) throws -> JSONValue {
        let obj = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        let j = JSONValue(obj)
        if !(200..<300).contains(status) {
            let code = j["error_code"].string ?? j["code"].string ?? j["error"].string ?? String(status)
            let msg = j["msg"].string ?? j["message"].string ?? j["error_description"].string ?? ""
            throw NovaError.server(code, msg)
        }
        return j
    }

    /// Token válido: si va a caducar en menos de un minuto se renueva antes.
    private func validToken() async throws -> String? {
        guard let s = session else { return nil }
        if s.expiresAt.timeIntervalSinceNow > 60 { return s.accessToken }
        return await refresh()?.accessToken
    }

    @discardableResult
    func refresh() async -> NovaSession? {
        if let t = refreshing { return await t.value }
        guard let s = session else { return nil }
        let t = Task<NovaSession?, Never> { [http] in
            var comps = URLComponents(url: NovaConfig.url.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            var req = URLRequest(url: comps.url!)
            req.httpMethod = "POST"
            req.setValue(NovaConfig.key, forHTTPHeaderField: "apikey")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
            guard let res = try? await http.data(for: req) else { return s }   // sin red: se conserva
            let status = (res.1 as? HTTPURLResponse)?.statusCode ?? 0
            let obj = try? JSONSerialization.jsonObject(with: res.0)
            if (200..<300).contains(status), let ns = NovaSession.from(JSONValue(obj)) { return ns }
            return (400..<500).contains(status) ? nil : s
        }
        refreshing = t
        let ns = await t.value
        refreshing = nil
        if ns != session { setSession(ns) }
        return ns
    }

    // MARK: Autenticación

    func signIn(email: String, password: String) async throws -> NovaSession {
        let (d, st) = try await send("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                     json: ["email": email, "password": password], auth: false)
        guard let s = NovaSession.from(try parse(d, st)) else { throw NovaError.invalid("No se pudo iniciar sesión.") }
        setSession(s)
        return s
    }

    /// Devuelve la sesión si la cuenta entra directamente; nil si hay que confirmar el correo con un código.
    func signUp(email: String, password: String, name: String) async throws -> NovaSession? {
        let (d, st) = try await send("auth/v1/signup", json: ["email": email, "password": password, "data": ["display_name": name]], auth: false)
        let j = try parse(d, st)
        // Supabase devuelve un usuario sin identidades cuando el correo ya existe.
        let user = j["user"].isNull ? j : j["user"]
        if let ids = user["identities"].raw as? [Any], ids.isEmpty { throw NovaError.invalid("Ya existe una cuenta con ese correo.") }
        if let s = NovaSession.from(j) { setSession(s); return s }
        return nil
    }

    /// Código del correo: tipo «email» (confirmar cuenta) o «recovery» (contraseña olvidada).
    func verifyEmailCode(email: String, code: String, type: String) async throws -> NovaSession {
        let (d, st) = try await send("auth/v1/verify", json: ["type": type, "email": email, "token": code], auth: false)
        guard let s = NovaSession.from(try parse(d, st)) else { throw NovaError.invalid("El código no es correcto o ha caducado.") }
        setSession(s)
        return s
    }

    func resendSignup(email: String) async throws {
        let (d, st) = try await send("auth/v1/resend", json: ["type": "signup", "email": email], auth: false)
        _ = try parse(d, st)
    }

    func sendRecovery(email: String) async throws {
        let (d, st) = try await send("auth/v1/recover", json: ["email": email], auth: false)
        _ = try parse(d, st)
    }

    func updatePassword(_ password: String) async throws {
        let (d, st) = try await send("auth/v1/user", method: "PUT", json: ["password": password])
        _ = try parse(d, st)
    }

    func signOut() async {
        if session != nil { _ = try? await send("auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")]) }
        setSession(nil)
    }

    // MARK: Verificación en dos pasos (Google Authenticator)

    /// Factor TOTP verificado de la cuenta, si lo tiene.
    func verifiedTotpFactor() async -> String? {
        guard let res = try? await send("auth/v1/user", method: "GET"), let j = try? parse(res.0, res.1) else { return nil }
        return j["factors"].array.first { $0["factor_type"].str == "totp" && $0["status"].str == "verified" }?["id"].string
    }

    /// true si la cuenta tiene 2 pasos y esta sesión aún no ha pasado el código.
    func needsSecondFactor() async -> Bool {
        guard let s = session, s.aal != "aal2" else { return false }
        return await verifiedTotpFactor() != nil
    }

    func verifyTotp(code: String) async throws {
        guard let factor = await verifiedTotpFactor() else { throw NovaError.invalid("Tu cuenta no tiene verificación en dos pasos.") }
        let (d1, s1) = try await send("auth/v1/factors/\(factor)/challenge", json: [String: Any]())
        let challenge = try parse(d1, s1)["id"].str
        let (d2, s2) = try await send("auth/v1/factors/\(factor)/verify", json: ["challenge_id": challenge, "code": code])
        let j = try parse(d2, s2)
        guard var ns = NovaSession.from(j) else { throw NovaError.invalid("El código no es correcto.") }
        if ns.userId.isEmpty, let old = session { ns.userId = old.userId; ns.email = old.email; ns.displayName = old.displayName; ns.createdAt = old.createdAt }
        setSession(ns)
    }

    // MARK: Funciones (RPC) y tablas

    func rpc(_ name: String, _ params: [String: Any] = [:]) async throws -> JSONValue {
        guard session != nil else { throw NovaError.notSignedIn }
        var (d, st) = try await send("rest/v1/rpc/\(name)", json: params)
        if st == 401, await refresh() != nil { (d, st) = try await send("rest/v1/rpc/\(name)", json: params) }
        return try parse(d, st)
    }

    /// RPC que no debe romper nada si falla (listas, estado…).
    func tryRPC(_ name: String, _ params: [String: Any] = [:]) async -> JSONValue? {
        try? await rpc(name, params)
    }

    func select(_ table: String, query: [URLQueryItem]) async -> JSONValue? {
        guard let res = try? await send("rest/v1/\(table)", method: "GET", query: query) else { return nil }
        return try? parse(res.0, res.1)
    }

    func update(_ table: String, match: [URLQueryItem], values: [String: Any]) async {
        _ = try? await send("rest/v1/\(table)", method: "PATCH", query: match, json: values, extraHeaders: ["Prefer": "return=minimal"])
    }

    // MARK: Fotos (Storage)

    /// Enlaces firmados (6 h) para fotos privadas de perfil o de grupos.
    func signedURLs(bucket: String, paths: [String]) async -> [String: URL] {
        let want = Array(Set(paths.filter { !$0.isEmpty }))
        guard !want.isEmpty, session != nil,
              let res = try? await send("storage/v1/object/sign/\(bucket)", json: ["expiresIn": 21600, "paths": want]),
              let j = try? parse(res.0, res.1) else { return [:] }
        var out: [String: URL] = [:]
        for item in j.array {
            guard let p = item["path"].string, let rel = item["signedURL"].string ?? item["signedUrl"].string, item["error"].isNull else { continue }
            if let u = URL(string: NovaConfig.url.absoluteString + "/storage/v1" + rel) { out[p] = u }
        }
        return out
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        let (d, st) = try await send("storage/v1/object/\(bucket)/\(path)", body: data, contentType: contentType,
                                     extraHeaders: ["x-upsert": "false", "cache-control": "max-age=31536000"])
        _ = try parse(d, st)
    }

    func remove(bucket: String, paths: [String]) async {
        guard !paths.isEmpty else { return }
        _ = try? await send("storage/v1/object/\(bucket)", method: "DELETE", json: ["prefixes": paths])
    }
}
