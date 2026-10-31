import SwiftUI

// ════════════════════════════════════════════════════════════════════════════════════
//  Una conversación abierta (amigo o grupo): mensajes, enviar, editar, eliminar, leídos.
//  Los mismos mensajes que en Nova Windows y en la web; se actualiza cada pocos segundos.
// ════════════════════════════════════════════════════════════════════════════════════

struct ChatMessage: Identifiable, Equatable {
    var id: Int                // 0 mientras se envía
    var clientId: String
    var sender: String
    var body: String
    var at: Date
    var edited: Bool
    var deleted: Bool
    var system: String
    var pending = false
    var failed = false

    var key: String { clientId.isEmpty ? "i\(id)" : clientId }

    static func from(_ j: JSONValue) -> ChatMessage {
        ChatMessage(id: j["id"].int ?? 0, clientId: j["client_id"].str, sender: j["sender_id"].str, body: j["body"].str,
                    at: j["created_at"].date ?? Date(), edited: !j["edited_at"].isNull, deleted: j["deleted"].bool == true,
                    system: j["system"].str)
    }
}

@MainActor
final class ChatSession: ObservableObject {
    let target: ChatTarget
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var conversationId = ""
    @Published private(set) var canSend = false
    @Published private(set) var loading = true
    @Published private(set) var hasMore = false
    @Published private(set) var peerRead = 0
    @Published var error: String?
    @Published var editing: ChatMessage?

    private let client = NovaClient.shared
    private var poll: Timer?
    private var typingAt: Date = .distantPast
    private var lastRead = 0

    init(target: ChatTarget) { self.target = target }

    var myId: String { NovaAccount.shared.me.userId }

    // MARK: Abrir y actualizar

    func open() async {
        loading = true
        error = nil
        switch target {
        case .friend(let fid):
            do {
                let j = try await client.rpc("nova_open_direct", ["p_friend": fid])
                guard j["result"].str == "ok" else {
                    error = j["result"].str == "not_friends" ? "Solo puedes escribir a tus amigos." : "No se pudo abrir la conversación."
                    loading = false
                    return
                }
                conversationId = j["conversation_id"].str
                canSend = j["can_send"].bool == true
                peerRead = j["peer_last_read"].int ?? 0
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "No se pudo abrir la conversación."
                loading = false
                return
            }
        case .group(let gid):
            conversationId = gid
            canSend = true
        }
        await loadLatest(replace: true)
        loading = false
        startPolling()
    }

