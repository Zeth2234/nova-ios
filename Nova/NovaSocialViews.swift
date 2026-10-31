import SwiftUI
import PhotosUI
import UIKit

// ════════════════════════════════════════════════════════════════════════════════════
//  Interfaz de la cuenta Nova en iOS: inicio de sesión, chats, conversación, amigos y perfil.
// ════════════════════════════════════════════════════════════════════════════════════

// MARK: - Piezas comunes

struct NovaAvatar: View {
    let name: String
    let color: String
    let url: URL?
    var size: CGFloat = 40
    var status: NovaStatus?
    var ring = false

    private var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Color(novaHex: color))
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                if let url = url {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                if ring {
                    Circle().strokeBorder(AngularGradient(colors: [NovaTheme.accent, Color(hex: 0xFF6FCF), Color(hex: 0xFFD36B), NovaTheme.accent], center: .center), lineWidth: max(2, size * 0.05))
                        .padding(-max(3, size * 0.07))
                }
            }
            if let s = status {
                Circle()
                    .fill(s.color)
                    .frame(width: max(9, size * 0.27), height: max(9, size * 0.27))
                    .overlay(Circle().stroke(NovaTheme.bg, lineWidth: max(2, size * 0.06)))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

struct NovaPrimaryButton: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            ZStack {
                if busy { ProgressView().tint(.white) } else { Text(title).font(.system(size: 16, weight: .semibold)) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NovaTheme.accentGradient))
            .opacity(enabled ? 1 : 0.5)
            .shadow(color: NovaTheme.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy || !enabled)
    }
}

struct NovaTextField: View {
    let title: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.dim)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .keyboardType(keyboard)
            .textContentType(content)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 16))
            .foregroundColor(NovaTheme.text)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.ink(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        }
    }
}

struct StatusText: View {
    let text: String?
    var ok = false
    var body: some View {
        if let t = text, !t.isEmpty {
            Text(t)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ok ? NovaTheme.good : NovaTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        }
    }
}

private func shortTime(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let cal = Calendar.current
    let f = DateFormatter()
    f.locale = Locale(identifier: "es_ES")
    if cal.isDateInToday(d) { f.dateFormat = "HH:mm" }
    else if cal.isDateInYesterday(d) { return "Ayer" }
    else if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 { f.dateFormat = "EEEE" }
    else { f.dateFormat = "d/M/yy" }
    return f.string(from: d)
}

// MARK: - Raíz (hoja «Amigos y chat»)

struct AccountHubView: View {
    @ObservedObject private var account = NovaAccount.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [NovaTheme.accent.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
            switch account.phase {
            case .loading:
                ProgressView().tint(NovaTheme.accent)
            case .signedOut:
                AuthView(close: { dismiss() })
            case .needsTotp:
                TotpView()
            case .signedIn:
                SocialHome(close: { dismiss() })
            }
        }
        .overlay(alignment: .bottom) {
            if let t = account.toast {
                Text(t)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NovaTheme.text)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .novaGlass(radius: 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: account.phase)
        .novaAppearance()
    }
}

// MARK: - Iniciar sesión / crear cuenta

struct AuthView: View {
    let close: () -> Void
    @ObservedObject private var account = NovaAccount.shared

