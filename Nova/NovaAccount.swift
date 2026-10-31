import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════════════════════════════
//  Cuenta Nova en iOS: perfil, amigos, solicitudes, conversaciones y grupos.
//  Usa las mismas funciones de Supabase que Nova Windows y la web.
// ════════════════════════════════════════════════════════════════════════════════════

// MARK: - Modelos

enum NovaStatus: String, CaseIterable, Identifiable {
    case online, busy, away, dnd, invisible, offline
    var id: String { rawValue }
    var title: String {
        switch self {
        case .online: return "En línea"
        case .busy: return "Ocupado"
        case .away: return "Ausente"
        case .dnd: return "No molestar"
        case .invisible: return "Invisible"
        case .offline: return "Desconectado"
        }
    }
    var color: Color {
        switch self {
        case .online: return Color(hex: 0x3DDC97)
        case .busy, .dnd: return Color(hex: 0xFF5A6E)
        case .away: return Color(hex: 0xFFB547)
        case .invisible, .offline: return Color(hex: 0x8A8698)
        }
    }
    var order: Int {
        switch self {
        case .online: return 0
        case .busy, .dnd: return 1
        case .away: return 2
        default: return 3
        }
    }
    /// Los que se pueden elegir (desconectado lo pone Nova solo).
    static let selectable: [NovaStatus] = [.online, .busy, .away, .dnd, .invisible]
    static func from(_ s: String) -> NovaStatus { NovaStatus(rawValue: s) ?? .offline }
}

struct ProfileField: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var value: String
}

struct MyProfile {
    var userId = ""
    var email = ""
    var name = ""
    var username = ""
    var pronouns = ""
    var bio = ""
    var about = ""
    var fields: [ProfileField] = []
    var avatarColor = "#7b6cff"
    var avatarURL: URL?
    var bannerURL: URL?
    var avatarData = ""
    var themePrimary = ""
    var themeAccent = ""
    var decoration = "none"
    var showMemberSince = true
    var showBadges = true
    var memberSince: Date?
    var friendCode = ""
    var isPremium = false
    var role = "user"
    var badges: [String] = []
    var status: NovaStatus = .online
}

struct Friend: Identifiable, Equatable {
    let id: String
    var name: String
    var username: String
    var avatarColor: String
    var avatarURL: URL?
    var status: NovaStatus
    var activity: String

    var statusLine: String {
        if !activity.isEmpty { return activity }
        return (username.isEmpty ? "" : "@\(username) · ") + status.title
    }
}

struct FriendRequest: Identifiable, Equatable {
    let id: String
    var name: String
    var avatarColor: String
    var avatarURL: URL?
}

struct Conversation: Equatable {
    var id: String
    var unread: Int
    var lastBody: String
    var lastSender: String
    var lastAt: Date?
}

struct GroupMember: Identifiable, Equatable {
    let id: String
    var name: String
    var username: String
    var avatarColor: String
    var avatarURL: URL?
    var status: NovaStatus
    var owner: Bool
    var lastRead: Int
}

struct NovaGroup: Identifiable, Equatable {
    let id: String
    var name: String
    var iconURL: URL?
    var ownerId: String
    var unread: Int
    var lastAt: Date?
    var lastBody: String
    var lastSender: String
    var members: [GroupMember]
}

/// Una fila de la lista de chats: un amigo o un grupo.
enum ChatTarget: Identifiable, Hashable {
    case friend(String)
    case group(String)
    var id: String {
        switch self {
        case .friend(let f): return "f:" + f
        case .group(let g): return "g:" + g
        }
    }
}

// MARK: - Estado de la cuenta

@MainActor
final class NovaAccount: ObservableObject {
    static let shared = NovaAccount()

    enum Phase: Equatable { case loading, signedOut, needsTotp, signedIn }

    @Published private(set) var phase: Phase = .loading
    @Published var me = MyProfile()
    @Published var friends: [Friend] = []
    @Published var requests: [FriendRequest] = []
    @Published var conversations: [String: Conversation] = [:]   // id de amigo → conversación
    @Published var groups: [NovaGroup] = []
    @Published var lastError: String?
    @Published var toast: String?

    private let client = NovaClient.shared
    private var refreshTimer: Timer?
    private var presenceTimer: Timer?
    private var toastWork: DispatchWorkItem?