    func close() {
        poll?.invalidate(); poll = nil
        stopTyping()
    }

    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.loadLatest(replace: false) }
        }
    }

    /// Últimos 50 mensajes; se mezclan con los que ya hay (sin duplicar).
    func loadLatest(replace: Bool) async {
        guard !conversationId.isEmpty,
              let rows = await client.tryRPC("nova_list_messages", ["p_conversation": conversationId, "p_before": NSNull(), "p_limit": 50]) else { return }
        let got = rows.array.map(ChatMessage.from)
        if replace { hasMore = got.count >= 50 }
        merge(got)
        if case .friend = target, let j = await client.tryRPC("nova_open_direct", ["p_friend": friendId]) {
            peerRead = j["peer_last_read"].int ?? peerRead
        }
        markRead()
    }

    func loadOlder() async {
        guard let first = messages.first(where: { $0.id > 0 })?.id,
              let rows = await client.tryRPC("nova_list_messages", ["p_conversation": conversationId, "p_before": first, "p_limit": 50]) else { return }
        let got = rows.array.map(ChatMessage.from)
        hasMore = got.count >= 50
        merge(got)
    }

    private var friendId: String { if case .friend(let f) = target { return f }; return "" }

    private func merge(_ got: [ChatMessage]) {
        var byId: [Int: ChatMessage] = [:]
        for m in messages where m.id > 0 { byId[m.id] = m }
        var pending = messages.filter { $0.id == 0 }
        for m in got {
            byId[m.id] = m
            pending.removeAll { $0.clientId == m.clientId && !m.clientId.isEmpty }
        }
        let merged = (Array(byId.values) + pending).sorted { a, b in
            if a.id > 0 && b.id > 0 { return a.id < b.id }
            return a.at < b.at
        }
        if merged != messages { messages = merged }
    }

    private func markRead() {
        guard let last = messages.last(where: { $0.id > 0 }), last.id > lastRead else { return }
        lastRead = last.id
        let conv = conversationId
        Task { _ = await client.tryRPC("nova_mark_read", ["p_conversation": conv, "p_last_id": last.id]) }
        let acc = NovaAccount.shared
        switch target {
        case .friend(let f): acc.conversations[f]?.unread = 0
        case .group(let g): if let i = acc.groups.firstIndex(where: { $0.id == g }) { acc.groups[i].unread = 0 }
        }
    }

    // MARK: Enviar, editar, eliminar

    func send(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, canSend else { return }
        if let e = editing {
            editing = nil
            Task { await edit(e, body: body) }
            return
        }
        stopTyping()
        let m = ChatMessage(id: 0, clientId: UUID().uuidString.lowercased(), sender: myId, body: String(body.prefix(2000)),
                            at: Date(), edited: false, deleted: false, system: "", pending: true)
        messages.append(m)
        Task { await deliver(m) }
    }

    func retry(_ m: ChatMessage) {
        guard let i = messages.firstIndex(where: { $0.clientId == m.clientId }) else { return }
        messages[i].failed = false
        messages[i].pending = true
        Task { await deliver(messages[i]) }
    }

    private func deliver(_ m: ChatMessage) async {
        do {
            let j = try await client.rpc("nova_send_message_v2", ["p_conversation": conversationId, "p_body": m.body,
                                                                  "p_client_id": m.clientId, "p_reply_to": NSNull()])
            if j["result"].str == "sent" {
                let real = ChatMessage.from(j["message"])
                if let i = messages.firstIndex(where: { $0.clientId == m.clientId }) {
                    if messages.contains(where: { $0.id == real.id && $0.clientId != m.clientId }) { messages.remove(at: i) }
                    else { messages[i] = real }
                }
                Haptics.tap()
            } else {
                let r: [String: String] = ["not_friends": "Ya no sois amigos: no puedes enviar mensajes.", "not_member": "Ya no estás en este grupo.",
                                           "rate_limited": "Vas muy rápido. Espera unos segundos.", "too_long": "El mensaje es demasiado largo."]
                fail(m, r[j["result"].str] ?? "No se pudo enviar el mensaje.")
            }
        } catch {
            fail(m, (error as? LocalizedError)?.errorDescription ?? "No se pudo enviar el mensaje.")
        }
    }

    private func fail(_ m: ChatMessage, _ text: String) {
        if let i = messages.firstIndex(where: { $0.clientId == m.clientId }) {
            messages[i].pending = false
            messages[i].failed = true
        }
        error = text
    }

    private func edit(_ m: ChatMessage, body: String) async {
        do {
            let j = try await client.rpc("nova_edit_message", ["p_message": m.id, "p_body": body])
            if j["result"].str == "ok" || j["result"].isNull {
                if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i].body = body; messages[i].edited = true }
            } else { error = "No se pudo editar el mensaje." }
        } catch { error = "No se pudo editar el mensaje." }
    }

    func delete(_ m: ChatMessage) {
        guard m.id > 0 else { messages.removeAll { $0.clientId == m.clientId }; return }
        if let i = messages.firstIndex(where: { $0.id == m.id }) { messages[i].deleted = true; messages[i].body = "" }
        Task {
            do { _ = try await client.rpc("nova_delete_message", ["p_message": m.id]) }
            catch { self.error = "No se pudo eliminar el mensaje." }
        }
    }

    // MARK: «Escribiendo…» (lo ven tus amigos en Nova Windows y en la web)

    func userTyped() {
        guard canSend, !conversationId.isEmpty, Date().timeIntervalSince(typingAt) > 3 else { return }
        typingAt = Date()
        let conv = conversationId
        Task { _ = await client.tryRPC("nova_set_typing", ["p_conversation": conv, "p_is_typing": true, "p_revision": Int(Date().timeIntervalSince1970 * 1000)]) }
    }

    func stopTyping() {
        guard typingAt != .distantPast, !conversationId.isEmpty else { return }
        typingAt = .distantPast
        let conv = conversationId
        Task { _ = await client.tryRPC("nova_set_typing", ["p_conversation": conv, "p_is_typing": false, "p_revision": Int(Date().timeIntervalSince1970 * 1000)]) }
    }
}