    enum Mode { case login, register, confirm, recover }
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var code = ""
    @State private var totp = ""
    @State private var recoverSent = false
    @State private var recoverNeedsTotp = false
    @State private var busy = false
    @State private var message: String?
    @State private var messageOK = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    NovaMark(size: 40)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(NovaTheme.dim)
                            .frame(width: 34, height: 34).background(Circle().fill(NovaTheme.surfaceHi))
                    }
                    .accessibilityLabel("Cerrar")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 28, weight: .bold)).foregroundColor(NovaTheme.text)
                    Text(subtitle).font(.system(size: 14)).foregroundColor(NovaTheme.dim)
                }
                if mode == .login || mode == .register { tabs }
                fields
                StatusText(text: message, ok: messageOK)
                NovaPrimaryButton(title: buttonTitle, busy: busy, action: submit)
                footer
            }
            .padding(22)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
    }

    private var title: String {
        switch mode {
        case .login: return "Tu cuenta Nova"
        case .register: return "Crea tu cuenta Nova"
        case .confirm: return "Confirma tu correo"
        case .recover: return "Restablece tu contraseña"
        }
    }
    private var subtitle: String {
        switch mode {
        case .login, .register: return "La misma cuenta que en Nova para Windows y en la web: tus amigos, tu chat y tu perfil."
        case .confirm: return "Te hemos enviado un código de 8 números a \(email)."
        case .recover: return recoverSent ? "Escribe el código del correo y tu contraseña nueva." : "Escribe el correo de tu cuenta y te enviaremos un código."
        }
    }
    private var buttonTitle: String {
        switch mode {
        case .login: return "Iniciar sesión"
        case .register: return "Crear cuenta"
        case .confirm: return "Confirmar y entrar"
        case .recover: return recoverSent ? "Cambiar contraseña" : "Enviar código"
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab("Iniciar sesión", .login)
            tab("Crear cuenta", .register)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NovaTheme.ink(0.05)))
    }

    private func tab(_ t: String, _ m: Mode) -> some View {
        Button {
            Haptics.select()
            mode = m
            message = nil
        } label: {
            Text(t).font(.system(size: 14, weight: .semibold))
                .foregroundColor(mode == m ? NovaTheme.text : NovaTheme.dim)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(mode == m ? NovaTheme.surfaceHi : Color.clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var fields: some View {
        switch mode {
        case .login:
            NovaTextField(title: "Correo", text: $email, keyboard: .emailAddress, content: .username)
            NovaTextField(title: "Contraseña", text: $password, secure: true, content: .password)
        case .register:
            NovaTextField(title: "Nombre", text: $name, content: .nickname)
            NovaTextField(title: "Correo", text: $email, keyboard: .emailAddress, content: .username)
            NovaTextField(title: "Contraseña (mínimo 8 caracteres)", text: $password, secure: true, content: .newPassword)
            NovaTextField(title: "Repite la contraseña", text: $password2, secure: true, content: .newPassword)
        case .confirm:
            NovaTextField(title: "Código del correo", text: $code, keyboard: .numberPad, content: .oneTimeCode)
        case .recover:
            NovaTextField(title: "Correo", text: $email, keyboard: .emailAddress, content: .username)
            if recoverSent {
                NovaTextField(title: "Código del correo", text: $code, keyboard: .numberPad, content: .oneTimeCode)
                if recoverNeedsTotp {
                    NovaTextField(title: "Código de Google Authenticator", text: $totp, keyboard: .numberPad, content: .oneTimeCode)
                }
                NovaTextField(title: "Contraseña nueva (mínimo 8)", text: $password, secure: true, content: .newPassword)
                NovaTextField(title: "Repite la contraseña", text: $password2, secure: true, content: .newPassword)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch mode {
        case .login:
            Button("¿Has olvidado la contraseña?") { mode = .recover; message = nil; recoverSent = false }
                .font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.accent)
        case .register:
            Text("Es la misma cuenta que usarás en el navegador Nova.").font(.system(size: 12)).foregroundColor(NovaTheme.faint)
        case .confirm:
            HStack {
                Button("Reenviar código") { Task { await resend() } }
                Spacer()
                Button("Volver") { mode = .register; message = nil }
            }
            .font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.accent)
        case .recover:
            Button("Volver a iniciar sesión") { mode = .login; message = nil }
                .font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.accent)
        }
    }

    private func say(_ t: String, ok: Bool = false) { message = t; messageOK = ok }
    private func err(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "Algo ha fallado. Inténtalo de nuevo." }
    private var emailOK: Bool { email.range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil }

    private func submit() {
        message = nil
        switch mode {
        case .login:
            guard emailOK, !password.isEmpty else { return say("Escribe tu correo y tu contraseña.") }
            run { try await account.signIn(email: email, password: password) }
        case .register:
            let n = name.trimmingCharacters(in: .whitespaces)
            guard n.count >= 2 else { return say("El nombre debe tener al menos 2 caracteres.") }
            guard emailOK else { return say("Escribe un correo válido.") }
            guard password.count >= 8 else { return say("La contraseña debe tener al menos 8 caracteres.") }
            guard password == password2 else { return say("Las contraseñas no coinciden.") }
            run {
                let inside = try await account.signUp(name: String(n.prefix(24)), email: email, password: password)
                if !inside { mode = .confirm; code = "" }
            }
        case .confirm:
            guard code.count >= 6 else { return say("Escribe el código del correo.") }
            run { try await account.confirmSignup(email: email, code: code) }
        case .recover:
            guard emailOK else { return say("Escribe el correo de tu cuenta.") }
            if !recoverSent {
                run {
                    try await account.sendRecovery(email: email)
                    recoverSent = true
                    say("Te hemos enviado un código. Revisa también el correo no deseado.", ok: true)
                }
            } else {
                guard code.count >= 6 else { return say("Escribe el código del correo.") }
                guard password.count >= 8 else { return say("La contraseña debe tener al menos 8 caracteres.") }
                guard password == password2 else { return say("Las contraseñas no coinciden.") }
                run {
                    do {
                        try await account.resetPassword(email: email, code: code, totp: recoverNeedsTotp ? totp : nil, newPassword: password)
                    } catch let e as NovaError {
                        if case .invalid(let m) = e, m.contains("Google Authenticator") { recoverNeedsTotp = true }
                        throw e
                    }
                }
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do { try await work() } catch { say(err(error)) }
            busy = false
        }
    }

    private func resend() async {
        do { try await account.resendSignup(email: email); say("Código reenviado.", ok: true) } catch { say(err(error)) }
    }
}

struct TotpView: View {
    @ObservedObject private var account = NovaAccount.shared
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield.fill").font(.system(size: 40)).foregroundStyle(NovaTheme.accentGradient)
            Text("Verificación en dos pasos").font(.system(size: 26, weight: .bold)).foregroundColor(NovaTheme.text)
            Text("Abre Google Authenticator y escribe el código de 6 números de Nova.").font(.system(size: 14)).foregroundColor(NovaTheme.dim)
            NovaTextField(title: "Código", text: $code, keyboard: .numberPad, content: .oneTimeCode)
            StatusText(text: message)
            NovaPrimaryButton(title: "Verificar", busy: busy, enabled: code.count == 6) {
                busy = true
                Task {
                    do { try await account.verifyTotp(code) } catch { message = (error as? LocalizedError)?.errorDescription ?? "El código no es correcto." }
                    busy = false
                }
            }
            Button("Usar otra cuenta") { Task { await account.cancelTotp() } }
                .font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.accent)
            Spacer()
        }
        .padding(24)
        .onChange(of: code) { v in code = String(v.filter(\.isNumber).prefix(6)) }
    }
}

// MARK: - Inicio con sesión: Chats · Amigos · Perfil

struct SocialHome: View {
    let close: () -> Void
    @ObservedObject private var account = NovaAccount.shared
    enum Tab: String, CaseIterable { case chats = "Chats", friends = "Amigos", profile = "Perfil" }
    @State private var tab: Tab = .chats
    @State private var path: [ChatTarget] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                picker.padding(.horizontal, 18).padding(.bottom, 8)
                Group {
                    switch tab {
                    case .chats: ChatsListView(open: { path.append($0) })
                    case .friends: FriendsView(openChat: { tab = .chats; path.append(.friend($0)) })
                    case .profile: MyProfileView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color.clear)
            .navigationBarHidden(true)
            .navigationDestination(for: ChatTarget.self) { t in ChatView(target: t) }
        }
        .tint(NovaTheme.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            NovaAvatar(name: account.me.name, color: account.me.avatarColor, url: account.me.avatarURL, size: 38, status: account.me.status)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.me.name).font(.system(size: 17, weight: .bold)).foregroundColor(NovaTheme.text).lineLimit(1)
                Text(account.me.status.title).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(NovaTheme.dim)
                    .frame(width: 34, height: 34).background(Circle().fill(NovaTheme.surfaceHi))
            }
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    Haptics.select()
                    withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                } label: {
                    HStack(spacing: 6) {
                        Text(t.rawValue)
                        if t == .chats && account.unreadTotal > 0 { badge(account.unreadTotal) }
                        if t == .friends && !account.requests.isEmpty { badge(account.requests.count) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tab == t ? NovaTheme.text : NovaTheme.dim)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tab == t ? NovaTheme.surfaceHi : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NovaTheme.ink(0.05)))
    }

    private func badge(_ n: Int) -> some View {
        Text(n > 99 ? "99+" : "\(n)")
            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
            .padding(.horizontal, 6).frame(minHeight: 18)
            .background(Capsule().fill(Color(hex: 0xFF3B4E)))
    }
}

