import SwiftUI
import UIKit

// Interfaz del panel de apps: panel lateral, reproductor, mini reproductor y asa del borde.

// MARK: - Utilidades

/// Observa una pestaña concreta (sonido, portada, no leídos…) aunque no sea la activa.
struct TabObserving<Content: View>: View {
    @ObservedObject var tab: BrowserTab
    @ViewBuilder let content: (BrowserTab) -> Content
    var body: some View { content(tab) }
}

private func timeText(_ s: Double) -> String {
    guard s.isFinite, s >= 0 else { return "0:00" }
    let t = Int(s.rounded(.down))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60)
                     : String(format: "%d:%02d", t / 60, t % 60)
}

/// Ecualizador animado (3 barras).
struct EqualizerBars: View {
    var color: Color = NovaTheme.accent2
    var height: CGFloat = 11
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: height * 0.36 + height * 0.64 * abs(sin(t * 3.4 + Double(i) * 1.35)))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}

// MARK: - Icono de app

struct PanelAppIcon: View {
    let app: PanelApp
    var favicon: UIImage?
    var size: CGFloat = 46

    private var image: UIImage? { favicon ?? app.iconPNG.flatMap { UIImage(data: $0) } }

    var body: some View {
        ZStack {
            if let img = image {
                NovaTheme.surfaceHi
                if img.size.width >= 96 {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(uiImage: img).resizable().interpolation(.high).scaledToFit().padding(size * 0.18)
                }
            } else {
                LinearGradient(colors: [app.tint, app.tint.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: app.glyph)
                    .font(.system(size: size * 0.40, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
    }
}

/// Insignia roja de no leídos.
struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Color(hex: 0xFF3B4E)))
            .overlay(Capsule().stroke(NovaTheme.surface, lineWidth: 2))
    }
}

/// Estado de una entrada leído de su pestaña (o «sin abrir»).
struct SlotState {
    var running = false
    var playing = false
    var muted = false
    var unread = 0
    var favicon: UIImage?
    var nowPlaying: NowPlaying?

    static let idle = SlotState()
    init() {}
    init(_ t: BrowserTab) {
        running = true
        playing = t.isPlayingAudio
        muted = t.isMuted
        unread = t.unreadCount
        favicon = t.faviconImage
        nowPlaying = t.nowPlaying
    }
}

// MARK: - Panel lateral

struct AppSidePanel: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = PanelStore.shared
    @AppStorage("panelExpanded") private var expanded = true
    @State private var dragX: CGFloat = 0
    @State private var showManager = false

    private var width: CGFloat { expanded ? 318 : 86 }

