import SwiftUI
import WebKit
import PhotosUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engine") private var engineRaw = SearchEngine.google.rawValue
    @AppStorage("showShortcuts") private var showShortcuts = true
    @ObservedObject private var bg = HomeBackgroundStore.shared
    @AppStorage("bgDim") private var bgDim = 0.35
    @AppStorage("bgBlur") private var bgBlur = 0.0
    @State private var pickedItem: PhotosPickerItem?
    @State private var confirmClear = false
    @State private var cleared = false
    @ObservedObject private var privacy = PrivacyStore.shared
    @AppStorage("quickLogin") private var quickLogin = true
    @AppStorage("quickAutoSubmit") private var quickAutoSubmit = true
    @AppStorage("blockTrackers") private var blockTrackers = true
    @State private var showVault = false
    @State private var vaultCount = Vault.all.count

    private var engine: SearchEngine { SearchEngine(rawValue: engineRaw) ?? .google }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [Color(hex: 0x4B2FB8, opacity: 0.30), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    searchGroup
                    homeGroup
                    backgroundGroup
                    securityGroup
                    quickLoginGroup
                    privacyGroup
                    aboutGroup
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: pickedItem) { item in
            guard let item = item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data = data {
                        bg.set(data: data)
                    } else {
                        bg.fail("No se pudo abrir la foto seleccionada.")
                    }
                    pickedItem = nil
                }
            }
        }
        .sheet(isPresented: $showVault, onDismiss: { vaultCount = Vault.all.count }) {
            SavedLoginsView()
        }
        .confirmationDialog("¿Borrar los datos de navegación?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { clearData() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán cookies, caché y almacenamiento de los sitios.")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            NovaMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuración")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text("Nova \(version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(NovaTheme.surfaceHi))
                    .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar")
        }
    }

    // MARK: Grupos

    private var searchGroup: some View {
        SettingsGroup("Buscador", footer: "Se usa al escribir texto en la barra de direcciones.") {
            ForEach(SearchEngine.allCases) { e in
                Button {
                    Haptics.select()
                    engineRaw = e.rawValue
                } label: {
                    HStack(spacing: 12) {
                        EngineBadge(engine: e, size: 34)
                        Text(e.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        if e == engine {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(NovaTheme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if e.id != SearchEngine.allCases.last?.id { RowDivider(inset: 60) }
            }
        }
    }

    private var homeGroup: some View {
        SettingsGroup("Inicio") {
            HStack(spacing: 12) {
                IconTile(symbol: "square.grid.2x2.fill", tint: NovaTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accesos rápidos")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Tus sitios favoritos bajo el buscador")
                        .font(.system(size: 12))
                        .foregroundColor(NovaTheme.dim)
                }
                Spacer()
                Toggle("", isOn: $showShortcuts)
                    .labelsHidden()
                    .tint(NovaTheme.accent)
            }
            .padding(14)
        }
    }

    private var backgroundGroup: some View {
        SettingsGroup("Fondo de inicio",
                      footer: "Admite fotos y GIFs animados. Los GIFs largos se optimizan para ahorrar memoria y batería.") {
            VStack(spacing: 14) {
                backgroundPreview

                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 14, weight: .semibold))
                            Text(bg.image == nil ? "Elegir foto o GIF" : "Cambiar fondo")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.accentGradient))
                    }

                    if bg.image != nil {
                        Button {
                            Haptics.tap()
                            bg.remove()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(NovaTheme.danger)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(NovaTheme.danger.opacity(0.14)))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Quitar fondo")
                    }
                }

                if let message = bg.errorMessage {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(NovaTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if bg.image != nil {
                    sliderRow(symbol: "circle.lefthalf.filled", title: "Oscurecer", value: $bgDim, range: 0...0.85)
                    sliderRow(symbol: "drop.fill", title: "Desenfoque", value: $bgBlur, range: 0...24)
                }
            }
            .padding(14)
        }
    }

    private var backgroundPreview: some View {
        ZStack {
            NovaBackground()
            HomeBackgroundView()
            if bg.isProcessing {
                ProgressView().tint(.white)
            } else if bg.image == nil {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .medium))
                    Text("Sin fondo personalizado")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(NovaTheme.dim)
            } else {
                Text("09:41")
                    .font(.system(size: 46, weight: .thin))
                    .foregroundColor(.white)
            }
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
    }

    private func sliderRow(symbol: String, title: String,
                           value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NovaTheme.accent2)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 84, alignment: .leading)
            Slider(value: value, in: range)
                .tint(NovaTheme.accent)
        }
    }

    // MARK: Seguridad (Face ID) y navegación privada

    private var lockAppBinding: Binding<Bool> {
        Binding(
            get: { privacy.lockApp },
            set: { on in
                // Se confirma con Face ID antes de cambiar el ajuste, para no quedarse bloqueado fuera.
                privacy.authenticate(reason: on ? "Confirma para activar el bloqueo de Nova"
                                                : "Confirma para desactivar el bloqueo de Nova") { ok in
                    if ok { privacy.lockApp = on }
                }
            }
        )
    }

    private var lockPrivateBinding: Binding<Bool> {
        Binding(
            get: { privacy.lockPrivate },
            set: { on in
                privacy.authenticate(reason: "Confirma para cambiar la protección de la navegación privada") { ok in
                    if ok { privacy.lockPrivate = on }
                }
            }
        )
    }

    private var securityGroup: some View {
        SettingsGroup("Seguridad y modo privado",
                      footer: "Con el bloqueo activo, Nova pide \(PrivacyStore.biometryName) al abrirla y al volver de segundo plano. El contenido se oculta en el selector de apps.") {
            toggleRow(symbol: "faceid", tint: NovaTheme.accent,
                      title: "Bloquear Nova con \(PrivacyStore.biometryName)",
                      detail: "Al abrir y al volver a la app",
                      isOn: lockAppBinding)
            RowDivider(inset: 60)
            toggleRow(symbol: "eye.slash.fill", tint: PrivateTheme.accent,
                      title: "Proteger navegación privada",
                      detail: "Pide \(PrivacyStore.biometryName) para abrir pestañas privadas",
                      isOn: lockPrivateBinding)
            RowDivider(inset: 60)
            toggleRow(symbol: "shield.lefthalf.filled", tint: NovaTheme.good,
                      title: "Bloquear rastreadores",
                      detail: "Anuncios y analíticas de terceros en pestañas privadas",
                      isOn: $blockTrackers)
        }
    }

    private var quickLoginGroup: some View {
        SettingsGroup("Inicio rápido",
                      footer: "Las contraseñas se guardan en el llavero del iPhone y solo se leen con \(PrivacyStore.biometryName). Las passkeys de los sitios no funcionan en Nova (iOS las reserva a apps con permiso especial de Apple), así que Nova usa tu contraseña con \(PrivacyStore.biometryName). No se guardan contraseñas en pestañas privadas.") {
            toggleRow(symbol: "key.fill", tint: NovaTheme.accent2,
                      title: "Guardar e iniciar sesión rápido",
                      detail: "Ofrece guardar y rellenar con \(PrivacyStore.biometryName)",
                      isOn: $quickLogin)
            RowDivider(inset: 60)
            toggleRow(symbol: "paperplane.fill", tint: NovaTheme.accent,
                      title: "Entrar automáticamente",
                      detail: "Pulsa «Iniciar sesión» tras rellenar",
                      isOn: $quickAutoSubmit)
            RowDivider(inset: 60)
            Button { showVault = true } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "list.bullet.rectangle.fill", tint: NovaTheme.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contraseñas guardadas")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(vaultCount == 1 ? "1 cuenta" : "\(vaultCount) cuentas")
                            .font(.system(size: 12))
                            .foregroundColor(NovaTheme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(NovaTheme.faint)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleRow(symbol: String, tint: Color, title: String, detail: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(14)
    }

    private var privacyGroup: some View {
        SettingsGroup("Privacidad") {
            Button { confirmClear = true } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: cleared ? "checkmark" : "trash.fill",
                             tint: cleared ? NovaTheme.good : NovaTheme.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Borrar datos de navegación")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(cleared ? "Datos eliminados" : "Cookies, caché y almacenamiento de sitios")
                            .font(.system(size: 12))
                            .foregroundColor(cleared ? NovaTheme.good : NovaTheme.dim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(NovaTheme.faint)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutGroup: some View {
        SettingsGroup("Acerca de", footer: "Los cambios se guardan en este dispositivo.") {
            infoRow(symbol: "moon.stars.fill", tint: NovaTheme.accent, title: "Apariencia", value: "Oscura")
            RowDivider(inset: 60)
            infoRow(symbol: "info.circle.fill", tint: NovaTheme.accent2, title: "Versión", value: version)
        }
    }

    private func infoRow(symbol: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(NovaTheme.dim)
        }
        .padding(14)
    }

    private func clearData() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async {
                cleared = true
                Haptics.success()
            }
        }
    }
}

// MARK: - Componentes

private struct SettingsGroup<Content: View>: View {
    let title: String
    let footer: String?
    let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(NovaTheme.dim)
                .padding(.horizontal, 6)
            VStack(spacing: 0) { content }
                .novaCard(radius: 18)
            if let footer = footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundColor(NovaTheme.faint)
                    .padding(.horizontal, 6)
            }
        }
    }
}

private struct RowDivider: View {
    var inset: CGFloat = 14
    var body: some View {
        Rectangle().fill(NovaTheme.stroke).frame(height: 1).padding(.leading, inset)
    }
}

private struct IconTile: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15)))
    }
}