    var unreadTotal: Int {
        conversations.values.reduce(0) { $0 + $1.unread } + groups.reduce(0) { $0 + $1.unread }
    }
    var onlineFriends: Int { friends.filter { $0.status != .offline && $0.status != .invisible }.count }

    private init() {
        Task { await bootstrap() }
    }

    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }
    func group(_ id: String) -> NovaGroup? { groups.first { $0.id == id } }

    // MARK: Arranque y sesión

    private func bootstrap() async {
        guard await client.currentSession() != nil else { phase = .signedOut; return }
        _ = await client.refresh()
        guard await client.currentSession() != nil else { phase = .signedOut; return }
        if await client.needsSecondFactor() { phase = .needsTotp; return }
        await enter()
    }

    private func enter() async {
        phase = .signedIn
        await reloadAll()
        startTimers()
        setPresence(me.status == .offline ? .online : me.status)
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.signIn(email: email.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
        if await client.needsSecondFactor() { phase = .needsTotp; return }
        await enter()
    }

    /// true si ya ha entrado; false si hay que poner el código del correo.
    func signUp(name: String, email: String, password: String) async throws -> Bool {
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        if let s = try await client.signUp(email: mail, password: password, name: name) {
            await setInitialColor(userId: s.userId, email: mail)
            await enter()
            return true
        }
        return false
    }

    func confirmSignup(email: String, code: String) async throws {
        let mail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let s = try await client.verifyEmailCode(email: mail, code: code, type: "email")
        await setInitialColor(userId: s.userId, email: mail)
        await enter()
    }

    func resendSignup(email: String) async throws { try await client.resendSignup(email: email.lowercased()) }
    func sendRecovery(email: String) async throws { try await client.sendRecovery(email: email.trimmingCharacters(in: .whitespaces).lowercased()) }

    /// Contraseña olvidada: código del correo + (si tiene) Google Authenticator + contraseña nueva.
    func resetPassword(email: String, code: String, totp: String?, newPassword: String) async throws {
        _ = try await client.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces).lowercased(), code: code, type: "recovery")
        if await client.needsSecondFactor() {
            guard let t = totp, t.count == 6 else { throw NovaError.invalid("Escribe también el código de Google Authenticator.") }
            try await client.verifyTotp(code: t)
        }
        try await client.updatePassword(newPassword)
        await enter()
    }

    func recoveryNeedsTotp() async -> Bool { await client.needsSecondFactor() }

    func verifyTotp(_ code: String) async throws {
        try await client.verifyTotp(code: code)
        await enter()
    }

    func cancelTotp() async {
        await client.signOut()
        phase = .signedOut
    }

    func signOut() async {
        stopTimers()
        _ = await client.tryRPC("nova_go_offline")
        await client.signOut()
        me = MyProfile(); friends = []; requests = []; conversations = [:]; groups = []
        phase = .signedOut
        flash("Has cerrado la sesión")
    }

    private func setInitialColor(userId: String, email: String) async {
        let colors = ["#7b6cff", "#ff6f91", "#3fb8ff", "#38d39f", "#ffb547", "#c77dff", "#ff8a5c", "#5ad1e6"]
        var h: Int32 = 7
        for c in email.unicodeScalars { h = h &* 31 &+ Int32(truncatingIfNeeded: c.value) }
        let color = colors[Int(abs(Int64(h)) % Int64(colors.count))]
        await client.update("profiles", match: [URLQueryItem(name: "id", value: "eq.\(userId)")], values: ["avatar_color": color])
    }

    // MARK: Cargar datos

    func reloadAll() async {
        guard let session = await client.currentSession() else { return }
        var p = MyProfile()
        p.userId = session.userId
        p.email = session.email
        p.status = me.status
        let prof = await client.tryRPC("nova_get_profile", ["p_user": NSNull()])
        if let j = prof, j["result"].str == "ok" {
            p.name = j["name"].str
            p.username = j["username"].str
            p.pronouns = j["pronouns"].str
            p.bio = j["bio"].str
            p.about = j["about"].str
            p.fields = j["fields"].array.prefix(3).map { ProfileField(label: $0["label"].str, value: $0["value"].str) }
            p.avatarColor = j["avatar_color"].string ?? p.avatarColor
            p.avatarData = j["avatar_data"].str
            p.themePrimary = j["theme_primary"].str
            p.themeAccent = j["theme_accent"].str
            p.decoration = j["decoration"].string ?? "none"
            p.showMemberSince = j["privacy"]["show_member_since"].bool ?? true
            p.showBadges = j["privacy"]["show_badges"].bool ?? true
            p.memberSince = j["member_since"].date
            p.badges = j["badges"].array.compactMap { $0["name"].string }
            let paths = [j["avatar_still_path"].str, j["avatar_path"].str, j["banner_still_path"].str, j["banner_path"].str]
            let signed = await client.signedURLs(bucket: NovaConfig.mediaBucket, paths: paths)
            p.avatarURL = signed[stillOrMain(j["avatar_path"].str, j["avatar_still_path"].str)]
            p.bannerURL = signed[stillOrMain(j["banner_path"].str, j["banner_still_path"].str)]
        }
        if p.name.isEmpty { p.name = session.displayName.isEmpty ? String(session.email.split(separator: "@").first ?? "Usuario") : session.displayName }
        if p.memberSince == nil { p.memberSince = session.createdAt }
        if let prem = await client.tryRPC("nova_get_premium_style", ["p_user": NSNull()]), prem["result"].str == "ok" {
            p.isPremium = prem["is_premium"].bool == true
        }
        if let roles = await client.select("nova_account_roles", query: [URLQueryItem(name: "select", value: "role"),
                                                                          URLQueryItem(name: "user_id", value: "eq.\(session.userId)")]) {
            p.role = roles.array.first?["role"].string ?? "user"
        }
        if let code = await client.tryRPC("nova_my_friend_code"), let c = code.string { p.friendCode = c }
        me = p
        await reloadSocial(includeFriends: true)
    }

    /// GIF animado → se usa la imagen fija (las fotos animadas son de Premium en el ordenador).
    private func stillOrMain(_ main: String, _ still: String) -> String {
        main.lowercased().hasSuffix(".gif") && !still.isEmpty ? still : main
    }

    func reloadSocial(includeFriends: Bool) async {
        guard phase == .signedIn else { return }
        if includeFriends {
            let list = await client.tryRPC("nova_list_friends")?.array ?? []
            let media = await client.tryRPC("nova_list_friends_media")?.array ?? []
            var mediaBy: [String: JSONValue] = [:]
            for m in media { mediaBy[m["id"].str] = m }
            let paths = media.map { stillOrMain($0["avatar_path"].str, $0["avatar_still_path"].str) }
            let signed = await client.signedURLs(bucket: NovaConfig.mediaBucket, paths: paths)
            friends = list.map { f in
                let id = f["id"].str
                let m = mediaBy[id]
                let path = m.map { stillOrMain($0["avatar_path"].str, $0["avatar_still_path"].str) } ?? ""
                return Friend(id: id, name: f["name"].string ?? "Usuario", username: m?["username"].str ?? "",
                              avatarColor: f["avatar_color"].string ?? "#7b6cff",
                              avatarURL: signed[path] ?? Self.dataURL(f["avatar_data"].str),
                              status: NovaStatus.from(f["status"].str), activity: f["activity"].str)
            }
        }
        let reqs = await client.tryRPC("nova_list_requests")?.array ?? []
        requests = reqs.map { r in
            FriendRequest(id: r["id"].str, name: r["name"].string ?? "Usuario", avatarColor: r["avatar_color"].string ?? "#7b6cff",
                          avatarURL: Self.dataURL(r["avatar_data"].str))
        }
        if let convs = await client.tryRPC("nova_list_conversations") {
            var map: [String: Conversation] = [:]
            for c in convs.array {
                map[c["friend_id"].str] = Conversation(id: c["conversation_id"].str, unread: c["unread"].int ?? 0,
                                                       lastBody: c["last_body"].str, lastSender: c["last_sender"].str, lastAt: c["last_at"].date)
            }
            conversations = map
        }
        await reloadGroups()
        updateAppBadge()
    }

    func reloadGroups() async {
        guard let rows = await client.tryRPC("nova_list_groups")?.array else { return }
        let memberPaths = rows.flatMap { g in g["members"].array.map { stillOrMain($0["avatar_path"].str, $0["avatar_still_path"].str) } }
        let signed = await client.signedURLs(bucket: NovaConfig.mediaBucket, paths: memberPaths)
        let icons = await client.signedURLs(bucket: NovaConfig.groupBucket, paths: rows.map { $0["icon_path"].str })
        groups = rows.map { g in
            NovaGroup(id: g["id"].str, name: String((g["name"].string ?? "Grupo").prefix(40)), iconURL: icons[g["icon_path"].str],
                      ownerId: g["owner_id"].str, unread: g["unread"].int ?? 0,
                      lastAt: g["last_message_at"].date ?? g["created_at"].date,
                      lastBody: g["last"]["deleted"].bool == true ? "Mensaje eliminado" : g["last"]["body"].str,
                      lastSender: g["last"]["sender_id"].str,
                      members: g["members"].array.map { m in
                          GroupMember(id: m["id"].str, name: m["name"].string ?? "Usuario", username: m["username"].str,
                                      avatarColor: m["avatar_color"].string ?? "#7b6cff",
                                      avatarURL: signed[stillOrMain(m["avatar_path"].str, m["avatar_still_path"].str)],
                                      status: NovaStatus.from(m["status"].str), owner: m["owner"].bool == true,
                                      lastRead: m["last_read_id"].int ?? 0)
                      })
        }
    }

    static func dataURL(_ s: String) -> URL? {
        guard s.hasPrefix("data:image/") || s.hasPrefix("https://") else { return nil }
        return URL(string: s)
    }

    /// Lista de chats: grupos y amigos, lo más reciente arriba.
    var chatTargets: [ChatTarget] {
        let g: [(ChatTarget, Date)] = groups.map { (.group($0.id), $0.lastAt ?? .distantPast) }
        let f: [(ChatTarget, Date)] = friends.map { (.friend($0.id), conversations[$0.id]?.lastAt ?? .distantPast) }
        return (g + f).sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.id < b.0.id
        }.map { $0.0 }
    }

    // MARK: Temporizadores: actualizar y estado «en línea»

    private func startTimers() {
        stopTimers()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reloadSocial(includeFriends: true) }
        }
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.setPresence(self.me.status)
            }
        }
    }

    private func stopTimers() {
        refreshTimer?.invalidate(); refreshTimer = nil
        presenceTimer?.invalidate(); presenceTimer = nil
    }

    /// Al volver a la app / al irse a segundo plano.
    func appBecameActive() {
        guard phase == .signedIn else { return }
        startTimers()
        setPresence(me.status)
        Task { await reloadSocial(includeFriends: true) }
    }

    func appWentBackground() {
        guard phase == .signedIn else { return }
        stopTimers()
        Task { _ = await client.tryRPC("nova_go_offline") }
    }

    func setPresence(_ status: NovaStatus) {
        let s = status == .offline ? NovaStatus.online : status
        me.status = s
        Task { _ = await client.tryRPC("nova_set_presence", ["p_status": s.rawValue, "p_activity": NSNull()]) }
    }

    private func updateAppBadge() {
        // Sin permiso de notificaciones no se puede poner el número en el icono; se deja preparado.
    }

    // MARK: Amigos

    enum CodePreview: Equatable {
        case none, notFound
        case user(name: String, color: String, avatar: URL?, note: String)
    }

    static func parseCode(_ input: String) -> String {
        var t = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if let r = t.range(of: "(?:add|friend|invite|amigo)/([^\\s?#]+)", options: [.regularExpression, .caseInsensitive]) {
            t = String(t[r]).components(separatedBy: "/").last ?? t
        }
        let c = t.replacingOccurrences(of: "[\\s-]+", with: "", options: .regularExpression).uppercased()
        return c.range(of: "^[A-HJ-NP-Z2-9]{8}$", options: .regularExpression) != nil ? c : ""
    }

    static func formatCode(_ c: String) -> String { c.count == 8 ? "\(c.prefix(4))-\(c.suffix(4))" : c }

    func previewCode(_ code: String) async -> CodePreview {
        guard let j = await client.tryRPC("nova_preview_code", ["p_code": code]) else { return .none }
        guard let name = j["name"].string else { return .notFound }
        let notes = ["self": "Es tu propio código", "already_friends": "Ya es tu amigo", "already_sent": "Ya le enviaste una solicitud",
                     "incoming": "Te envió una solicitud: pulsa Añadir para aceptarla"]
        return .user(name: name, color: j["avatar_color"].string ?? "#7b6cff", avatar: Self.dataURL(j["avatar_data"].str),
                     note: notes[j["result"].str] ?? "Pulsa Añadir para enviarle una solicitud")
    }

    /// Devuelve (mensaje, correcto).
    func addFriend(code: String) async -> (String, Bool) {
        do {
            let j = try await client.rpc("nova_add_friend", ["p_code": code])
            let name = j["name"].str
            let msgs: [String: (String, Bool)] = [
                "sent": ("Solicitud enviada a \(name).", true), "accepted": ("¡\(name) y tú ya sois amigos!", true),
                "already_sent": ("Ya le enviaste una solicitud a \(name).", true), "already_friends": ("\(name) ya es tu amigo.", false),
                "self": ("Ese es tu propio código.", false), "too_many": ("Tienes demasiadas solicitudes pendientes.", false)]
            let r = msgs[j["result"].str] ?? ("No hay ningún usuario con ese código.", false)
            if r.1 { await reloadSocial(includeFriends: true) }
            return r
        } catch {
            return ((error as? LocalizedError)?.errorDescription ?? "No se pudo añadir al amigo.", false)
        }
    }

    func respond(_ req: FriendRequest, accept: Bool) async {
        requests.removeAll { $0.id == req.id }
        do {
            let j = try await client.rpc("nova_respond_request", ["p_id": req.id, "p_accept": accept])
            flash(j["result"].str == "not_found" ? "Esa solicitud ya no existe" : accept ? "\(req.name) y tú ya sois amigos" : "Solicitud rechazada")
        } catch { flash("No se pudo responder a la solicitud") }
        await reloadSocial(includeFriends: true)
    }

    func removeFriend(_ f: Friend) async {
        do {
            _ = try await client.rpc("nova_remove_friend", ["p_friend": f.id])
            friends.removeAll { $0.id == f.id }
            flash("\(f.name) ya no está en tus amigos")
        } catch { flash("No se pudo eliminar al amigo") }
        await reloadSocial(includeFriends: true)
    }

    // MARK: Perfil de otra persona

    struct PublicProfile {
        var name = "", username = "", pronouns = "", bio = "", about = ""
        var fields: [ProfileField] = []
        var avatarColor = "#7b6cff", themePrimary = "", themeAccent = "", decoration = "none"
        var avatarURL: URL?, bannerURL: URL?
        var memberSince: Date?
        var isPremium = false, isOwner = false
        var badges: [String] = []
    }

    func loadProfile(_ userId: String) async -> PublicProfile? {
        guard let j = await client.tryRPC("nova_get_profile", ["p_user": userId]), j["result"].str == "ok" else { return nil }
        var p = PublicProfile()
        p.name = j["name"].string ?? "Usuario"; p.username = j["username"].str; p.pronouns = j["pronouns"].str
        p.bio = j["bio"].str; p.about = j["about"].str
        p.fields = j["fields"].array.prefix(3).map { ProfileField(label: $0["label"].str, value: $0["value"].str) }
        p.avatarColor = j["avatar_color"].string ?? p.avatarColor
        p.themePrimary = j["theme_primary"].str; p.themeAccent = j["theme_accent"].str; p.decoration = j["decoration"].string ?? "none"
        p.memberSince = (j["privacy"]["show_member_since"].bool ?? true) ? j["member_since"].date : nil
        if j["privacy"]["show_badges"].bool ?? true { p.badges = j["badges"].array.compactMap { $0["name"].string } }
        let signed = await client.signedURLs(bucket: NovaConfig.mediaBucket,
                                             paths: [stillOrMain(j["avatar_path"].str, j["avatar_still_path"].str),
                                                     stillOrMain(j["banner_path"].str, j["banner_still_path"].str)])
        p.avatarURL = signed[stillOrMain(j["avatar_path"].str, j["avatar_still_path"].str)] ?? Self.dataURL(j["avatar_data"].str)
        p.bannerURL = signed[stillOrMain(j["banner_path"].str, j["banner_still_path"].str)]
        if let prem = await client.tryRPC("nova_get_premium_style", ["p_user": userId]) { p.isPremium = prem["is_premium"].bool == true }
        if let roles = await client.select("nova_account_roles", query: [URLQueryItem(name: "select", value: "role"),
                                                                          URLQueryItem(name: "user_id", value: "eq.\(userId)")]) {
            p.isOwner = roles.array.first?["role"].str == "owner"
        }
        return p
    }

    // MARK: Guardar perfil

    static let saveMessages: [String: String] = [
        "username_taken": "Ese nombre de usuario ya está en uso.",
        "username_reserved": "Ese nombre de usuario está reservado.",
        "username_invalid": "El nombre de usuario debe tener 3–20 caracteres: letras minúsculas, números, punto o guion bajo.",
        "name_invalid": "El nombre visible debe tener entre 2 y 24 caracteres.",
        "bio_too_long": "La descripción es demasiado larga.",
        "premium_required": "Eso es de Nova Premium.",
    ]

    static func validUsername(_ u: String) -> Bool {
        u.range(of: "^[a-z0-9_.]{3,20}$", options: .regularExpression) != nil && !u.hasPrefix(".") && !u.hasSuffix(".") && !u.contains("..")
    }

    func usernameAvailable(_ u: String) async -> Bool? {
        guard let j = await client.tryRPC("nova_username_available", ["p_username": u]) else { return nil }
        if let b = j.bool { return b }
        if let r = j["result"].string { return r == "ok" || r == "available" }
        return j["available"].bool
    }

    /// avatar/banner: nil = sin cambios, .some(nil) = quitar, .some(data) = foto nueva (PNG).
    func saveProfile(_ draft: MyProfile, avatar: Data??, banner: Data??) async throws {
        guard let session = await client.currentSession() else { throw NovaError.notSignedIn }
        var data: [String: Any] = [
            "name": draft.name.trimmingCharacters(in: .whitespaces),
            "username": draft.username.trimmingCharacters(in: .whitespaces).lowercased(),
            "pronouns": draft.pronouns.trimmingCharacters(in: .whitespaces),
            "bio": draft.bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "about": draft.about.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
            "fields": draft.fields.map { ["label": $0.label.trimmingCharacters(in: .whitespaces), "value": $0.value.trimmingCharacters(in: .whitespaces)] }
                .filter { !($0["label"] ?? "").isEmpty || !($0["value"] ?? "").isEmpty },
            "avatar_color": draft.avatarColor,
            "theme_primary": draft.themePrimary,
            "theme_accent": draft.themeAccent,
            "decoration": draft.decoration,
            "show_member_since": draft.showMemberSince,
            "show_badges": draft.showBadges,
        ]
        var uploaded: [String] = []
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        do {
            if let a = avatar {
                if let png = a {
                    let path = "\(session.userId)/avatar-\(stamp).png"
                    try await client.upload(bucket: NovaConfig.mediaBucket, path: path, data: png, contentType: "image/png")
                    uploaded.append(path)
                    data["avatar"] = ["path": path, "still_path": NSNull()]
                } else { data["avatar"] = NSNull() }
            }
            if let b = banner {
                if let png = b {
                    let path = "\(session.userId)/banner-\(stamp + 1).png"
                    try await client.upload(bucket: NovaConfig.mediaBucket, path: path, data: png, contentType: "image/png")
                    uploaded.append(path)
                    data["banner"] = ["path": path, "still_path": NSNull()]
                } else { data["banner"] = NSNull() }
            }
            var res: JSONValue
            do { res = try await client.rpc("nova_save_profile_v3", ["p_data": data]) }
            catch let e as NovaError where e.code == "PGRST202" || e.code == "42883" {
                res = try await client.rpc("nova_save_profile", ["p_data": data])
            }
            guard res["result"].str == "ok" else {
                throw NovaError.invalid(Self.saveMessages[res["result"].str] ?? "No se pudo guardar el perfil. Inténtalo de nuevo.")
            }
            let old = res["old_paths"].array.compactMap { $0.string }.filter { $0.hasPrefix("\(session.userId)/") }
            await client.remove(bucket: NovaConfig.mediaBucket, paths: old)
        } catch {
            await client.remove(bucket: NovaConfig.mediaBucket, paths: uploaded)
            throw error
        }
        await reloadAll()
        flash("Perfil guardado. También lo verás así en Nova.")
    }

    // MARK: Avisos

    func flash(_ text: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        let w = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: w)
    }
}

// MARK: - Utilidades de color

extension Color {
    /// «#7b6cff» → Color (si no es válido, el violeta de Nova).
    init(novaHex: String, fallback: UInt32 = 0x7B6CFF) {
        let s = novaHex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if s.count == 6, let v = UInt32(s, radix: 16) { self.init(hex: v) } else { self.init(hex: fallback) }
    }

    /// Color → «#rrggbb».
    var novaHexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