// MARK: - Lista de chats

struct ChatsListView: View {
    let open: (ChatTarget) -> Void
    @ObservedObject private var account = NovaAccount.shared
    @State private var query = ""

    private var targets: [ChatTarget] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return account.chatTargets }
        return account.chatTargets.filter { t in
            switch t {
            case .friend(let id): return (account.friend(id)?.name.lowercased().contains(q) ?? false) || (account.friend(id)?.username.lowercased().contains(q) ?? false)
            case .group(let id): return account.group(id)?.name.lowercased().contains(q) ?? false
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(NovaTheme.faint)
                    TextField("Buscar chats", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .font(.system(size: 15))
                .padding(.horizontal, 14).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.ink(0.05)))
                .padding(.bottom, 6)

                if account.friends.isEmpty && account.groups.isEmpty {
                    EmptyState(symbol: "bubble.left.and.bubble.right", title: "Tu chat de Nova, también aquí",
                               text: "Cuando tengas amigos aparecerán aquí. Añade a alguien con su código en «Amigos».")
                }
                ForEach(targets) { t in
                    Button { Haptics.tap(); open(t) } label: { ChatRow(target: t) }
                        .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 30)
        }
        .refreshable { await account.reloadSocial(includeFriends: true) }
    }
}

struct ChatRow: View {
    let target: ChatTarget
    @ObservedObject private var account = NovaAccount.shared

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundColor(NovaTheme.text).lineLimit(1)
                    Spacer()
                    Text(shortTime(lastAt)).font(.system(size: 12)).foregroundColor(unread > 0 ? NovaTheme.accent : NovaTheme.faint)
                }
                HStack {
                    Text(preview).font(.system(size: 13.5)).foregroundColor(NovaTheme.dim).lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(NovaTheme.accentGradient))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(unread > 0 ? NovaTheme.accent.opacity(0.08) : NovaTheme.ink(0.03)))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var avatar: some View {
        switch target {
        case .friend(let id):
            let f = account.friend(id)
            NovaAvatar(name: f?.name ?? "?", color: f?.avatarColor ?? "#7b6cff", url: f?.avatarURL, size: 48, status: f?.status)
        case .group(let id):
            let g = account.group(id)
            GroupAvatar(group: g, size: 48)
        }
    }

    private var title: String {
        switch target {
        case .friend(let id): return account.friend(id)?.name ?? "Amigo"
        case .group(let id): return account.group(id)?.name ?? "Grupo"
        }
    }
    private var lastAt: Date? {
        switch target {
        case .friend(let id): return account.conversations[id]?.lastAt
        case .group(let id): return account.group(id)?.lastAt
        }
    }
    private var unread: Int {
        switch target {
        case .friend(let id): return account.conversations[id]?.unread ?? 0
        case .group(let id): return account.group(id)?.unread ?? 0
        }
    }
    private var preview: String {
        let me = account.me.userId
        switch target {
        case .friend(let id):
            if let c = account.conversations[id], !c.lastBody.isEmpty {
                return (c.lastSender == me ? "Tú: " : "") + c.lastBody.replacingOccurrences(of: "\n", with: " ")
            }
            return account.friend(id)?.statusLine ?? ""
        case .group(let id):
            guard let g = account.group(id) else { return "" }
            if g.lastBody.isEmpty { return "\(g.members.count) miembros" }
            let who = g.lastSender == me ? "Tú" : (g.members.first { $0.id == g.lastSender }?.name ?? "")
            return (who.isEmpty ? "" : "\(who): ") + g.lastBody.replacingOccurrences(of: "\n", with: " ")
        }
    }
}

struct GroupAvatar: View {
    let group: NovaGroup?
    var size: CGFloat = 44
    @ObservedObject private var account = NovaAccount.shared

