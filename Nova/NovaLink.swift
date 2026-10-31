import SwiftUI
import WebKit
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import PhotosUI

// ════════════════════════════════════════════════════════════════════════════════════
//  Enlace con Nova para Windows (v88): emparejar, Puente móvil, Transferencias,
//  pestañas del PC que se ejecutan en este iPhone y gestor de archivos de Nova.
//
//  · Supabase (nova_devices) solo guarda «este dispositivo existe y su dirección en tu
//    wifi». Todo lo demás viaja DIRECTO entre el iPhone y el PC por la red local
//    (WebSocket que abre Nova en el PC). Nada se sube a la nube.
// ════════════════════════════════════════════════════════════════════════════════════

/// Sin aislamiento de actor: lo lee BrowserTab al terminar de cargar una página.
enum NovaLinkFlags { static var linked = false }

struct LinkDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var platform: String
    var ips: [String]
    var port: Int
    var token: String
    var updatedAt: Date?
}

struct LinkTab: Identifiable, Equatable {
    var id: String
    var title: String
    var url: String
}

struct LinkFileItem: Identifiable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var dir: Bool
    var size: Int64
}

struct LinkTransfer: Identifiable, Equatable {
    var id: String
    var name: String
    var got: Int64
    var size: Int64
    var incoming: Bool
    var fraction: Double { size > 0 ? min(1, Double(got) / Double(size)) : 1 }
}

/// Una web del iPhone pide un archivo y el usuario eligió «Mi PC».
struct PCPickRequest: Identifiable {
    let id = UUID()
    weak var webView: WKWebView?
}

private final class IncomingFile {
    let id: String
    let name: String
    let size: Int64
    let req: String
    let url: URL
    let handle: FileHandle
    var got: Int64 = 0
    init(id: String, name: String, size: Int64, req: String, url: URL, handle: FileHandle) {
        self.id = id; self.name = name; self.size = size; self.req = req; self.url = url; self.handle = handle
    }
}

// MARK: - Archivos de Nova en este iPhone (también visibles en la app Archivos → En mi iPhone → Nova)

