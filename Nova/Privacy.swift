import SwiftUI
import WebKit
import LocalAuthentication

// MARK: - Seguridad (Face ID) y estado de privacidad

/// Gestiona el bloqueo con Face ID / Touch ID / código del iPhone.
/// - lockApp: pide autenticación al abrir Nova y al volver de segundo plano.
/// - lockPrivate: pide autenticación para abrir la navegación privada.
final class PrivacyStore: ObservableObject {
    static let shared = PrivacyStore()

    @Published var lockApp: Bool { didSet { UserDefaults.standard.set(lockApp, forKey: "lockApp") } }
    @Published var lockPrivate: Bool { didSet { UserDefaults.standard.set(lockPrivate, forKey: "lockPrivate") } }
    @Published private(set) var isLocked: Bool
    /// true cuando la navegación privada ya se desbloqueó en esta sesión.
    @Published private(set) var privateUnlocked = false
    @Published var message: String?

    private var authInFlight = false

    private init() {
        UserDefaults.standard.register(defaults: ["lockApp": false, "lockPrivate": true])
        let app = UserDefaults.standard.bool(forKey: "lockApp")
        lockApp = app
        lockPrivate = UserDefaults.standard.bool(forKey: "lockPrivate")
        isLocked = app
    }

    // MARK: Información del dispositivo

    static var biometryName: String {
        let ctx = LAContext()
        var err: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "el código"
        }
    }

    static var canAuthenticate: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    // MARK: Autenticación

    /// Pide Face ID (con el código del iPhone como alternativa si falla).
    func authenticate(reason: String, _ completion: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancelar"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // Sin código ni biometría en el iPhone no se puede proteger nada:
            // no se deja al usuario fuera de su propia app.
            DispatchQueue.main.async {
                self.message = "Activa Face ID o un código en Ajustes de iOS para usar el bloqueo."
                completion(true)
            }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// Desbloquea la app completa.
    func unlock() {
        guard isLocked, !authInFlight else { return }
        authInFlight = true
        authenticate(reason: "Desbloquea Nova") { [weak self] ok in
            guard let self = self else { return }
            self.authInFlight = false
            if ok {
                self.isLocked = false
                self.privateUnlocked = true
                Haptics.success()
            }
        }
    }

    /// Antes de abrir/mostrar pestañas privadas.
    func requestPrivateAccess(_ completion: @escaping (Bool) -> Void) {
        guard lockPrivate, !privateUnlocked else { completion(true); return }
        authenticate(reason: "Abrir la navegación privada") { [weak self] ok in
            if ok { self?.privateUnlocked = true }
            completion(ok)
        }
    }

    /// Se llama al pasar a segundo plano.
    func enteredBackground(activeIsPrivate: Bool) {
        privateUnlocked = false
        if lockApp {
            isLocked = true
        } else if lockPrivate && activeIsPrivate {
            isLocked = true
        }
    }
}

// MARK: - Pantalla de bloqueo y protector del selector de apps

struct LockScreenView: View {
    @ObservedObject private var privacy = PrivacyStore.shared

    var body: some View {
        ZStack {
            NovaBackground().ignoresSafeArea()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                NovaMark(size: 66)
                Text("Nova está bloqueado")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(NovaTheme.text)
                Text("Usa \(PrivacyStore.biometryName) para continuar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
                Button {
                    Haptics.tap()
                    privacy.unlock()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Desbloquear")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .frame(height: 48)
                    .background(Capsule().fill(NovaTheme.accentGradient))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 6)

                if let m = privacy.message {
                    Text(m)
                        .font(.system(size: 12))
                        .foregroundColor(NovaTheme.warn)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if UIApplication.shared.applicationState == .active { privacy.unlock() }
            }
        }
    }
}

/// Tapa el contenido cuando Nova no está en primer plano (selector de apps, Centro de control).
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            NovaTheme.bg
            NovaMark(size: 72)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Tema de navegación privada

enum PrivateTheme {
    static let bg      = Color.nova(light: Color(hex: 0xF4EFFB), dark: Color(hex: 0x0A0710))
    static let surface = Color.nova(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x15101F))
    static let accent  = Color.nova(light: Color(hex: 0x7B4FE0), dark: Color(hex: 0xB68CFF))
}

struct PrivateBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(colors: [Color(hex: 0x170D2A), Color(hex: 0x0A0710)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x6B3FD1, opacity: 0.30), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 480)
                RadialGradient(colors: [Color(hex: 0x3A1D78, opacity: 0.28), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 520)
            } else {
                LinearGradient(colors: [Color(hex: 0xF8F4FE), Color(hex: 0xEDE6F8)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xB68CFF, opacity: 0.30), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 480)
                RadialGradient(colors: [Color(hex: 0x8D6BE8, opacity: 0.18), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 520)
            }
        }
    }
}