    var body: some View {
        if let url = group?.iconURL {
            NovaAvatar(name: group?.name ?? "G", color: "#8b7bff", url: url, size: size)
        } else {
            let others = (group?.members ?? []).filter { $0.id != account.me.userId }.prefix(2)
            ZStack {
                if others.count >= 2 {
                    let a = Array(others)
                    NovaAvatar(name: a[0].name, color: a[0].avatarColor, url: a[0].avatarURL, size: size * 0.7)
                        .offset(x: -size * 0.15, y: -size * 0.15)
                    NovaAvatar(name: a[1].name, color: a[1].avatarColor, url: a[1].avatarURL, size: size * 0.7)
                        .overlay(Circle().stroke(NovaTheme.bg, lineWidth: 2))
                        .offset(x: size * 0.15, y: size * 0.15)
                } else {
                    NovaAvatar(name: group?.name ?? "G", color: "#8b7bff", url: others.first?.avatarURL, size: size)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(NovaTheme.accentGradient)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(NovaTheme.text)
            Text(text).font(.system(size: 13.5)).foregroundColor(NovaTheme.dim).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Conversación

struct ChatView: View {
    let target: ChatTarget
    @ObservedObject private var account = NovaAccount.shared
    @StateObject private var chat: ChatSession
    @State private var draft = ""
    @State private var showProfile: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(target: ChatTarget) {
        self.target = target
        _chat = StateObject(wrappedValue: ChatSession(target: target))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(NovaTheme.stroke)
            messagesList
            composer
        }
        .background(NovaTheme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { await chat.open() }
        .onDisappear { chat.close() }
        .sheet(item: Binding(get: { showProfile.map { IdBox(id: $0) } }, set: { showProfile = $0?.id })) { box in
            FriendProfileSheet(userId: box.id, onMessage: nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var title: String {
        switch target {
        case .friend(let id): return account.friend(id)?.name ?? "Chat"
        case .group(let id): return account.group(id)?.name ?? "Grupo"
        }
    }
    private var subtitle: String {
        switch target {
        case .friend(let id): return account.friend(id)?.statusLine ?? ""
        case .group(let id):
            guard let g = account.group(id) else { return "" }
            let on = g.members.filter { $0.id == account.me.userId || ($0.status != .offline && $0.status != .invisible) }.count
            return "\(g.members.count) miembros · \(on) en línea"
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundColor(NovaTheme.text)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Volver")
            Button {
                if case .friend(let id) = target { showProfile = id }
            } label: {
                HStack(spacing: 10) {
                    switch target {
                    case .friend(let id):
                        let f = account.friend(id)
                        NovaAvatar(name: f?.name ?? "?", color: f?.avatarColor ?? "#7b6cff", url: f?.avatarURL, size: 38, status: f?.status)
                    case .group(let id):
                        GroupAvatar(group: account.group(id), size: 38)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(NovaTheme.text).lineLimit(1)
                        Text(subtitle).font(.system(size: 12)).foregroundColor(NovaTheme.dim).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if chat.hasMore {
                        Button("Cargar mensajes anteriores") { Task { await chat.loadOlder() } }
                            .font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.accent)
                            .padding(.vertical, 10)
                    }
                    if chat.loading {
                        ProgressView().tint(NovaTheme.accent).padding(40)
                    } else if let e = chat.error, chat.messages.isEmpty {
                        EmptyState(symbol: "exclamationmark.bubble", title: "No se pudo abrir", text: e)
                    } else if chat.messages.isEmpty {
                        EmptyState(symbol: "hand.wave", title: "Di hola 👋", text: "Este es el principio de vuestra conversación. Los mensajes también se ven en Nova para Windows.")
                    }
                    ForEach(Array(chat.messages.enumerated()), id: \.element.key) { i, m in
                        if i == 0 || !Calendar.current.isDate(m.at, inSameDayAs: chat.messages[i - 1].at) {
                            DaySeparator(date: m.at)
                        }
                        MessageBubble(message: m, mine: m.sender == account.me.userId,
                                      showName: isGroup && m.sender != account.me.userId && (i == 0 || chat.messages[i - 1].sender != m.sender),
                                      senderName: senderName(m.sender),
                                      seen: seenText(m, index: i),
                                      onEdit: { chat.editing = m; draft = m.body; focused = true },
                                      onDelete: { chat.delete(m) },
                                      onRetry: { chat.retry(m) })
                            .id(m.key)
                    }
                    Color.clear.frame(height: 6).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.last?.key) { _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var isGroup: Bool { if case .group = target { return true }; return false }

    private func senderName(_ id: String) -> String {
        if case .group(let gid) = target { return account.group(gid)?.members.first { $0.id == id }?.name ?? "Antiguo miembro" }
        return account.friend(id)?.name ?? ""
    }

    /// «Visto» bajo tu último mensaje que la otra persona ya ha leído (solo chats de amigos).
    private func seenText(_ m: ChatMessage, index: Int) -> String? {
        guard !isGroup, m.sender == account.me.userId, m.id > 0, chat.peerRead >= m.id else { return nil }
        let laterMine = chat.messages[(index + 1)...].contains { $0.sender == account.me.userId && $0.id > 0 && chat.peerRead >= $0.id }
        return laterMine ? nil : "Visto"
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let e = chat.editing {
                HStack {
                    Image(systemName: "pencil").foregroundColor(NovaTheme.accent)
                    Text("Editando: \(e.body)").lineLimit(1).foregroundColor(NovaTheme.dim)
                    Spacer()
                    Button("Cancelar") { chat.editing = nil; draft = "" }.foregroundColor(NovaTheme.accent)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 6)
            }
            if let e = chat.error, !chat.messages.isEmpty {
                Text(e).font(.system(size: 12.5)).foregroundColor(NovaTheme.danger).frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { chat.error = nil }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(chat.canSend ? "Escribe a \(title)…" : "No puedes escribir aquí", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.ink(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
                    .disabled(!chat.canSend)
                    .onChange(of: draft) { v in if !v.isEmpty { chat.userTyped() } }
                Button {
                    let t = draft
                    draft = ""
                    chat.send(t)
                } label: {
                    Image(systemName: chat.editing == nil ? "arrow.up" : "checkmark")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(NovaTheme.accentGradient))
                        .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chat.canSend)
                .accessibilityLabel(chat.editing == nil ? "Enviar" : "Guardar cambios")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(NovaTheme.surface.opacity(0.9).ignoresSafeArea(edges: .bottom))
    }
}

struct IdBox: Identifiable { let id: String }

struct DaySeparator: View {
    let date: Date
    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold)).foregroundColor(NovaTheme.faint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(NovaTheme.ink(0.05)))
            .padding(.vertical, 10)
    }
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Hoy" }
        if cal.isDateInYesterday(date) { return "Ayer" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f.string(from: date).capitalized
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let mine: Bool
    let showName: Bool
    let senderName: String
    let seen: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// Texto con los enlaces (https://…) pulsables.
    static func linkified(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return a }
        let ns = s as NSString
        for m in det.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            guard let url = m.url, let r = Range(m.range, in: s), let ar = Range(r, in: a) else { continue }
            a[ar].link = url
            a[ar].underlineStyle = .single
        }
        return a
    }

    var body: some View {
        if !message.system.isEmpty {
            Text(message.body.isEmpty ? "Aviso del grupo" : message.body)
                .font(.system(size: 12)).foregroundColor(NovaTheme.faint)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
        } else {
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if showName {
                    Text(senderName).font(.system(size: 11.5, weight: .semibold)).foregroundColor(NovaTheme.accent).padding(.horizontal, 6)
                }
                HStack {
                    if mine { Spacer(minLength: 50) }
                    bubble
                    if !mine { Spacer(minLength: 50) }
                }
                if let s = seen {
                    Text(s).font(.system(size: 11)).foregroundColor(NovaTheme.faint).padding(.horizontal, 6)
                }
                if message.failed {
                    Button("No enviado · Toca para reintentar", action: onRetry)
                        .font(.system(size: 11.5, weight: .medium)).foregroundColor(NovaTheme.danger)
                }
            }
            .padding(.top, showName ? 6 : 0)
        }
    }

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if message.deleted {
                Text("Mensaje eliminado").italic().foregroundColor(mine ? .white.opacity(0.7) : NovaTheme.faint)
            } else {
                Text(Self.linkified(message.body))
                    .foregroundColor(mine ? .white : NovaTheme.text)
                    .tint(mine ? .white : NovaTheme.accent2)
                    .textSelection(.enabled)
            }
            HStack(spacing: 4) {
                if message.edited && !message.deleted { Text("editado") }
                Text(Self.timeFmt.string(from: message.at))
                if mine {
                    Image(systemName: message.pending ? "clock" : (message.failed ? "exclamationmark.circle" : "checkmark"))
                }
            }
            .font(.system(size: 10.5))
            .foregroundColor(mine ? .white.opacity(0.7) : NovaTheme.faint)
        }
        .font(.system(size: 15.5))
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(mine ? AnyShapeStyle(NovaTheme.accentGradient) : AnyShapeStyle(NovaTheme.ink(0.07)))
        )
        .opacity(message.pending ? 0.7 : 1)
        .contextMenu {
            if !message.deleted {
                Button { UIPasteboard.general.string = message.body } label: { Label("Copiar", systemImage: "doc.on.doc") }
                if mine && message.id > 0 {
                    Button(action: onEdit) { Label("Editar", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label("Eliminar", systemImage: "trash") }
                }
            }
        }
    }
}

// MARK: - Amigos

struct FriendsView: View {
    let openChat: (String) -> Void
    @ObservedObject private var account = NovaAccount.shared
    @State private var codeInput = ""
    @State private var preview: NovaAccount.CodePreview = .none
    @State private var addMessage: String?
    @State private var addOK = false
    @State private var adding = false
    @State private var showProfile: String?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                codeCard
                addCard
                if !account.requests.isEmpty { requestsCard }
                friendsCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .refreshable { await account.reloadSocial(includeFriends: true) }
        .sheet(item: Binding(get: { showProfile.map { IdBox(id: $0) } }, set: { showProfile = $0?.id })) { box in
            FriendProfileSheet(userId: box.id, onMessage: { showProfile = nil; openChat(box.id) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundColor(NovaTheme.dim).padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .novaCard(radius: 18)
        }
    }

    private var codeCard: some View {
        section("Tu código de amigo") {
            HStack {
                Text(account.me.friendCode.isEmpty ? "— — — —" : NovaAccount.formatCode(account.me.friendCode))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(NovaTheme.accentGradient)
                Spacer()
                Button {
                    UIPasteboard.general.string = NovaAccount.formatCode(account.me.friendCode)
                    Haptics.success()
                    account.flash("Código de amigo copiado")
                } label: { Image(systemName: "doc.on.doc").frame(width: 38, height: 38).background(Circle().fill(NovaTheme.ink(0.06))) }
                .disabled(account.me.friendCode.isEmpty)
                ShareLink(item: "Añádeme en Nova con mi código de amigo: \(NovaAccount.formatCode(account.me.friendCode))") {
                    Image(systemName: "square.and.arrow.up").frame(width: 38, height: 38).background(Circle().fill(NovaTheme.ink(0.06)))
                }
            }
            .foregroundColor(NovaTheme.text)
            Text("Pásaselo a quien quieras: lo puede añadir aquí, en la web o en Nova → Amigos.")
                .font(.system(size: 12.5)).foregroundColor(NovaTheme.dim)
        }
    }

    private var addCard: some View {
        section("Añadir amigo") {
            HStack(spacing: 8) {
                TextField("Código, p. ej. ABCD-2345", text: $codeInput)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 16, design: .monospaced))
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.ink(0.05)))
                Button {
                    Task { await add() }
                } label: {
                    Group { if adding { ProgressView().tint(.white) } else { Text("Añadir") } }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accentGradient))
                }
                .disabled(adding || NovaAccount.parseCode(codeInput).isEmpty)
            }
            switch preview {
            case .none: EmptyView()
            case .notFound:
                Text("No hay ningún usuario con ese código.").font(.system(size: 13)).foregroundColor(NovaTheme.dim)
            case .user(let name, let color, let avatar, let note):
                HStack(spacing: 10) {
                    NovaAvatar(name: name, color: color, url: avatar, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.system(size: 14, weight: .semibold)).foregroundColor(NovaTheme.text)
                        Text(note).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                    }
                }
            }
            StatusText(text: addMessage, ok: addOK)
        }
        .onChange(of: codeInput) { v in
            addMessage = nil
            previewTask?.cancel()
            let code = NovaAccount.parseCode(v)
            guard !code.isEmpty else { preview = .none; return }
            previewTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                let p = await account.previewCode(code)
                if !Task.isCancelled && NovaAccount.parseCode(codeInput) == code { preview = p }
            }
        }
    }

