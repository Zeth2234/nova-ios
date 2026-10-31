import SwiftUI
import UIKit

// Personalizar el panel de apps: ancladas (reordenar / quitar), catálogo, sitio actual,
// dirección propia y opciones. Se abre desde el panel o desde Configuración.

struct PanelManagerView: View {
    /// Pestaña que se está viendo (para «Añadir este sitio»). nil desde Configuración.
    var currentTab: BrowserTab?
    var runningCount: Int = 0

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PanelStore.shared
    @AppStorage("panelHandle") private var showHandle = true
    @AppStorage("panelMiniPlayer") private var miniPlayer = true
    @AppStorage("panelBadges") private var badges = true
    @AppStorage("panelExclusiveAudio") private var exclusiveAudio = false
    @AppStorage("panelExpanded") private var expanded = true
    @State private var editMode: EditMode = .inactive
    @State private var customURL = ""
    @State private var customName = ""
    @State private var customError = false

    private var available: [PanelApp] { AppCatalog.all.filter { !store.isPinned($0.id) } }

    /// Sitio que se está viendo, si no está ya anclado.
    private var currentCandidate: PanelApp? {
        guard let tab = currentTab, tab.hasPage else { return nil }
        let host = tab.host
        if AppCatalog.best(in: store.pinned, host: host) != nil { return nil }
        var app = AppCatalog.match(host: host) ?? PanelApp.adHoc(host: host, url: tab.currentURL)
        if store.isPinned(app.id) { return nil }
        if app.isCustom {
            let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title.count <= 22, title != host { app.name = title }
        }
        if app.iconPNG == nil { app.iconPNG = tab.faviconImage?.panelIconPNG() }
        return app
    }

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [Color.nova(light: Color(hex: 0x8D7CFF, opacity: 0.18), dark: Color(hex: 0x4B2FB8, opacity: 0.30)), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 6)

