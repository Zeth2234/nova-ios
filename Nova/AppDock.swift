import SwiftUI
import WebKit

// MARK: - Catálogo de apps reconocidas

struct DockAppInfo {
    let name: String
    let hosts: [String]
    let color: Color
    let glyph: String
}

enum AppCatalog {
    static let all: [DockAppInfo] = [
        DockAppInfo(name: "YouTube", hosts: ["youtube.com", "youtu.be"], color: Color(hex: 0xFF1F3D), glyph: "play.fill"),
        DockAppInfo(name: "Spotify", hosts: ["spotify.com"], color: Color(hex: 0x1DB954), glyph: "music.note"),
        DockAppInfo(name: "WhatsApp", hosts: ["whatsapp.com"], color: Color(hex: 0x25D366), glyph: "message.fill"),
        DockAppInfo(name: "Discord", hosts: ["discord.com"], color: Color(hex: 0x5865F2), glyph: "bubble.left.fill"),
        DockAppInfo(name: "X", hosts: ["x.com", "twitter.com"], color: Color(hex: 0x14171C), glyph: "xmark"),
        DockAppInfo(name: "Twitch", hosts: ["twitch.tv"], color: Color(hex: 0x9146FF), glyph: "tv.fill"),
        DockAppInfo(name: "SoundCloud", hosts: ["soundcloud.com"], color: Color(hex: 0xFF5500), glyph: "waveform")
    ]

    static func match(host: String) -> DockAppInfo? {
        let h = host.lowercased()
        return all.first { app in app.hosts.contains { h == $0 || h.hasSuffix("." + $0) } }
    }
}

// MARK: - Lógica del panel (máx. 4 apps en segundo plano)

extension BrowserModel {
    static let maxDockApps = 4

    /// Pestañas que cuentan como "app": sitios reconocidos o cualquier pestaña que esté sonando.
    /// Las pestañas privadas nunca aparecen aquí para no mostrar su actividad.
    var dockTabs: [BrowserTab] {
        tabs.filter { !$0.isPrivate && $0.hasPage && (AppCatalog.match(host: $0.host) != nil || $0.isPlayingAudio) }
    }

    /// Si hay más de 4, cierra la más antigua que no esté activa ni sonando.
    func enforceDockLimit() {
        let apps = dockTabs
        guard apps.count > Self.maxDockApps else { return }
        if let victim = apps.first(where: { $0.id != activeTabID && !$0.isPlayingAudio }) {
            closeTab(victim.id)
        }
    }

    func pollAudioState() {
        tabs.forEach { $0.pollAudio() }
        enforceDockLimit()
    }
}

extension BrowserTab {
    /// Detecta si la página reproduce audio (video/audio sin pausar ni silenciar).
    func pollAudio() {
        guard hasPage else { if isPlayingAudio { isPlayingAudio = false }; return }
        let js = """
        Array.from(document.querySelectorAll('video,audio')).some(m =>
            !m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState > 2);
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let playing = (result as? Bool) ?? false
                if playing != self.isPlayingAudio { self.isPlayingAudio = playing }
            }
        }
    }
}

// MARK: - Animación de ecualizador

struct EqualizerBars: View {
    var color: Color = NovaTheme.accent2
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.6, height: 4 + 7 * abs(sin(t * 3.4 + Double(i) * 1.35)))
                }
            }
            .frame(height: 11, alignment: .bottom)
        }
    }
}

// MARK: - Icono de una app

struct DockItemView: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    private var info: DockAppInfo? { AppCatalog.match(host: tab.host) }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                icon
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(isActive ? NovaTheme.accent : NovaTheme.stroke, lineWidth: isActive ? 1.6 : 1)
                    )
                    .shadow(color: isActive ? NovaTheme.accent.opacity(0.45) : .clear, radius: 7)

                badge.offset(x: 4, y: 4)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(isActive ? 1.0 : 0.94)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(role: .destructive, action: onClose) {
                Label("Cerrar \(info?.name ?? "app")", systemImage: "xmark.circle")
            }
        }
        .accessibilityLabel("\(info?.name ?? tab.host), \(tab.isPlayingAudio ? "reproduciendo" : "abierta")")
    }

    @ViewBuilder private var icon: some View {
        if let img = tab.faviconImage {
            Image(uiImage: img).resizable().scaledToFill().background(Color.white.opacity(0.06))
        } else {
            ZStack {
                (info?.color ?? NovaTheme.surfaceHi)
                Image(systemName: info?.glyph ?? "globe")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    /// Sonando → ecualizador animado. Abierta sin sonido → punto. (Cerrada → no aparece.)
    @ViewBuilder private var badge: some View {
        if tab.isPlayingAudio {
            EqualizerBars()
                .padding(.horizontal, 4).padding(.vertical, 3)
                .background(Capsule().fill(NovaTheme.bg))
                .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .fill(isActive ? NovaTheme.accent : NovaTheme.good)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(NovaTheme.bg, lineWidth: 2))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Panel flotante

struct AppDockView: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        let apps = Array(model.dockTabs.prefix(BrowserModel.maxDockApps))
        if !apps.isEmpty {
            HStack(spacing: 6) {
                ForEach(apps) { tab in
                    DockItemView(tab: tab,
                                 isActive: tab.id == model.activeTabID && !model.isHome,
                                 onTap: { model.selectTab(tab.id) },
                                 onClose: { model.closeTab(tab.id) })
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(NovaTheme.surface.opacity(0.78)))
            )
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: apps.map { $0.id })
            .padding(.bottom, 10)
        }
    }
}