    private func add() async {
        let code = NovaAccount.parseCode(codeInput)
        guard !code.isEmpty else { addMessage = "Ese código no es válido. Tiene 8 letras y números, por ejemplo ABCD-2345."; addOK = false; return }
        adding = true
        let (msg, ok) = await account.addFriend(code: code)
        adding = false
        addMessage = msg; addOK = ok
        if ok { codeInput = ""; preview = .none; Haptics.success() }
    }

    private var requestsCard: some View {
        section("Solicitudes · \(account.requests.count)") {
            ForEach(account.requests) { r in
                HStack(spacing: 10) {
                    NovaAvatar(name: r.name, color: r.avatarColor, url: r.avatarURL, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                        Text("Quiere ser tu amigo").font(.system(size: 12.5)).foregroundColor(NovaTheme.dim)
                    }
                    Spacer()
                    Button { Task { await account.respond(r, accept: false) } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(NovaTheme.danger)
                            .frame(width: 36, height: 36).background(Circle().fill(NovaTheme.danger.opacity(0.12)))
                    }
                    .accessibilityLabel("Rechazar a \(r.name)")
                    Button { Task { await account.respond(r, accept: true) } } label: {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(NovaTheme.good)
                            .frame(width: 36, height: 36).background(Circle().fill(NovaTheme.good.opacity(0.14)))
                    }
                    .accessibilityLabel("Aceptar a \(r.name)")
                }
            }
        }
    }

