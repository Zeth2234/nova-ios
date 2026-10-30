import SwiftUI
import WebKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("engine") private var engineRaw = SearchEngine.google.rawValue
    @AppStorage("showShortcuts") private var showShortcuts = true
    @State private var confirmClear = false
    @State private var cleared = false

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
                    privacyGroup
                    aboutGroup
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
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