    var body: some View {
        let entries = model.panelEntries()
        let runningCount = model.panelTabs.count

        VStack(spacing: 0) {
            header(runningCount: runningCount)
                .padding(.horizontal, expanded ? 16 : 0)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if expanded, let tab = model.nowPlayingTab {
                NowPlayingCard(tab: tab, app: PanelStore.shared.resolve(tab), onOpen: { open(tab: tab, app: nil) })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            Rectangle().fill(NovaTheme.stroke).frame(height: 1).padding(.horizontal, expanded ? 16 : 18)

            ScrollView(showsIndicators: false) {
                VStack(spacing: expanded ? 4 : 10) {
                    if expanded { sectionTitle("Ancladas") }
                    ForEach(entries.pinned) { entry in item(entry) }

                    if entries.pinned.isEmpty {
                        Text(expanded ? "No hay apps ancladas.\nAñade tus favoritas con «+»." : "Vacío")
                            .font(.system(size: 12))
                            .foregroundColor(NovaTheme.faint)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 14)
                    }

                    if !entries.others.isEmpty {
                        if expanded {
                            sectionTitle("Otras abiertas")
                        } else {
                            Rectangle().fill(NovaTheme.stroke).frame(width: 30, height: 1).padding(.vertical, 2)
                        }
                        ForEach(entries.others) { entry in item(entry) }
                    }
                }
                .padding(.horizontal, expanded ? 10 : 0)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(panelBackground)
        .overlay(panelBorder)
        .shadow(color: NovaTheme.shadow(0.45), radius: 24, x: 6, y: 8)
        .padding(.leading, 8)
        .padding(.vertical, 8)
        .offset(x: min(0, dragX))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in dragX = min(0, v.translation.width) }
                .onEnded { v in
                    if v.translation.width < -70 || v.predictedEndTranslation.width < -160 {
                        store.setOpen(false)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragX = 0 }
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: entries.pinned.map { $0.id + ($0.tab == nil ? "" : "•") })
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: entries.others.map { $0.id })
        .sheet(isPresented: $showManager) {
            PanelManagerView(currentTab: (!model.isHome && !model.activeTab.isPrivate) ? model.activeTab : nil,
                             runningCount: runningCount)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(NovaTheme.surface.opacity(0.86))
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(RadialGradient(colors: [NovaTheme.accent.opacity(0.16), .clear],
                                     center: .topLeading, startRadius: 0, endRadius: 260))
        }
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(LinearGradient(colors: [NovaTheme.ink(0.18), NovaTheme.ink(0.04)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }

    // MARK: Cabecera y pie

    @ViewBuilder private func header(runningCount: Int) -> some View {
        if expanded {
            HStack(spacing: 10) {
                NovaMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apps")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(NovaTheme.text)
                    HStack(spacing: 5) {
                        CapacityDots(used: runningCount)
                        Text("\(min(runningCount, PanelStore.maxRunning)) de \(PanelStore.maxRunning) abiertas")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(NovaTheme.dim)
                    }
                }
                Spacer()
                circleButton("sidebar.left", label: "Panel compacto") { expanded = false }
                circleButton("xmark", label: "Cerrar panel") { store.setOpen(false) }
            }
        } else {
            VStack(spacing: 10) {
                NovaMark(size: 28)
                CapacityDots(used: runningCount)
                circleButton("sidebar.right", label: "Ampliar panel") { expanded = true }
            }
        }
    }

    private var footer: some View {
        Group {
            if expanded {
                HStack(spacing: 8) {
                    footerButton("plus", title: "Añadir") { showManager = true }
                    footerButton("slider.horizontal.3", title: "Personalizar") { showManager = true }
                }
                .padding(.horizontal, 12)
            } else {
                VStack(spacing: 8) {
                    circleButton("plus", label: "Añadir apps") { showManager = true }
                    circleButton("slider.horizontal.3", label: "Personalizar panel") { showManager = true }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(NovaTheme.stroke).frame(height: 1).padding(.horizontal, expanded ? 16 : 18)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(NovaTheme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(NovaTheme.ink(0.8))
                .frame(width: 34, height: 34)
                .background(Circle().fill(NovaTheme.ink(0.07)))
                .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private func footerButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(NovaTheme.ink(0.85))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.ink(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Entradas

    @ViewBuilder private func item(_ entry: PanelEntry) -> some View {
        if let tab = entry.tab {
            TabObserving(tab: tab) { t in
                PanelItemView(entry: entry, state: SlotState(t), tab: t,
                              isActive: t.id == model.activeTabID && !model.isHome,
                              expanded: expanded, model: model,
                              onOpen: { open(tab: t, app: entry.app) })
            }
        } else {
            PanelItemView(entry: entry, state: .idle, tab: nil, isActive: false,
                          expanded: expanded, model: model,
                          onOpen: { open(tab: nil, app: entry.app) })
        }
    }

    private func open(tab: BrowserTab?, app: PanelApp?) {
        Haptics.tap()
        if let tab = tab {
            model.focusPanelTab(tab)
        } else if let app = app {
            model.openPanelApp(app)
        }
        store.setOpen(false)
    }
}

/// Puntos de capacidad: 4 huecos, se llenan con las apps abiertas.
struct CapacityDots: View {
    let used: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<PanelStore.maxRunning, id: \.self) { i in
                Capsule()
                    .fill(i < used ? AnyShapeStyle(NovaTheme.accentGradient) : AnyShapeStyle(NovaTheme.ink(0.14)))
                    .frame(width: 8, height: 4)
            }
        }
        .accessibilityLabel("\(used) de \(PanelStore.maxRunning) apps abiertas")
    }
}

// MARK: - Elemento del panel

struct PanelItemView: View {
    let entry: PanelEntry
    let state: SlotState
    let tab: BrowserTab?
    let isActive: Bool
    let expanded: Bool
    let model: BrowserModel
    let onOpen: () -> Void

    @AppStorage("panelBadges") private var showBadges = true

    private var app: PanelApp { entry.app }
    private var unread: Int { showBadges ? state.unread : 0 }

    var body: some View {
        Button(action: onOpen) {
            if expanded { row } else { tile }
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu }
        .accessibilityLabel(accessibility)
    }

    // Compacto: icono + nombre.
    private var tile: some View {
        VStack(spacing: 4) {
            ZStack {
                iconWithIndicators(size: 48)
            }
            .frame(width: 66, height: 54)
            .overlay(alignment: .leading) { runningMark }
            Text(app.name)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(state.running ? NovaTheme.ink(0.85) : NovaTheme.dim)
                .lineLimit(1)
                .frame(width: 70)
        }
    }

    // Ampliado: icono + nombre + estado + acciones.
    private var row: some View {
        HStack(spacing: 12) {
            iconWithIndicators(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(NovaTheme.text)
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isActive ? NovaTheme.accent.opacity(0.13) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? NovaTheme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func iconWithIndicators(size: CGFloat) -> some View {
        PanelAppIcon(app: app, favicon: state.favicon, size: size)
            .saturation(state.running ? 1 : 0.85)
            .opacity(state.running ? 1 : 0.82)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .stroke(isActive ? NovaTheme.accent : Color.clear, lineWidth: 2)
                    .padding(-3)
            )
            .shadow(color: isActive ? NovaTheme.accent.opacity(0.5) : .clear, radius: 8)
            .overlay(alignment: .topTrailing) {
                if unread > 0 { UnreadBadge(count: unread).offset(x: 7, y: -7).transition(.scale) }
            }
            .overlay(alignment: .bottomTrailing) {
                if state.playing {
                    EqualizerBars(height: 10)
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .background(Capsule().fill(NovaTheme.surface))
                        .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
                        .offset(x: 6, y: 5)
                        .transition(.scale.combined(with: .opacity))
                } else if state.muted && state.nowPlaying != nil {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(NovaTheme.dim)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(NovaTheme.surface))
                        .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
                        .offset(x: 6, y: 5)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.playing)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: unread)
    }

    /// Marca a la izquierda (como el Dock del Mac): larga = en pantalla, corta = abierta.
    @ViewBuilder private var runningMark: some View {
        if state.running {
            Capsule()
                .fill(isActive ? AnyShapeStyle(NovaTheme.accentGradient) : AnyShapeStyle(NovaTheme.ink(0.55)))
                .frame(width: 3.5, height: isActive ? 22 : 7)
                .offset(x: -1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let np = state.nowPlaying, state.playing || np.paused {
            HStack(spacing: 5) {
                if state.playing { EqualizerBars(color: app.color == 0x14171C || app.color == 0x111317 ? NovaTheme.accent2 : app.tint, height: 9) }
                else { Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold)).foregroundColor(NovaTheme.dim) }
                Text(np.artist.isEmpty ? np.title : "\(np.title) · \(np.artist)")
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundColor(state.playing ? NovaTheme.ink(0.8) : NovaTheme.dim)
        } else if unread > 0 {
            Text(unread == 1 ? "1 mensaje sin leer" : "\(unread) sin leer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0xFF3B4E))
        } else if state.running {
            HStack(spacing: 5) {
                Circle().fill(isActive ? NovaTheme.accent : NovaTheme.good).frame(width: 6, height: 6)
                Text(isActive ? "En pantalla" : "Abierta en segundo plano")
            }
            .font(.system(size: 12))
            .foregroundColor(NovaTheme.dim)
        } else {
            Text(entry.pinned ? "Toca para abrir" : app.hosts.first ?? "")
                .font(.system(size: 12))
                .foregroundColor(NovaTheme.faint)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let tab = tab, let np = state.nowPlaying {
            Button {
                Haptics.tap()
                tab.mediaCommand(.toggle)
            } label: {
                Image(systemName: np.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(NovaTheme.accentGradient))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(np.paused ? "Reanudar" : "Pausar")
        } else if let tab = tab {
            Button {
                Haptics.tap()
                withAnimation { model.closeTab(tab.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(NovaTheme.ink(0.07)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar \(app.name)")
        } else {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NovaTheme.faint)
        }
    }

    @ViewBuilder private var menu: some View {
        Button(action: onOpen) {
            Label(state.running ? "Ir a \(app.name)" : "Abrir \(app.name)", systemImage: "arrow.up.forward.app")
        }
        if let tab = tab {
            if let np = state.nowPlaying {
                Button { tab.mediaCommand(.toggle) } label: {
                    Label(np.paused ? "Reanudar" : "Pausar", systemImage: np.paused ? "play.fill" : "pause.fill")
                }
                Button { tab.mediaCommand(.next) } label: { Label("Siguiente", systemImage: "forward.fill") }
            }
            Button { tab.mediaCommand(.mute(!state.muted)) } label: {
                Label(state.muted ? "Activar sonido" : "Silenciar",
                      systemImage: state.muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            Button { tab.webView.reload() } label: { Label("Recargar", systemImage: "arrow.clockwise") }
            Button { tab.setDesktop(!tab.desktopMode) } label: {
                Label(tab.desktopMode ? "Versión móvil" : "Versión de ordenador",
                      systemImage: tab.desktopMode ? "iphone" : "desktopcomputer")
            }
        }
        Divider()
        if entry.pinned {
            Button { PanelStore.shared.unpin(app.id) } label: { Label("Quitar del panel", systemImage: "pin.slash") }
        } else {
            Button {
                var pinnedApp = app
                if pinnedApp.iconPNG == nil, let img = state.favicon { pinnedApp.iconPNG = img.panelIconPNG() }
                PanelStore.shared.pin(pinnedApp)
            } label: { Label("Anclar al panel", systemImage: "pin") }
        }
        if let tab = tab {
            Button(role: .destructive) { model.closeTab(tab.id) } label: {
                Label("Cerrar \(app.name)", systemImage: "xmark.circle")
            }
        }
    }

    private var accessibility: String {
        var parts = [app.name]
        if state.playing { parts.append("reproduciendo") }
        else if state.running { parts.append("abierta") }
        if unread > 0 { parts.append("\(unread) sin leer") }
        if isActive { parts.append("en pantalla") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Reproductor

struct NowPlayingArtwork: View {
    let np: NowPlaying?
    let app: PanelApp?
    let favicon: UIImage?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let url = np?.artwork {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: NovaTheme.shadow(0.3), radius: 6, y: 3)
    }

    @ViewBuilder private var fallback: some View {
        if let app = app {
            PanelAppIcon(app: app, favicon: favicon, size: size)
        } else {
            ZStack {
                NovaTheme.surfaceHi
                Image(systemName: "music.note").font(.system(size: size * 0.4, weight: .bold)).foregroundColor(NovaTheme.dim)
            }
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var tab: BrowserTab
    let app: PanelApp?
    let onOpen: () -> Void

    var body: some View {
        if let np = tab.nowPlaying {
            VStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 12) {
                        NowPlayingArtwork(np: np, app: app, favicon: tab.faviconImage, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if tab.isPlayingAudio { EqualizerBars(color: NovaTheme.accent2, height: 8) }
                                Text((app?.name ?? tab.host).uppercased())
                                    .font(.system(size: 9.5, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundColor(NovaTheme.accent)
                                    .lineLimit(1)
                            }
                            Text(np.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(NovaTheme.text)
                                .lineLimit(2)
                            if !np.artist.isEmpty {
                                Text(np.artist)
                                    .font(.system(size: 12))
                                    .foregroundColor(NovaTheme.dim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if np.duration > 0 { ProgressLine(np: np) }

                HStack {
                    controlButton(tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 13, label: tab.isMuted ? "Activar sonido" : "Silenciar") {
                        tab.mediaCommand(.mute(!tab.isMuted))
                    }
                    Spacer()
                    controlButton("backward.fill", size: 17, label: "Anterior") { tab.mediaCommand(.previous) }
                    Spacer()
                    Button {
                        Haptics.tap()
                        tab.mediaCommand(.toggle)
                    } label: {
                        Image(systemName: np.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(NovaTheme.accentGradient))
                            .shadow(color: NovaTheme.accent.opacity(0.45), radius: 8, y: 3)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(np.paused ? "Reanudar" : "Pausar")
                    Spacer()
                    controlButton("forward.fill", size: 17, label: "Siguiente") { tab.mediaCommand(.next) }
                    Spacer()
                    controlButton("arrow.up.forward.app", size: 14, label: "Abrir") { onOpen() }
                }
                .padding(.horizontal, 4)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.ink(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(NovaTheme.ink(0.85))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Barra de progreso que avanza sola entre lecturas.
struct ProgressLine: View {
    let np: NowPlaying
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let pos = np.position(at: ctx.date)
            let frac = np.duration > 0 ? min(1, max(0, pos / np.duration)) : 0
            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaTheme.ink(0.12))
                        Capsule().fill(NovaTheme.accentGradient).frame(width: max(4, g.size.width * frac))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(timeText(pos))
                    Spacer()
                    Text("-" + timeText(max(0, np.duration - pos)))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundColor(NovaTheme.faint)
            }
        }
    }
}

// MARK: - Mini reproductor flotante + avisos

struct PanelBottomOverlay: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = PanelStore.shared
    @AppStorage("panelMiniPlayer") private var miniPlayer = true

    var body: some View {
        VStack(spacing: 8) {
            if let text = store.notice {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill").foregroundColor(NovaTheme.accent)
                    Text(text).foregroundColor(NovaTheme.text).lineLimit(2)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .novaGlass(radius: 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if miniPlayer, !store.isOpen, !model.isPrivate, let tab = model.nowPlayingTab,
               !(tab.id == model.activeTabID && !model.isHome) {
                MiniPlayer(tab: tab, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: store.notice)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: model.nowPlayingTab?.id)
    }
}

struct MiniPlayer: View {
    @ObservedObject var tab: BrowserTab
    let model: BrowserModel
    @ObservedObject private var store = PanelStore.shared
    @State private var dragY: CGFloat = 0

    var body: some View {
        if let np = tab.nowPlaying, store.hiddenPlayerKey != tab.id.uuidString + np.trackKey {
            let app = store.resolve(tab)
            HStack(spacing: 11) {
                NowPlayingArtwork(np: np, app: app, favicon: tab.faviconImage, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(NovaTheme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if tab.isPlayingAudio { EqualizerBars(height: 8) }
                        Text(np.artist.isEmpty ? (app?.name ?? tab.host) : np.artist)
                            .font(.system(size: 11.5))
                            .foregroundColor(NovaTheme.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                button(np.paused ? "play.fill" : "pause.fill", size: 17, label: np.paused ? "Reanudar" : "Pausar") { tab.mediaCommand(.toggle) }
                button("forward.fill", size: 15, label: "Siguiente") { tab.mediaCommand(.next) }
                button("xmark", size: 11, label: "Ocultar reproductor") {
                    withAnimation { store.hiddenPlayerKey = tab.id.uuidString + np.trackKey }
                }
            }
            .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 8)
            .novaGlass(radius: 20)
            .overlay(alignment: .bottom) {
                if np.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        GeometryReader { g in
                            Capsule().fill(NovaTheme.accentGradient)
                                .frame(width: g.size.width * min(1, max(0, np.position(at: ctx.date) / np.duration)), height: 2)
                        }
                        .frame(height: 2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                model.focusPanelTab(tab)
            }
            .offset(y: max(0, dragY))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { dragY = $0.translation.height }
                    .onEnded { v in
                        if v.translation.height > 50 {
                            withAnimation { store.hiddenPlayerKey = tab.id.uuidString + np.trackKey }
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragY = 0 }
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Reproduciendo \(np.title)")
        }
    }

    private func button(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundColor(NovaTheme.ink(0.9))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Asa del borde izquierdo

struct PanelEdgeHandle: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var store = PanelStore.shared
    @AppStorage("panelHandle") private var showHandle = true

    var body: some View {
        if showHandle && !store.isOpen && !model.isPrivate {
            let tabs = model.panelTabs
            let playing = tabs.contains { $0.isPlayingAudio }
            let unread = tabs.reduce(0) { $0 + $1.unreadCount }
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .fill(NovaTheme.accentGradient)
                    .frame(width: 5, height: 58)
                    .shadow(color: NovaTheme.accent.opacity(0.6), radius: playing ? 8 : 4)
                    .opacity(0.9)
                if playing || unread > 0 {
                    Circle()
                        .fill(unread > 0 ? Color(hex: 0xFF3B4E) : NovaTheme.good)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(NovaTheme.bg, lineWidth: 1.5))
                        .offset(x: 5, y: -4)
                }
            }
            .frame(width: 26, height: 96)
            .contentShape(Rectangle())
            .onTapGesture { store.setOpen(true) }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onEnded { v in if v.translation.width > 20 { store.setOpen(true) } }
            )
            .accessibilityLabel("Abrir panel de apps")
            .accessibilityAddTraits(.isButton)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}