    private var friendsCard: some View {
        section("Amigos · \(account.onlineFriends) en línea de \(account.friends.count)") {
            if account.friends.isEmpty {
                Text("Aún no tienes amigos en Nova. Añade a alguien con su código o comparte el tuyo.")
                    .font(.system(size: 13.5)).foregroundColor(NovaTheme.dim)
            }
            ForEach(account.friends.sorted { ($0.status.order, $0.name.lowercased()) < ($1.status.order, $1.name.lowercased()) }) { f in
                Button { showProfile = f.id } label: {
                    HStack(spacing: 12) {
                        NovaAvatar(name: f.name, color: f.avatarColor, url: f.avatarURL, size: 42, status: f.status)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                            Text(f.statusLine).font(.system(size: 12.5)).foregroundColor(NovaTheme.dim).lineLimit(1)
                        }
                        Spacer()
                        Button { openChat(f.id) } label: {
                            Image(systemName: "bubble.left.fill").font(.system(size: 14)).foregroundColor(NovaTheme.accent)
                                .frame(width: 36, height: 36).background(Circle().fill(NovaTheme.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Escribir a \(f.name)")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Perfil de un amigo

struct FriendProfileSheet: View {
    let userId: String
    let onMessage: (() -> Void)?
    @ObservedObject private var account = NovaAccount.shared
    @State private var profile: NovaAccount.PublicProfile?
    @State private var loading = true
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            if loading {
                ProgressView().tint(NovaTheme.accent).padding(60)
            } else if let p = profile {
                ProfileCard(name: p.name, username: p.username, pronouns: p.pronouns, bio: p.bio, about: p.about, fields: p.fields,
                            avatarColor: p.avatarColor, avatarURL: p.avatarURL, bannerURL: p.bannerURL,
                            themePrimary: p.themePrimary, themeAccent: p.themeAccent, decoration: p.decoration,
                            isPremium: p.isPremium, isOwner: p.isOwner, badges: p.badges, memberSince: p.memberSince,
                            status: account.friend(userId)?.status, activity: account.friend(userId)?.activity ?? "")
                VStack(spacing: 10) {
                    if let onMessage = onMessage, account.friend(userId) != nil {
                        NovaPrimaryButton(title: "Enviar mensaje", action: onMessage)
                    }
                    if let f = account.friend(userId) {
                        Button(role: .destructive) { confirmRemove = true } label: {
                            Text("Eliminar amigo").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .confirmationDialog("¿Eliminar a \(f.name) de tus amigos?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Eliminar", role: .destructive) { Task { await account.removeFriend(f); dismiss() } }
                            Button("Cancelar", role: .cancel) {}
                        }
                    }
                }
                .padding(16)
            } else {
                EmptyState(symbol: "person.crop.circle.badge.questionmark", title: "No se pudo cargar el perfil", text: "Inténtalo de nuevo en un momento.")
            }
        }
        .background(NovaTheme.bg.ignoresSafeArea())
        .task {
            profile = await account.loadProfile(userId)
            loading = false
        }
        .novaAppearance()
    }
}

// MARK: - Tarjeta de perfil (la misma para ti y para tus amigos)

struct ProfileCard: View {
    let name: String
    let username: String
    let pronouns: String
    let bio: String
    let about: String
    let fields: [ProfileField]
    let avatarColor: String
    let avatarURL: URL?
    let bannerURL: URL?
    let themePrimary: String
    let themeAccent: String
    let decoration: String
    let isPremium: Bool
    let isOwner: Bool
    let badges: [String]
    let memberSince: Date?
    var status: NovaStatus?
    var activity: String = ""

    private var bannerGradient: LinearGradient {
        LinearGradient(colors: [Color(novaHex: themePrimary.isEmpty ? avatarColor : themePrimary), Color(novaHex: themeAccent, fallback: 0xFF6FCF)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                bannerGradient
                if let u = bannerURL {
                    AsyncImage(url: u) { ph in if let i = ph.image { i.resizable().scaledToFill() } else { Color.clear } }
                }
            }
            .frame(height: 120)
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                NovaAvatar(name: name, color: avatarColor, url: avatarURL, size: 88, status: status,
                           ring: ["orbit", "spark", "frame"].contains(decoration) || (isPremium && decoration != "halo" && decoration != "none"))
                    .shadow(color: decoration == "halo" ? Color(novaHex: themePrimary.isEmpty ? avatarColor : themePrimary).opacity(0.8) : .clear, radius: 14)
                    .overlay(Circle().stroke(NovaTheme.surface, lineWidth: 5).frame(width: 96, height: 96))
                    .padding(.top, -48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 24, weight: .bold)).foregroundColor(NovaTheme.text)
                    HStack(spacing: 6) {
                        if !username.isEmpty { Text("@\(username)") }
                        if !pronouns.isEmpty { Text("· \(pronouns)") }
                    }
                    .font(.system(size: 14)).foregroundColor(NovaTheme.dim)
                }
                if !activity.isEmpty {
                    Label(activity, systemImage: "sparkles").font(.system(size: 13)).foregroundColor(NovaTheme.accent2)
                }
                if isOwner || isPremium || !badges.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if isOwner { chip("Owner", "crown.fill", Color(hex: 0xFFC94D)) }
                            if isPremium { chip("Nova Premium", "star.fill", NovaTheme.accent) }
                            ForEach(badges.prefix(6), id: \.self) { b in chip(b, "seal.fill", NovaTheme.accent2) }
                        }
                    }
                }
                if !bio.isEmpty { Text(bio).font(.system(size: 15)).foregroundColor(NovaTheme.text) }
                if !about.isEmpty { block("Sobre mí") { Text(about).font(.system(size: 14)).foregroundColor(NovaTheme.ink(0.85)) } }
                let fs = fields.filter { !$0.label.isEmpty && !$0.value.isEmpty }
                if !fs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fs) { f in
                            HStack(alignment: .top) {
                                Text(f.label).font(.system(size: 13, weight: .semibold)).foregroundColor(NovaTheme.dim).frame(width: 110, alignment: .leading)
                                Text(f.value).font(.system(size: 14)).foregroundColor(NovaTheme.text)
                            }
                        }
                    }
                }
                if let d = memberSince {
                    block("Miembro desde") {
                        Text(d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es_ES"))))
                            .font(.system(size: 14)).foregroundColor(NovaTheme.ink(0.85))
                    }
                }
            }
            .padding(16)
        }
        .background(NovaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func chip(_ t: String, _ icon: String, _ c: Color) -> some View {
        Label(t, systemImage: icon).font(.system(size: 11.5, weight: .semibold)).foregroundColor(c)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(c.opacity(0.13)))
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundColor(NovaTheme.faint)
            content()
        }
    }
}

// MARK: - Mi perfil