                List {
                    summarySection
                    pinnedSection
                    if let app = currentCandidate { currentSection(app) }
                    catalogSection
                    customSection
                    optionsSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
            }
        }
        .novaAppearance()
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accentGradient)
                Image(systemName: "sidebar.left").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Panel de apps")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(NovaTheme.text)
                Text("\(store.pinned.count) ancladas · \(min(runningCount, PanelStore.maxRunning)) de \(PanelStore.maxRunning) abiertas")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()
            Button {
                Haptics.tap()
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            } label: {
                Text(editMode.isEditing ? "Listo" : "Ordenar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(NovaTheme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(NovaTheme.accent.opacity(0.12)))
            }
            .buttonStyle(PressableStyle())
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(NovaTheme.surfaceHi))
                    .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar")
        }
    }

    // MARK: Secciones

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                featureTile("sidebar.left", "Panel lateral", "Desliza desde el asa o pulsa «⋯ › Panel de apps»")
            }
            HStack(spacing: 14) {
                featureTile("play.circle.fill", "Reproductor", "Pausa, siguiente y silencio sin cambiar de app")
            }
            HStack(spacing: 14) {
                featureTile("bell.badge.fill", "No leídos", "WhatsApp, Discord, Gmail… muestran su contador")
            }
        } footer: {
            Text("Hasta \(PanelStore.maxRunning) apps abiertas a la vez. Si abres otra, la que lleve más tiempo sin usarse se suspende (nunca la que estás viendo ni la que suena) y vuelve a cargarse al tocarla.")
        }
        .listRowBackground(NovaTheme.surface)
    }

    private func featureTile(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(NovaTheme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NovaTheme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                Text(detail).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
            }
        }
        .padding(.vertical, 2)
    }

    private var pinnedSection: some View {
        Section {
            if store.pinned.isEmpty {
                Text("No hay apps ancladas. Añade alguna del catálogo de abajo.")
                    .font(.system(size: 13))
                    .foregroundColor(NovaTheme.dim)
            }
            ForEach(store.pinned) { app in
                HStack(spacing: 12) {
                    PanelAppIcon(app: app, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                        Text(app.hosts.first ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(NovaTheme.dim)
                    }
                    Spacer()
                    if app.desktop {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(NovaTheme.faint)
                            .accessibilityLabel("Se abre en versión de ordenador")
                    }
                    if !editMode.isEditing {
                        Button {
                            Haptics.tap()
                            withAnimation { store.unpin(app.id) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(NovaTheme.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Quitar \(app.name)")
                    }
                }
                .padding(.vertical, 2)
            }
            .onMove { store.move(from: $0, to: $1) }
            .onDelete { store.remove(at: $0) }
        } header: {
            Text("Ancladas")
        } footer: {
            Text("Pulsa «Ordenar» y arrastra para cambiar el orden del panel.")
        }
        .listRowBackground(NovaTheme.surface)
    }

    private func currentSection(_ app: PanelApp) -> some View {
        Section {
            Button {
                withAnimation { store.pin(app) }
            } label: {
                HStack(spacing: 12) {
                    PanelAppIcon(app: app, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Añadir «\(app.name)»").font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                        Text(app.hosts.first ?? "").font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundColor(NovaTheme.accent)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Sitio actual")
        }
        .listRowBackground(NovaTheme.surface)
    }

    private var catalogSection: some View {
        Section {
            if available.isEmpty {
                Text("Ya tienes todas las apps del catálogo.")
                    .font(.system(size: 13))
                    .foregroundColor(NovaTheme.dim)
            }
            ForEach(available) { app in
                Button {
                    withAnimation { store.pin(app) }
                } label: {
                    HStack(spacing: 12) {
                        PanelAppIcon(app: app, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                            Text(app.hosts.first ?? "").font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundColor(NovaTheme.good)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Catálogo")
        }
        .listRowBackground(NovaTheme.surface)
    }

    private var customSection: some View {
        Section {
            TextField("Dirección (p. ej. web.telegram.org)", text: $customURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(NovaTheme.text)
            TextField("Nombre (opcional)", text: $customName)
                .foregroundColor(NovaTheme.text)
            Button {
                if let app = PanelStore.custom(from: customURL, name: customName), !store.isPinned(app.id) {
                    withAnimation { store.pin(app) }
                    customURL = ""
                    customName = ""
                    customError = false
                } else {
                    customError = true
                }
            } label: {
                Label("Añadir al panel", systemImage: "plus.app.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(customURL.isEmpty ? NovaTheme.faint : NovaTheme.accent)
            }
            .disabled(customURL.isEmpty)
        } header: {
            Text("Otra web")
        } footer: {
            if customError {
                Text("Escribe una dirección válida que no esté ya en el panel.").foregroundColor(NovaTheme.danger)
            } else {
                Text("Cualquier web puede vivir en el panel como si fuera una app.")
            }
        }
        .listRowBackground(NovaTheme.surface)
    }

    private var optionsSection: some View {
        Section {
            optionRow("hand.draw.fill", NovaTheme.accent, "Asa en el borde", "Toca o desliza el borde izquierdo para abrir", $showHandle)
            optionRow("sidebar.squares.left", NovaTheme.accent2, "Panel ampliado", "Nombres, estado y reproductor completo", $expanded)
            optionRow("play.rectangle.on.rectangle.fill", NovaTheme.good, "Mini reproductor", "Controla la música desde cualquier pestaña", $miniPlayer)
            optionRow("bell.badge.fill", NovaTheme.danger, "Contadores de no leídos", "Insignias rojas en las apps", $badges)
            optionRow("speaker.wave.2.fill", NovaTheme.warn, "Solo una app con sonido", "Al sonar una, se pausan las demás", $exclusiveAudio)
        } header: {
            Text("Opciones")
        }
        .listRowBackground(NovaTheme.surface)
    }

    private func optionRow(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
                    Text(detail).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                }
            }
        }
        .tint(tint)
        .padding(.vertical, 2)
    }
}