struct PrivateTopBar: View {
    var openSettings: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PrivateTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(PrivateTheme.accent.opacity(0.16)))
                Text("Privada")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(NovaTheme.text)
            }
            Spacer()
            Button {
                Haptics.tap()
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(NovaTheme.ink(0.9))
                    .frame(width: 40, height: 40)
                    .novaGlass(radius: 14, shadow: false)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Configuración")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

/// Inicio de una pestaña privada: explica qué protege y qué no, con buscador propio.
struct PrivateHomeView: View {
    @ObservedObject var model: BrowserModel
    @State private var query = ""
    @State private var confirmClose = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(PrivateTheme.accent)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(PrivateTheme.accent.opacity(0.14)))
                    .overlay(Circle().stroke(PrivateTheme.accent.opacity(0.35), lineWidth: 1))
                    .padding(.top, 34)

                VStack(spacing: 8) {
                    Text("Navegación privada")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(NovaTheme.text)
                    Text("Estas pestañas no guardan historial, cookies, contraseñas ni datos de sitios. Todo se borra al cerrarlas.")
                        .font(.system(size: 14))
                        .foregroundColor(NovaTheme.dim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                }

                searchField

                VStack(spacing: 0) {
                    PrivateFeatureRow(symbol: "internaldrive.fill", title: "Sin rastro en el dispositivo",
                                      detail: "Cookies y caché viven solo en memoria")
                    Divider().background(NovaTheme.stroke).padding(.leading, 56)
                    PrivateFeatureRow(symbol: "shield.lefthalf.filled", title: "Rastreadores bloqueados",
                                      detail: "Anuncios y analíticas de terceros conocidos")
                    Divider().background(NovaTheme.stroke).padding(.leading, 56)
                    PrivateFeatureRow(symbol: "faceid", title: "Protegida con \(PrivacyStore.biometryName)",
                                      detail: "Se vuelve a pedir al regresar a Nova")
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PrivateTheme.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
                .padding(.horizontal, 18)

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        model.leavePrivateMode()
                    } label: {
                        Text("Salir del modo privado")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NovaTheme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.surfaceHi))
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        confirmClose = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(NovaTheme.danger)
                            .frame(width: 44, height: 44)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(NovaTheme.danger.opacity(0.14)))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Cerrar y borrar pestañas privadas")
                }
                .padding(.horizontal, 18)

                Text("La navegación privada no te hace anónimo: los sitios, tu red o tu proveedor de internet pueden seguir viendo tu actividad.")
                    .font(.system(size: 11.5))
                    .foregroundColor(NovaTheme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
            }
        }
        .confirmationDialog("¿Cerrar y borrar las pestañas privadas?",
                            isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Cerrar y borrar", role: .destructive) { model.closeAllTabs(private: true) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán sus cookies y datos de sitios.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(NovaTheme.dim)
            TextField("Buscar o escribir una dirección", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($focused)
                .foregroundColor(NovaTheme.text)
                .tint(PrivateTheme.accent)
                .onSubmit {
                    let q = query
                    query = ""
                    focused = false
                    model.load(q)
                }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PrivateTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(focused ? PrivateTheme.accent.opacity(0.8) : NovaTheme.stroke, lineWidth: focused ? 1.4 : 1))
        .padding(.horizontal, 18)
    }
}

private struct PrivateFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(PrivateTheme.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PrivateTheme.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(NovaTheme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Bloqueo de rastreadores (solo pestañas privadas)

enum TrackerBlocker {
    /// Expresiones de WebKit Content Blocker (sin alternancia "|"). Solo se bloquean
    /// peticiones de terceros, así que las propias webs de estas empresas siguen funcionando.
    private static let patterns = [
        "doubleclick\\.net", "google-analytics\\.com", "googletagmanager\\.com",
        "googlesyndication\\.com", "googleadservices\\.com", "adservice\\.google\\.",
        "connect\\.facebook\\.net/.*/fbevents", "scorecardresearch\\.com", "hotjar\\.com",
        "criteo\\.(com|net)", "taboola\\.com", "outbrain\\.com", "adnxs\\.com",
        "quantserve\\.com", "mixpanel\\.com", "amplitude\\.com", "clarity\\.ms",
        "optimizely\\.com", "moatads\\.com", "rubiconproject\\.com", "pubmatic\\.com",
        "openx\\.net", "adsrvr\\.org", "ads\\.linkedin\\.com", "snap\\.licdn\\.com",
        "analytics\\.tiktok\\.com", "analytics\\.twitter\\.com", "ads-twitter\\.com",
        "amazon-adsystem\\.com", "bat\\.bing\\.com", "chartbeat\\.(com|net)", "fullstory\\.com"
    ]

    private static var compiled: WKContentRuleList?
    private static var compiling = false
    private static var waiting: [(WKContentRuleList) -> Void] = []

    static func install(on controller: WKUserContentController) {
        if let list = compiled {
            controller.add(list)
            return
        }
        waiting.append { controller.add($0) }
        compile()
    }

    private static func compile() {
        guard !compiling else { return }
        compiling = true
        let rules: [[String: Any]] = patterns.map { p -> [String: Any] in
            let trigger: [String: Any] = ["url-filter": p, "load-type": ["third-party"]]
            let action: [String: Any] = ["type": "block"]
            return ["trigger": trigger, "action": action]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else {
            compiling = false
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "NovaPrivateTrackers",
            encodedContentRuleList: json
        ) { list, _ in
            DispatchQueue.main.async {
                TrackerBlocker.compiling = false
                guard let list = list else { return }
                TrackerBlocker.compiled = list
                let pending = TrackerBlocker.waiting
                TrackerBlocker.waiting = []
                pending.forEach { $0(list) }
            }
        }
    }
}