struct MyProfileView: View {
    @ObservedObject private var account = NovaAccount.shared
    @State private var editing = false
    @State private var confirmLogout = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                let m = account.me
                ProfileCard(name: m.name, username: m.username, pronouns: m.pronouns, bio: m.bio, about: m.about, fields: m.fields,
                            avatarColor: m.avatarColor, avatarURL: m.avatarURL, bannerURL: m.bannerURL,
                            themePrimary: m.themePrimary, themeAccent: m.themeAccent, decoration: m.decoration,
                            isPremium: m.isPremium, isOwner: m.role == "owner", badges: m.showBadges ? m.badges : [],
                            memberSince: m.showMemberSince ? m.memberSince : nil, status: m.status)
                VStack(spacing: 10) {
                    statusMenu
                    NovaPrimaryButton(title: "Personalizar perfil") { editing = true }
                    Button(role: .destructive) { confirmLogout = true } label: {
                        Text("Cerrar sesión").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .confirmationDialog("¿Cerrar la sesión de Nova en este iPhone?", isPresented: $confirmLogout, titleVisibility: .visible) {
                        Button("Cerrar sesión", role: .destructive) { Task { await account.signOut() } }
                        Button("Cancelar", role: .cancel) {}
                    }
                    Text(m.email).font(.system(size: 12)).foregroundColor(NovaTheme.faint)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .refreshable { await account.reloadAll() }
        .fullScreenCover(isPresented: $editing) { EditProfileView() }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(NovaStatus.selectable) { s in
                Button { Haptics.select(); account.setPresence(s) } label: {
                    Label(s.title, systemImage: account.me.status == s ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            HStack {
                Circle().fill(account.me.status.color).frame(width: 10, height: 10)
                Text("Estado: \(account.me.status.title)").foregroundColor(NovaTheme.text)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundColor(NovaTheme.faint)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 14).frame(height: 48)
            .novaCard(radius: 14)
        }
    }
}

// MARK: - Personalizar perfil

struct EditProfileView: View {
    @ObservedObject private var account = NovaAccount.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MyProfile()
    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var newAvatar: Data??          // nil = sin cambios · .some(nil) = quitar
    @State private var newBanner: Data??
    @State private var avatarPreview: UIImage?
    @State private var bannerPreview: UIImage?
    @State private var saving = false
    @State private var message: String?
    @State private var userHint: String?
    @State private var userOK = false
    @State private var userTask: Task<Void, Never>?
    @State private var loaded = false

    private let avatarColors = ["#7b6cff", "#ff873e", "#ff4f64", "#2fbf8f", "#3da5ff", "#e05bd0"]
    private let decorations: [(String, String)] = [("none", "Ninguna"), ("halo", "Halo"), ("orbit", "Órbita"), ("spark", "Chispas"), ("frame", "Marco")]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    mediaSection
                    group("Nombre") {
                        NovaTextField(title: "Nombre visible", text: $draft.name)
                        NovaTextField(title: "Nombre de usuario", text: $draft.username)
                        if let h = userHint { Text(h).font(.system(size: 12.5)).foregroundColor(userOK ? NovaTheme.good : NovaTheme.dim) }
                        NovaTextField(title: "Pronombres", text: $draft.pronouns)
                    }
                    group("Sobre ti") {
                        counterField("Descripción corta", text: $draft.bio, max: 80)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sobre mí").font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.dim)
                                Spacer()
                                Text("\(draft.about.count)/190").font(.system(size: 12)).foregroundColor(NovaTheme.faint)
                            }
                            TextEditor(text: $draft.about)
                                .frame(minHeight: 96)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.ink(0.05)))
                                .onChange(of: draft.about) { v in if v.count > 190 { draft.about = String(v.prefix(190)) } }
                        }
                        fieldsEditor
                    }
                    group("Colores y decoración") {
                        Text("Color del avatar sin foto").font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.dim)
                        HStack(spacing: 10) {
                            ForEach(avatarColors, id: \.self) { c in
                                Circle().fill(Color(novaHex: c)).frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(NovaTheme.text, lineWidth: draft.avatarColor.lowercased() == c ? 2.5 : 0).padding(-4))
                                    .onTapGesture { Haptics.select(); draft.avatarColor = c }
                            }
                        }
                        HStack(spacing: 18) {
                            ColorPicker("Principal", selection: colorBinding(\.themePrimary, fallback: 0x7B6CFF), supportsOpacity: false)
                            ColorPicker("Acento", selection: colorBinding(\.themeAccent, fallback: 0xFF6FCF), supportsOpacity: false)
                        }
                        .font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.text)
                        Button("Colores por defecto") { draft.themePrimary = ""; draft.themeAccent = "" }
                            .font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.accent)
                        Text("Decoración del avatar").font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.dim)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(0..<decorations.count, id: \.self) { i in
                                    let d = decorations[i]
                                    let locked = !account.me.isPremium && ["orbit", "spark", "frame"].contains(d.0) && draft.decoration != d.0
                                    Button {
                                        guard !locked else { message = "Esa decoración es de Nova Premium."; return }
                                        Haptics.select(); draft.decoration = d.0
                                    } label: {
                                        HStack(spacing: 4) {
                                            if locked { Image(systemName: "lock.fill").font(.system(size: 10)) }
                                            Text(d.1)
                                        }
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundColor(draft.decoration == d.0 ? .white : NovaTheme.text)
                                        .padding(.horizontal, 14).frame(height: 36)
                                        .background(Capsule().fill(draft.decoration == d.0 ? AnyShapeStyle(NovaTheme.accentGradient) : AnyShapeStyle(NovaTheme.ink(0.06))))
                                        .opacity(locked ? 0.55 : 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    group("Privacidad") {
                        Toggle("Mostrar «Miembro desde»", isOn: $draft.showMemberSince).tint(NovaTheme.accent)
                        Toggle("Mostrar mis insignias", isOn: $draft.showBadges).tint(NovaTheme.accent)
                    }
                    .font(.system(size: 15)).foregroundColor(NovaTheme.text)
                    Text("Se guarda en tu cuenta Nova: tus amigos lo verán igual en el navegador. El estilo del nombre y las fotos animadas se cambian desde Nova para Windows.")
                        .font(.system(size: 12)).foregroundColor(NovaTheme.faint)
                    StatusText(text: message)
                }
                .padding(18)
            }
            .background(NovaTheme.bg.ignoresSafeArea())
            .navigationTitle("Personalizar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Guardar") { Task { await save() } }.fontWeight(.semibold) }
                }
            }
        }
        .tint(NovaTheme.accent)
        .novaAppearance()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = account.me
        }
        .onChange(of: avatarItem) { item in load(item, banner: false) }
        .onChange(of: bannerItem) { item in load(item, banner: true) }
        .onChange(of: draft.username) { v in checkUsername(v) }
        .onChange(of: draft.bio) { v in if v.count > 80 { draft.bio = String(v.prefix(80)) } }
        .onChange(of: draft.name) { v in if v.count > 24 { draft.name = String(v.prefix(24)) } }
        .onChange(of: draft.pronouns) { v in if v.count > 40 { draft.pronouns = String(v.prefix(40)) } }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1).foregroundColor(NovaTheme.dim)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .novaCard(radius: 18)
        }
    }

    private func counterField(_ title: String, text: Binding<String>, max: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            NovaTextField(title: title, text: text)
            Text("\(text.wrappedValue.count)/\(max)").font(.system(size: 11.5)).foregroundColor(NovaTheme.faint)
        }
    }

    private func colorBinding(_ key: WritableKeyPath<MyProfile, String>, fallback: UInt32) -> Binding<Color> {
        Binding(get: { Color(novaHex: draft[keyPath: key], fallback: fallback) },
                set: { draft[keyPath: key] = $0.novaHexString })
    }

    // Foto y banner
    private var mediaSection: some View {
        group("Foto y banner") {
            ZStack(alignment: .bottomLeading) {
                ZStack {
                    LinearGradient(colors: [Color(novaHex: draft.themePrimary.isEmpty ? draft.avatarColor : draft.themePrimary),
                                            Color(novaHex: draft.themeAccent, fallback: 0xFF6FCF)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let b = bannerPreview { Image(uiImage: b).resizable().scaledToFill() }
                    else if newBanner == nil, let u = draft.bannerURL {
                        AsyncImage(url: u) { ph in if let i = ph.image { i.resizable().scaledToFill() } else { Color.clear } }
                    }
                }
                .frame(height: 110).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Group {
                    if let a = avatarPreview {
                        Image(uiImage: a).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                    } else {
                        NovaAvatar(name: draft.name, color: draft.avatarColor, url: newAvatar == nil ? draft.avatarURL : nil, size: 72)
                    }
                }
                .overlay(Circle().stroke(NovaTheme.surface, lineWidth: 4))
                .offset(x: 14, y: 30)
            }
            .padding(.bottom, 30)
            HStack(spacing: 8) {
                PhotosPicker(selection: $avatarItem, matching: .images) { pill("Cambiar foto", "camera.fill") }
                Button { newAvatar = .some(nil); avatarPreview = nil; draft.avatarURL = nil } label: { pill("Quitar", "trash") }
                    .disabled(draft.avatarURL == nil && avatarPreview == nil)
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $bannerItem, matching: .images) { pill("Cambiar banner", "photo.fill") }
                Button { newBanner = .some(nil); bannerPreview = nil; draft.bannerURL = nil } label: { pill("Quitar", "trash") }
                    .disabled(draft.bannerURL == nil && bannerPreview == nil)
            }
        }
    }

    private func pill(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.system(size: 13.5, weight: .semibold)).foregroundColor(NovaTheme.text)
            .padding(.horizontal, 14).frame(height: 38)
            .background(Capsule().fill(NovaTheme.ink(0.06)))
    }

    private func load(_ item: PhotosPickerItem?, banner: Bool) {
        guard let item = item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
                message = "No se pudo abrir la imagen."
                return
            }
            if banner {
                let out = Self.crop(img, width: 1200, height: 400)
                bannerPreview = out
                newBanner = .some(out.pngData())
                bannerItem = nil
            } else {
                let out = Self.crop(img, width: 512, height: 512)
                avatarPreview = out
                newAvatar = .some(out.pngData())
                avatarItem = nil
            }
        }
    }

    /// Recorte centrado al tamaño exacto (como la web: cuadrado para la foto, panorámico para el banner).
    static func crop(_ img: UIImage, width: CGFloat, height: CGFloat) -> UIImage {
        let target = CGSize(width: width, height: height)
        let scale = max(target.width / img.size.width, target.height / img.size.height)
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height))
        }
    }

    // Campos personalizados (hasta 3)
    private var fieldsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Campos personalizados (hasta 3)").font(.system(size: 13, weight: .medium)).foregroundColor(NovaTheme.dim)
            ForEach($draft.fields) { $f in
                HStack(spacing: 8) {
                    TextField("Etiqueta", text: $f.label).frame(width: 110)
                    TextField("Valor", text: $f.value)
                    Button { draft.fields.removeAll { $0.id == f.id } } label: {
                        Image(systemName: "minus.circle.fill").foregroundColor(NovaTheme.danger)
                    }
                }
                .font(.system(size: 14.5))
                .padding(.horizontal, 10).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NovaTheme.ink(0.05)))
                .onChange(of: f.label) { v in if v.count > 24 { f.label = String(v.prefix(24)) } }
                .onChange(of: f.value) { v in if v.count > 80 { f.value = String(v.prefix(80)) } }
            }
            if draft.fields.count < 3 {
                Button { draft.fields.append(ProfileField(label: "", value: "")) } label: { pill("Añadir campo", "plus") }
            }
        }
    }

    private func checkUsername(_ raw: String) {
        let lower = raw.lowercased()
        if lower != raw { draft.username = lower; return }
        userTask?.cancel()
        let v = lower.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { userHint = "Sin @: tus amigos verán solo tu nombre visible."; userOK = false; return }
        if v == account.me.username { userHint = "Este es tu nombre de usuario actual."; userOK = true; return }
        guard NovaAccount.validUsername(v) else {
            userHint = "3–20 letras minúsculas, números, punto o guion bajo."; userOK = false; return
        }
        userHint = "Comprobando…"; userOK = false
        userTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            if Task.isCancelled { return }
            let ok = await account.usernameAvailable(v)
            if Task.isCancelled { return }
            switch ok {
            case .some(true): userHint = "@\(v) está libre."; userOK = true
            case .some(false): userHint = "@\(v) ya está en uso."; userOK = false
            case .none: userHint = nil
            }
        }
    }

    private func save() async {
        message = nil
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 && name.count <= 24 else { message = "El nombre visible debe tener entre 2 y 24 caracteres."; return }
        let u = draft.username.trimmingCharacters(in: .whitespaces)
        if !u.isEmpty && !NovaAccount.validUsername(u) { message = NovaAccount.saveMessages["username_invalid"]; return }
        if draft.about.components(separatedBy: "\n").count > 7 { message = "«Sobre mí» admite como máximo 7 líneas."; return }
        let fields = draft.fields.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        if fields.contains(where: { $0.label.trimmingCharacters(in: .whitespaces).isEmpty || $0.value.trimmingCharacters(in: .whitespaces).isEmpty }) {
            message = "Cada campo necesita etiqueta y valor (o quítalo)."; return
        }
        saving = true
        do {
            try await account.saveProfile(draft, avatar: newAvatar, banner: newBanner)
            saving = false
            dismiss()
        } catch {
            saving = false
            message = (error as? LocalizedError)?.errorDescription ?? "No se pudo guardar el perfil."
        }
    }
}
