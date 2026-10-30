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
            RadialGradient(colors: [Color(hex: 0x4B2FB8, opacity: 0.35), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    hero
                    summaryCards
                    searchSection
                    homeSection
                    privacySection
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 30)
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

    // MARK: Secciones

    private var header: some View {
        HStack(spacing: 12) {
            NovaMark(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("NOVA BROWSER")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(NovaTheme.dim)
                Text("Configuración")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("Nova \(version)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(NovaTheme.surface))
                .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(NovaTheme.surface))
                    .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Todo en orden.")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text("Consulta y personaliza tu experiencia en Nova.")
                .font(.system(size: 14))
                .foregroundColor(NovaTheme.dim)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 10) {
            SummaryCard(symbol: "moon.stars.fill", tint: NovaTheme.accent,
                        label: "APARIENCIA", value: "Oscura", caption: "Interfaz actual")
            SummaryCard(symbol: "magnifyingglass", tint: NovaTheme.accent2,
                        label: "BUSCADOR", value: engine.name, caption: "Motor activo")
            SummaryCard(symbol: "checkmark", tint: NovaTheme.good,
                        label: "INICIO", value: showShortcuts ? "Accesos" : "Limpio",
                        caption: showShortcuts ? "Activados" : "Sin accesos")
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("BUSCADOR PREDETERMINADO")
            VStack(spacing: 0) {
                ForEach(SearchEngine.allCases) { e in
                    Button { engineRaw = e.rawValue } label: {
                        HStack(spacing: 12) {
                            EngineBadge(engine: e, size: 32)
                            Text(e.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            if e == engine {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(NovaTheme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if e.id != SearchEngine.allCases.last?.id {
                        Rectangle().fill(NovaTheme.stroke).frame(height: 1).padding(.leading, 58)
                    }
                }
            }
            .novaCard()
        }
    }

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("PANTALLA DE INICIO")
            HStack(spacing: 12) {
                IconTile(symbol: "square.grid.2x2", tint: NovaTheme.accent)
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
            .novaCard()
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("PRIVACIDAD")
            Button { confirmClear = true } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "trash", tint: Color(hex: 0xFF5C7A))
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
                        .foregroundColor(NovaTheme.dim)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .novaCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundColor(NovaTheme.accent)
            Text("Los cambios guardados se conservan en este dispositivo.")
                .font(.system(size: 12))
                .foregroundColor(NovaTheme.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .novaCard(radius: 14)
    }

    private func clearData() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async { cleared = true }
        }
    }
}

// MARK: - Componentes

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundColor(NovaTheme.accent2.opacity(0.9))
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

private struct SummaryCard: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconTile(symbol: symbol, tint: tint)
            Spacer(minLength: 14)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(NovaTheme.dim)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            Text(caption)
                .font(.system(size: 10))
                .foregroundColor(NovaTheme.dim)
                .lineLimit(1)
                .padding(.top, 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .novaCard()
    }
}