enum LocalFiles {
    static var root: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return u
    }
    static var received: URL {
        let u = root.appendingPathComponent("Recibidos", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// Ruta relativa ("" = raíz) → URL, siempre dentro de la carpeta de Nova.
    static func resolve(_ rel: String) -> URL? {
        let clean = rel.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        var u = root
        for part in clean { u.appendPathComponent(part) }
        let rp = root.resolvingSymlinksInPath().standardizedFileURL.path
        let up = u.resolvingSymlinksInPath().standardizedFileURL.path
        return (up == rp || up.hasPrefix(rp + "/")) ? u : nil
    }

    static func relative(_ url: URL) -> String {
        // v89 · iOS devuelve a veces /private/var/… y otras /var/…: se resuelven los enlaces antes de comparar.
        // Antes los archivos de «Recibidos» salían con una ruta mala y no se podían enviar al PC.
        let rp = root.resolvingSymlinksInPath().standardizedFileURL.path
        let up = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard up.hasPrefix(rp) else { return url.lastPathComponent }
        return String(up.dropFirst(rp.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func list(_ rel: String) -> [LinkFileItem] {
        guard let dir = resolve(rel),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.map { u -> LinkFileItem in
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = v?.isDirectory ?? false
            return LinkFileItem(name: u.lastPathComponent, path: relative(u), dir: isDir, size: Int64(v?.fileSize ?? 0))
        }
        .sorted { a, b in a.dir != b.dir ? a.dir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    static func usedBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory != true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    static func freeBytes() -> Int64 {
        let v = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func unique(in dir: URL, name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        var u = dir.appendingPathComponent(safe.isEmpty ? "archivo" : safe)
        let ext = u.pathExtension
        let base = u.deletingPathExtension().lastPathComponent
        var i = 1
        while FileManager.default.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)")
            i += 1
        }
        return u
    }

    static func mime(_ url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    static func size(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}

// MARK: - Servicio de enlace

@MainActor
final class NovaLink: ObservableObject {
    static let shared = NovaLink()

    @Published private(set) var devices: [LinkDevice] = []
    @Published private(set) var connected: LinkDevice?
    @Published private(set) var connecting = false
    @Published private(set) var pcTabs: [LinkTab] = []
    @Published private(set) var transfers: [String: LinkTransfer] = [:]
    @Published private(set) var remoteTabs: [RemoteTabHost] = [] {
        didSet { sharingChanged(was: !oldValue.isEmpty) }
    }
    @Published private(set) var pcPremium = false
    @Published var showDevices = false
    @Published var toast: String?
    @Published var pcPick: PCPickRequest?

    weak var model: BrowserModel?

    private let session = URLSession(configuration: .default)
    private var socket: URLSessionWebSocketTask?
    private var pending: [String: CheckedContinuation<JSONValue, Never>] = [:]
    private var acks: [String: CheckedContinuation<Bool, Never>] = [:]
    private var incoming: [String: IncomingFile] = [:]
    private var completedByReq: [String: URL] = [:]
    private var lastTabsKey = ""
    private var retryAt = Date.distantPast
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var toastWork: DispatchWorkItem?
    let deviceId: String
    private let token: String

    private init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "novaLink.deviceId"), id.count == 36 { deviceId = id }
        else { deviceId = UUID().uuidString.lowercased(); d.set(deviceId, forKey: "novaLink.deviceId") }
        if let t = d.string(forKey: "novaLink.token"), t.count >= 32 { token = t }
        else { token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased(); d.set(token, forKey: "novaLink.token") }
        _ = LocalFiles.received
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            Task { @MainActor in NovaLink.shared.tick() }
        }
    }

    var isPremium: Bool { pcPremium || NovaAccount.shared.me.isPremium }
    var limitBytes: Int64 { isPremium ? 2 * 1024 * 1024 * 1024 : 50 * 1024 * 1024 }
    var limitText: String { isPremium ? "2 GB" : "50 MB" }
    var deviceName: String { UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name }

    func flash(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { toast = text }
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in withAnimation { self?.toast = nil } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: w)
    }

    // MARK: Ciclo

    private func tick() {
        if socket == nil { connectIfNeeded() } else { reportTabs() }
    }

    func appBecameActive() {
        if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        retryAt = .distantPast
        connectIfNeeded()
    }

    /// iOS deja unos segundos más a Nova en segundo plano para terminar envíos y pestañas remotas.
    func appWentBackground() {
        guard socket != nil, bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "NovaLink") { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
        }
    }

    func connectIfNeeded(force: Bool = false) {
        if force { retryAt = .distantPast }
        guard socket == nil, !connecting, NovaAccount.shared.phase == .signedIn, Date() >= retryAt else { return }
        connecting = true
        Task {
            await registerSelf()
            await reloadDevices()
            let pcs = devices.filter { $0.platform == "windows" && $0.port > 0 && !$0.token.isEmpty }
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            for d in pcs {
                for ip in d.ips {
                    if await tryConnect(d, ip: ip) { connecting = false; return }
                }
            }
            connecting = false
            retryAt = Date().addingTimeInterval(10)
        }
    }

    private func registerSelf() async {
        _ = await NovaClient.shared.tryRPC("nova_device_upsert", [
            "p_id": deviceId, "p_name": String(deviceName.prefix(40)), "p_platform": "ios",
            "p_ips": [String](), "p_port": 0, "p_token": token,
            "p_version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""])
    }

    func reloadDevices() async {
        guard let rows = await NovaClient.shared.tryRPC("nova_device_list") else { return }
        devices = rows.array.map { r in
            LinkDevice(id: r["id"].str, name: r["name"].str, platform: r["platform"].str,
                       ips: r["lan_ips"].array.map { $0.str }.filter { !$0.isEmpty },
                       port: r["lan_port"].int ?? 0, token: r["link_token"].str, updatedAt: r["updated_at"].date)
        }.filter { $0.id != deviceId }
    }

    func forget(_ d: LinkDevice) async {
        _ = await NovaClient.shared.tryRPC("nova_device_remove", ["p_id": d.id])
        if connected?.id == d.id { disconnect() }
        await reloadDevices()
    }

    private func tryConnect(_ d: LinkDevice, ip: String) async -> Bool {
        var c = URLComponents()
        c.scheme = "ws"; c.host = ip; c.port = d.port; c.path = "/nova-link"
        c.queryItems = [URLQueryItem(name: "token", value: d.token), URLQueryItem(name: "device", value: deviceId),
                        URLQueryItem(name: "name", value: String(deviceName.prefix(40)))]
        guard let url = c.url else { return false }
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
        let first: URLSessionWebSocketTask.Message? = await withTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
            group.addTask { try? await task.receive() }
            group.addTask { try? await Task.sleep(nanoseconds: 3_000_000_000); return nil }
            let r = await group.next() ?? nil
            if r == nil { task.cancel(with: .goingAway, reason: nil) }
            group.cancelAll()
            return r
        }
        guard let msg = first else { return false }
        socket = task
        connected = d
        NovaLinkFlags.linked = true
        broadcastLinkedFlag()
        if case .string(let s) = msg { handleText(s) }
        send(["t": "hello", "name": String(deviceName.prefix(40)), "premium": NovaAccount.shared.me.isPremium])
        lastTabsKey = ""
        reportTabs()
        receiveLoop(task)
        Haptics.success()
        flash("Conectado con \(d.name)")
        return true
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                do {
                    let msg = try await task.receive()
                    guard let self = self, self.socket === task else { return }
                    switch msg {
                    case .string(let s): self.handleText(s)
                    case .data(let d): self.handleBinary(d)
                    @unknown default: break
                    }
                } catch {
                    self?.dropped(task)
                    return
                }
            }
        }
    }

    func disconnect() {
        if let t = socket { t.cancel(with: .goingAway, reason: nil); dropped(t) }
    }

    private func dropped(_ task: URLSessionWebSocketTask) {
        guard socket === task else { return }
        socket = nil
        let was = connected?.name
        connected = nil
        pcTabs = []
        NovaLinkFlags.linked = false
        broadcastLinkedFlag()
        for (_, c) in pending { c.resume(returning: JSONValue(["ok": false, "error": "Se perdió la conexión con el PC."] as [String: Any])) }
        pending.removeAll()
        for (_, c) in acks { c.resume(returning: false) }
        acks.removeAll()
        for (_, f) in incoming { try? f.handle.close(); try? FileManager.default.removeItem(at: f.url) }
        incoming.removeAll()
        transfers.removeAll()
        for h in remoteTabs { h.shutdown(notify: false) }
        remoteTabs.removeAll()
        retryAt = Date().addingTimeInterval(3)
        if let was = was { flash("Desconectado de \(was)") }
    }

    private func broadcastLinkedFlag() {
        let js = "window.__novaLinked = \(NovaLinkFlags.linked ? "true" : "false");"
        for t in model?.tabs ?? [] { t.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: Envío

    func send(_ obj: [String: Any]) {
        guard let task = socket, let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return }
        task.send(.string(s)) { _ in }
    }

    private func sendBinary(_ data: Data) async -> Bool {
        guard let task = socket else { return false }
        do { try await task.send(.data(data)); return true } catch { return false }
    }

    func ask(_ msg: [String: Any], req: String = UUID().uuidString.lowercased(), timeout: Double = 20) async -> JSONValue {
        guard socket != nil else { return JSONValue(["ok": false, "error": "No hay ningún PC conectado. Abre Nova en el PC (misma wifi)."] as [String: Any]) }
        var m = msg
        m["req"] = req
        return await withCheckedContinuation { (c: CheckedContinuation<JSONValue, Never>) in
            pending[req] = c
            send(m)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                Task { @MainActor in NovaLink.shared.resolve(req, JSONValue(["ok": false, "error": "El PC no responde."] as [String: Any])) }
            }
        }
    }

    private func resolve(_ req: String, _ v: JSONValue) {
        if let c = pending.removeValue(forKey: req) { c.resume(returning: v) }
    }

    private func resolveAck(_ id: String, _ ok: Bool) {
        if let c = acks.removeValue(forKey: id) { c.resume(returning: ok) }
    }

    // MARK: Pestañas (Puente móvil)

    private func reportTabs() {
        guard socket != nil, let model = model else { return }
        let list: [[String: Any]] = model.tabs.filter { !$0.isPrivate }.compactMap { t in
            guard let u = t.currentURL, let s = u.scheme?.lowercased(), s == "http" || s == "https" else { return nil }
            return ["id": t.id.uuidString, "title": t.title, "url": u.absoluteString]
        }
        let key = list.map { "\($0["url"] ?? "")|\($0["title"] ?? "")" }.joined(separator: "\n")
        guard key != lastTabsKey else { return }
        lastTabsKey = key
        send(["t": "tabs", "tabs": list])
    }

    func sendTabToPC(_ url: URL?) {
        guard let u = url, let s = u.scheme?.lowercased(), s == "http" || s == "https" else { flash("Esta pestaña no se puede enviar."); return }
        guard socket != nil else { flash("Abre Nova en el PC (misma wifi)."); return }
        send(["t": "open", "url": u.absoluteString])
        Haptics.success()
        flash("Enviada a \(connected?.name ?? "tu PC")")
    }

    func openHere(_ url: String) {
        guard let model = model else { return }
        model.createTab()
        model.load(url)
        showDevices = false
    }

    // MARK: Mensajes del PC

    private func handleText(_ s: String) {
        guard let data = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        let m = JSONValue(obj)
        let t = m["t"].str
        switch t {
        case "hello":
            pcPremium = m["premium"].bool == true
        case "ping":
            send(["t": "pong"])
        case "pong":
            break
        case "tabs":
            pcTabs = m["tabs"].array.map { LinkTab(id: $0["id"].str, title: $0["title"].str, url: $0["url"].str) }
        case "open":
            let u = m["url"].str
            if u.hasPrefix("http://") || u.hasPrefix("https://") { openHere(u); flash("Pestaña recibida del PC") }
        case "pfs:list":
            let rel = m["path"].str
            let items = LocalFiles.list(rel).map { ["name": $0.name, "path": $0.path, "dir": $0.dir, "size": $0.size] as [String: Any] }
            send(["t": "pfs:list:r", "req": m["req"].str, "ok": LocalFiles.resolve(rel) != nil, "path": rel, "items": items,
                  "used": LocalFiles.usedBytes(), "free": LocalFiles.freeBytes()])
        case "pfs:get":
            let rel = m["path"].str, req = m["req"].str, move = m["move"].bool == true
            let purpose = m["purpose"].str == "inject" ? "inject" : "save"
            Task { await self.servePhoneFile(rel, move: move, purpose: purpose, req: req) }
        case "pfs:delete":
            let ok = deleteLocal(m["path"].str)
            send(["t": "pfs:delete:r", "req": m["req"].str, "ok": ok, "error": ok ? "" : "No se pudo borrar."])
        case "file:begin":
            beginIncoming(m)
        case "file:end":
            endIncoming(m["id"].str)
        case "file:ack":
            resolveAck(m["id"].str, true)
        case "file:refused":
            let id = m["id"].str
            resolveAck(id, false)
            if let f = incoming.removeValue(forKey: id) { try? f.handle.close(); try? FileManager.default.removeItem(at: f.url) }
            transfers[id] = nil
            flash(m["error"].str.isEmpty ? "El PC rechazó el archivo." : m["error"].str)
        case "rtab:open":
            openRemoteTab(rid: m["rid"].str, url: m["url"].str, mode: m["mode"].str, width: m["ow"].int ?? 1920)
        case "rtab:input":
            remoteTabs.first(where: { $0.id == m["rid"].str })?.input(m)
        case "rtab:nav":
            remoteTabs.first(where: { $0.id == m["rid"].str })?.navigate(m["action"].str, url: m["url"].str)
        case "rtab:close":
            if let h = remoteTabs.first(where: { $0.id == m["rid"].str }) { h.shutdown(notify: false); remoteTabs.removeAll { $0 === h } }
        case "rtab:mode":
            remoteTabs.first(where: { $0.id == m["rid"].str })?.setMode(m["mode"].str, width: m["w"].int ?? 1920)
        case "rtab:key":
            remoteTabs.first(where: { $0.id == m["rid"].str })?.requestKeyFrame()
        case "rtab:ack":
            remoteTabs.first(where: { $0.id == m["rid"].str })?.frameAcked()
        default:
            let req = m["req"].str
            if !req.isEmpty, t.hasSuffix(":r") { resolve(req, m) }
        }
    }

    private func handleBinary(_ d: Data) {
        guard d.count >= 37 else { return }
        let s = d.startIndex
        let kind = d[s]
        let key = String(decoding: d[(s + 1)..<(s + 37)], as: UTF8.self)
        guard kind == 2, let f = incoming[key] else { return }
        let payload = d[(s + 37)...]
        f.handle.write(Data(payload))
        f.got += Int64(payload.count)
        if f.got > limitBytes + 1024 {
            try? f.handle.close(); try? FileManager.default.removeItem(at: f.url)
            incoming[key] = nil; transfers[key] = nil
            flash("El archivo supera \(limitText).")
            return
        }
        transfers[key]?.got = f.got
    }

    private func beginIncoming(_ m: JSONValue) {
        let id = m["id"].str
        guard id.count == 36 else { return }
        let name = m["name"].str.isEmpty ? "archivo" : m["name"].str
        let req = m["req"].str
        let size = Int64(m["size"].double ?? 0)
        let dir = req.isEmpty ? LocalFiles.received : FileManager.default.temporaryDirectory
        let url = req.isEmpty ? LocalFiles.unique(in: dir, name: name) : dir.appendingPathComponent("nova-\(id)-\(name)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        incoming[id] = IncomingFile(id: id, name: name, size: size, req: req, url: url, handle: h)
        transfers[id] = LinkTransfer(id: id, name: name, got: 0, size: size, incoming: true)
    }

    private func endIncoming(_ id: String) {
        guard let f = incoming.removeValue(forKey: id) else { return }
        try? f.handle.close()
        transfers[id] = nil
        send(["t": "file:ack", "id": id])
        if f.req.isEmpty {
            Haptics.success()
            flash("Recibido «\(f.url.lastPathComponent)» · Archivos de Nova › Recibidos")
        } else {
            completedByReq[f.req] = f.url
        }
    }

    private func deleteLocal(_ rel: String) -> Bool {
        guard !rel.isEmpty, let u = LocalFiles.resolve(rel), u.standardizedFileURL.path != LocalFiles.root.standardizedFileURL.path else { return false }
        return (try? FileManager.default.removeItem(at: u)) != nil
    }

    // MARK: Archivos que salen del iPhone

    @discardableResult
    func streamFile(_ url: URL, extra: [String: Any] = [:]) async -> (ok: Bool, error: String) {
        guard socket != nil else { return (false, "No hay ningún PC conectado.") }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else { return (false, "No se pudo leer el archivo.") }
        if size > limitBytes { return (false, "Máximo \(limitText) por archivo\(isPremium ? "" : " (más con Nova Premium)").") }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return (false, "No se pudo abrir el archivo.") }
        defer { try? fh.close() }
        let id = UUID().uuidString.lowercased()
        var begin: [String: Any] = ["t": "file:begin", "id": id, "name": url.lastPathComponent, "size": size, "mime": LocalFiles.mime(url)]
        for (k, v) in extra { begin[k] = v }
        send(begin)
        var header = Data([2])
        header.append(Data(id.utf8))
        transfers[id] = LinkTransfer(id: id, name: url.lastPathComponent, got: 0, size: size, incoming: false)
        var sent: Int64 = 0
        while true {
            let chunk = fh.readData(ofLength: 256 * 1024)
            if chunk.isEmpty { break }
            var frame = header
            frame.append(chunk)
            guard await sendBinary(frame) else { transfers[id] = nil; return (false, "Se perdió la conexión.") }
            sent += Int64(chunk.count)
            transfers[id]?.got = sent
        }
        let ok: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            acks[id] = c
            send(["t": "file:end", "id": id])
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
                Task { @MainActor in NovaLink.shared.resolveAck(id, false) }
            }
        }
        transfers[id] = nil
        return ok ? (true, "") : (false, "El PC no recibió el archivo.")
    }

    /// El PC pidió un archivo de Nova en el iPhone (descargar, mover o dárselo a una web).
    private func servePhoneFile(_ rel: String, move: Bool, purpose: String, req: String) async {
        guard let u = LocalFiles.resolve(rel), FileManager.default.fileExists(atPath: u.path) else {
            send(["t": "pfs:get:r", "req": req, "ok": false, "error": "Ese archivo ya no existe en el iPhone."]); return
        }
        let r = await streamFile(u, extra: ["purpose": purpose, "req": req])
        if r.ok {
            if move { try? FileManager.default.removeItem(at: u) }
        } else {
            send(["t": "pfs:get:r", "req": req, "ok": false, "error": r.error])
        }
    }

    /// Enviar archivos de Nova al PC (copiar o mover). Se guardan en Descargas\Nova.
    func sendToPC(_ rel: String, move: Bool) async {
        guard let u = LocalFiles.resolve(rel) else { return }
        let r = await streamFile(u, extra: ["purpose": "save"])
        if r.ok {
            if move { try? FileManager.default.removeItem(at: u) }
            Haptics.success()
            flash(move ? "Movido al PC (Descargas › Nova)" : "Enviado al PC (Descargas › Nova)")
        } else { flash(r.error) }
    }

    // MARK: Archivos del PC (carpetas compartidas)

    func listPC(_ path: String) async -> (items: [LinkFileItem], path: String, error: String?) {
        let r = await ask(["t": "fs:list", "path": path])
        guard r["ok"].bool == true else { return ([], path, r["error"].str.isEmpty ? "No se pudo leer el PC." : r["error"].str) }
        let items = r["items"].array.map { LinkFileItem(name: $0["name"].str, path: $0["path"].str, dir: $0["dir"].bool == true, size: Int64($0["size"].double ?? 0)) }
        return (items, r["path"].str, nil)
    }

    /// Trae un archivo del PC a un temporal. move = el PC lo manda a su papelera después.
    func fetchFromPC(_ path: String, move: Bool) async -> (url: URL?, error: String) {
        let req = UUID().uuidString.lowercased()
        let r = await ask(["t": "fs:get", "path": path, "move": move], req: req, timeout: 900)
        let url = completedByReq.removeValue(forKey: req)
        if r["ok"].bool == true, let url = url { return (url, "") }
        if let url = url { try? FileManager.default.removeItem(at: url) }
        return (nil, r["error"].str.isEmpty ? "No se pudo traer el archivo." : r["error"].str)
    }

    func downloadFromPC(_ item: LinkFileItem, move: Bool) async {
        let r = await fetchFromPC(item.path, move: move)
        guard let tmp = r.url else { flash(r.error); return }
        let dest = LocalFiles.unique(in: LocalFiles.received, name: item.name)
        do { try FileManager.default.moveItem(at: tmp, to: dest); Haptics.success(); flash(move ? "Movido al iPhone › Recibidos" : "Guardado en Archivos de Nova › Recibidos") }
        catch { flash("No se pudo guardar el archivo.") }
    }

    /// Una web del iPhone pidió un archivo y el usuario eligió uno del PC.
    func injectFromPC(_ item: LinkFileItem, into webView: WKWebView?) async {
        guard let webView = webView else { return }
        flash("Recibiendo «\(item.name)»…")
        let r = await fetchFromPC(item.path, move: false)
        guard let tmp = r.url, let data = try? Data(contentsOf: tmp) else { flash(r.error); return }
        try? FileManager.default.removeItem(at: tmp)
        let b64 = data.base64EncodedString()
        let js = "(window.__novaDeliver ? window.__novaDeliver(\(jsString(item.name)), \(jsString(LocalFiles.mime(URL(fileURLWithPath: item.name)))), \(jsString(b64))) : false)"
        webView.evaluateJavaScript(js) { res, err in
            let ok = err == nil && (res as? Bool) == true
            Task { @MainActor in NovaLink.shared.flash(ok ? "Archivo listo en la web" : "La web no aceptó el archivo.") }
        }
    }

    // MARK: Pestañas del PC que se ejecutan aquí

    private func openRemoteTab(rid: String, url: String, mode: String, width: Int) {
        guard rid.count == 36, url.hasPrefix("http") else { return }
        let h = RemoteTabHost(rid: rid, url: url, mode: mode.isEmpty ? "jpeg" : mode, width: width)
        remoteTabs.append(h)
        showDevices = false
        pcPick = nil
    }

    func stopRemoteTab(_ h: RemoteTabHost) {
        h.shutdown(notify: true)
        remoteTabs.removeAll { $0 === h }
    }

    /// v89 · Vídeo H.264: [4][rid][ancho 2][alto 2][avcC] y [3][rid][clave 1][datos AVCC].
    func sendVideoConfig(rid: String, width: Int, height: Int, avcc: Data) {
        guard let task = socket else { return }
        var d = Data([4])
        d.append(Data(rid.utf8))
        d.append(contentsOf: [UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF), UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF)])
        d.append(avcc)
        task.send(.data(d)) { _ in }
    }

    func sendVideoFrame(rid: String, key: Bool, data: Data, done: @escaping @Sendable () -> Void) {
        guard let task = socket else { done(); return }
        var d = Data([3])
        d.append(Data(rid.utf8))
        d.append(key ? 1 : 0)
        d.append(data)
        task.send(.data(d)) { _ in done() }
    }

    // MARK: Compartiendo (v90)

    private var keepAlive: AVAudioPlayer?
    private var savedBrightness: CGFloat?

    /// Mientras el PC usa el iPhone: la pantalla no se apaga sola y un audio silencioso mantiene viva la
    /// conexión si sales de Nova o bloqueas el iPhone (al volver, la imagen sigue al instante).
    private func sharingChanged(was: Bool) {
        let now = !remoteTabs.isEmpty
        guard now != was else { return }
        UIApplication.shared.isIdleTimerDisabled = now
        if now { startKeepAlive() } else { stopKeepAlive(); setDimmed(false) }
    }

    private func startKeepAlive() {
        guard keepAlive == nil else { return }
        let rate = 8000, seconds = 2
        let samples = rate * seconds
        var wav = Data("RIFF".utf8)
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        wav.append(contentsOf: le32(36 + samples * 2))
        wav.append(Data("WAVEfmt ".utf8))
        wav.append(contentsOf: le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate * 2) + le16(2) + le16(16))
        wav.append(Data("data".utf8))
        wav.append(contentsOf: le32(samples * 2))
        wav.append(Data(count: samples * 2))
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: wav)
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            keepAlive = p
        } catch {}
    }

    private func stopKeepAlive() {
        keepAlive?.stop()
        keepAlive = nil
    }

    /// Pantalla negra mientras se comparte: casi no gasta batería (OLED) y Nova sigue trabajando.
    @Published private(set) var dimmed = false
    func setDimmed(_ on: Bool) {
        guard on != dimmed else { return }
        dimmed = on
        if on { savedBrightness = UIScreen.main.brightness; UIScreen.main.brightness = 0.02 }
        else if let b = savedBrightness { UIScreen.main.brightness = b; savedBrightness = nil }
    }

    func stopSharing() {
        for h in remoteTabs { h.shutdown(notify: true) }
        remoteTabs.removeAll()
        flash("Has dejado de compartir")
    }

    // MARK: Enviar archivos de fuera de Nova (Archivos / Fotos) directamente al PC (v90)

    func sendExternal(_ urls: [URL]) async {
        guard socket != nil else { flash("Abre Nova en el PC (misma cuenta y wifi) y espera a «Conectado»."); connectIfNeeded(force: true); return }
        var ok = 0, lastError = ""
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            let r = await streamFile(u, extra: ["purpose": "save"])
            if scoped { u.stopAccessingSecurityScopedResource() }
            if r.ok { ok += 1 } else { lastError = r.error }
        }
        if ok > 0 { Haptics.success() }
        flash(ok == urls.count ? (ok == 1 ? "Enviado al PC (Descargas › Nova)" : "\(ok) archivos enviados al PC") : (lastError.isEmpty ? "Algún archivo no se envió." : lastError))
    }

    func sendPhotos(_ items: [PhotosPickerItem]) async {
        guard socket != nil else { flash("Abre Nova en el PC (misma cuenta y wifi) y espera a «Conectado»."); connectIfNeeded(force: true); return }
        flash("Preparando \(items.count == 1 ? "la foto" : "\(items.count) fotos")…")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nova-envio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var urls: [URL] = []
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let u = LocalFiles.unique(in: dir, name: "Foto \(fmt.string(from: Date()))\(i > 0 ? " \(i + 1)" : "").\(ext)")
            if (try? data.write(to: u)) != nil { urls.append(u) }
        }
        guard !urls.isEmpty else { flash("No se pudieron leer las fotos."); return }
        await sendExternal(urls)
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }

    func sendFrame(rid: String, jpeg: Data) async {
        var d = Data([1])
        d.append(Data(rid.utf8))
        d.append(jpeg)
        _ = await sendBinary(d)
    }
}

func jsString(_ s: String) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: [s]), let a = String(data: d, encoding: .utf8) else { return "\"\"" }
    return String(a.dropFirst().dropLast())
}
