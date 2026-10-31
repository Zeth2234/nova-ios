import SwiftUI
import WebKit
import UIKit

// ════════════════════════════════════════════════════════════════════════════════════
//  PANEL DE APPS DE NOVA (iOS)
//  · Panel lateral deslizable (compacto o ampliado) con apps ancladas, como en Nova Windows.
//  · Hasta 4 apps abiertas a la vez en segundo plano; la que lleve más tiempo sin usarse
//    se suspende (nunca la que estás viendo ni la que suena).
//  · Reproductor integrado (portada, título, artista, progreso, anterior / pausa / siguiente,
//    silenciar), contadores de no leídos, mini reproductor flotante y asa en el borde.
//  · Personalización: anclar / quitar / reordenar, catálogo de apps, sitio actual o dirección propia.
//  Interfaz: AppPanelViews.swift · Personalizar: AppPanelManager.swift
// ════════════════════════════════════════════════════════════════════════════════════

// MARK: - App del panel

struct PanelApp: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var hosts: [String]
    var color: UInt32
    var glyph: String
    var desktop: Bool
    var iconPNG: Data?

    init(id: String, name: String, url: String, hosts: [String], color: UInt32, glyph: String,
         desktop: Bool = false, iconPNG: Data? = nil) {
        self.id = id; self.name = name; self.url = url; self.hosts = hosts
        self.color = color; self.glyph = glyph; self.desktop = desktop; self.iconPNG = iconPNG
    }

    var tint: Color { Color(hex: color) }
    var isCustom: Bool { id.hasPrefix("web:") }

    static func cleanHost(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// 0 = no coincide. Si coincide, longitud del dominio (el más concreto gana: music.youtube.com > youtube.com).
    func matchScore(host: String) -> Int {
        let h = PanelApp.cleanHost(host)
        guard !h.isEmpty else { return 0 }
        var best = 0
        for d in hosts where h == d || h.hasSuffix("." + d) { best = max(best, d.count) }
        return best
    }

    /// App improvisada para una web que no está en el catálogo (p. ej. una pestaña que suena).
    static func adHoc(host: String, url: URL?) -> PanelApp {
        let h = cleanHost(host)
        let base = h.split(separator: ".").first.map(String.init) ?? h
        let name = base.isEmpty ? "Web" : base.prefix(1).uppercased() + base.dropFirst()
        return PanelApp(id: "web:" + h, name: name, url: url?.absoluteString ?? "https://" + h,
                        hosts: [h], color: 0x6A55E6, glyph: "globe")
    }
}

// MARK: - Catálogo

enum AppCatalog {
    static let all: [PanelApp] = [
        PanelApp(id: "youtube", name: "YouTube", url: "https://m.youtube.com", hosts: ["youtube.com", "youtu.be"], color: 0xFF1F3D, glyph: "play.rectangle.fill"),
        PanelApp(id: "ytmusic", name: "YouTube Music", url: "https://music.youtube.com", hosts: ["music.youtube.com"], color: 0xE0102E, glyph: "music.note.list"),
        PanelApp(id: "spotify", name: "Spotify", url: "https://open.spotify.com", hosts: ["spotify.com"], color: 0x1DB954, glyph: "music.note", desktop: true),
        PanelApp(id: "soundcloud", name: "SoundCloud", url: "https://m.soundcloud.com", hosts: ["soundcloud.com"], color: 0xFF5500, glyph: "waveform"),
        PanelApp(id: "applemusic", name: "Apple Music", url: "https://music.apple.com", hosts: ["music.apple.com"], color: 0xFA2D48, glyph: "music.quarternote.3"),
        PanelApp(id: "whatsapp", name: "WhatsApp", url: "https://web.whatsapp.com", hosts: ["whatsapp.com"], color: 0x25D366, glyph: "message.fill", desktop: true),
        PanelApp(id: "telegram", name: "Telegram", url: "https://web.telegram.org/k/", hosts: ["telegram.org"], color: 0x2AABEE, glyph: "paperplane.fill"),
        PanelApp(id: "discord", name: "Discord", url: "https://discord.com/app", hosts: ["discord.com"], color: 0x5865F2, glyph: "bubble.left.and.bubble.right.fill", desktop: true),
        PanelApp(id: "instagram", name: "Instagram", url: "https://www.instagram.com", hosts: ["instagram.com"], color: 0xE1306C, glyph: "camera.fill"),
        PanelApp(id: "tiktok", name: "TikTok", url: "https://www.tiktok.com", hosts: ["tiktok.com"], color: 0x111317, glyph: "music.note.tv"),
        PanelApp(id: "x", name: "X", url: "https://x.com", hosts: ["x.com", "twitter.com"], color: 0x14171C, glyph: "xmark"),
        PanelApp(id: "reddit", name: "Reddit", url: "https://www.reddit.com", hosts: ["reddit.com"], color: 0xFF4500, glyph: "text.bubble.fill"),
        PanelApp(id: "twitch", name: "Twitch", url: "https://m.twitch.tv", hosts: ["twitch.tv"], color: 0x9146FF, glyph: "tv.fill"),
        PanelApp(id: "netflix", name: "Netflix", url: "https://www.netflix.com", hosts: ["netflix.com"], color: 0xE50914, glyph: "film.fill"),
        PanelApp(id: "gmail", name: "Gmail", url: "https://mail.google.com", hosts: ["mail.google.com"], color: 0xEA4335, glyph: "envelope.fill"),
        PanelApp(id: "chatgpt", name: "ChatGPT", url: "https://chatgpt.com", hosts: ["chatgpt.com", "chat.openai.com"], color: 0x10A37F, glyph: "sparkles"),
    ]

    /// Ancladas la primera vez que se abre Nova.
    static var defaults: [PanelApp] { ["youtube", "spotify", "whatsapp", "discord"].compactMap { id in all.first { $0.id == id } } }

    static func best(in list: [PanelApp], host: String) -> PanelApp? {
        var winner: PanelApp?
        var score = 0
        for app in list {
            let s = app.matchScore(host: host)
            if s > score { score = s; winner = app }
        }
        return winner
    }

    static func match(host: String) -> PanelApp? { best(in: all, host: host) }
}

// MARK: - Estado del panel (persistente)

final class PanelStore: ObservableObject {
    static let shared = PanelStore()
    static let maxRunning = 4
    private static let key = "panelPinned.v2"

    @Published var pinned: [PanelApp] = [] { didSet { save() } }
    @Published var isOpen = false
    @Published var notice: String?
    /// Pista del mini reproductor que el usuario ha cerrado (vuelve a salir al cambiar de canción).
    @Published var hiddenPlayerKey: String?

    private var noticeWork: DispatchWorkItem?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([PanelApp].self, from: data) {
            pinned = list
        } else {
            pinned = AppCatalog.defaults
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pinned) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func isPinned(_ id: String) -> Bool { pinned.contains { $0.id == id } }

    func pin(_ app: PanelApp) {
        guard !isPinned(app.id) else { return }
        pinned.append(app)
        Haptics.success()
        flash("\(app.name) añadida al panel")
    }

    func unpin(_ id: String) {
        guard let app = pinned.first(where: { $0.id == id }) else { return }
        pinned.removeAll { $0.id == id }
        flash("\(app.name) quitada del panel")
    }

    func move(from source: IndexSet, to destination: Int) { pinned.move(fromOffsets: source, toOffset: destination) }
    func remove(at offsets: IndexSet) { pinned.remove(atOffsets: offsets) }

    /// App a la que pertenece una pestaña: la que la abrió desde el panel, o la que coincide por dominio.
    func resolve(_ tab: BrowserTab) -> PanelApp? {
        if let id = tab.panelAppID, let app = pinned.first(where: { $0.id == id }) ?? AppCatalog.all.first(where: { $0.id == id }) {
            return app
        }
        return AppCatalog.best(in: pinned, host: tab.host) ?? AppCatalog.match(host: tab.host)
    }

    /// App para anclar a partir de una dirección escrita a mano.
    static func custom(from text: String, name: String = "") -> PanelApp? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.contains("."), !raw.contains(" ") else { return nil }
        guard let url = URL(string: raw.hasPrefix("http") ? raw : "https://" + raw), let host = url.host else { return nil }
        if let known = AppCatalog.match(host: host) { return known }
        var app = PanelApp.adHoc(host: host, url: url)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { app.name = n }
        return app
    }

    func flash(_ text: String) {
        noticeWork?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { notice = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.notice = nil }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
    }

    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { isOpen = open }
    }
}

// MARK: - Entradas del panel

struct PanelEntry: Identifiable {
    let id: String
    let app: PanelApp
    let tab: BrowserTab?
    let pinned: Bool
}

extension BrowserModel {
    static let maxDockApps = PanelStore.maxRunning

    /// Pestañas que cuentan como app abierta: abiertas desde el panel, de un sitio reconocido
    /// o que están sonando. Las privadas nunca aparecen.
    var panelTabs: [BrowserTab] {
        let store = PanelStore.shared
        return tabs.filter { !$0.isPrivate && $0.hasPage && ($0.panelAppID != nil || $0.isPlayingAudio || store.resolve($0) != nil) }
    }

    /// Compatibilidad con el código anterior.
    var dockTabs: [BrowserTab] { panelTabs }

    func panelTab(for app: PanelApp) -> BrowserTab? {
        let store = PanelStore.shared
        return panelTabs.first { store.resolve($0)?.id == app.id }
    }

    /// Ancladas (con su pestaña si está abierta) + otras apps abiertas que no están ancladas.
    func panelEntries() -> (pinned: [PanelEntry], others: [PanelEntry]) {
        let store = PanelStore.shared
        let running = panelTabs
        var used = Set<UUID>()
        let pinnedEntries: [PanelEntry] = store.pinned.map { app in
            let tab = running.first { !used.contains($0.id) && store.resolve($0)?.id == app.id }
            if let tab = tab { used.insert(tab.id) }
            return PanelEntry(id: app.id, app: app, tab: tab, pinned: true)
        }
        let others: [PanelEntry] = running.filter { !used.contains($0.id) }.map { tab in
            PanelEntry(id: "tab:" + tab.id.uuidString,
                       app: store.resolve(tab) ?? PanelApp.adHoc(host: tab.host, url: tab.currentURL),
                       tab: tab, pinned: false)
        }
        return (pinnedEntries, others)
    }

    /// Pestaña que debería mostrar el reproductor: la que suena; si no, la última con algo en pausa.
    var nowPlayingTab: BrowserTab? {
        let candidates = tabs.filter { !$0.isPrivate && $0.nowPlaying != nil }
        return candidates.first { $0.isPlayingAudio } ?? candidates.max { $0.lastUsed < $1.lastUsed }
    }

    /// Abre una app del panel: si ya está abierta cambia a ella; si no, la abre en una pestaña nueva.
    func openPanelApp(_ app: PanelApp) {
        if let tab = panelTab(for: app) {
            focusPanelTab(tab)
            return
        }
        createTab()
        let tab = activeTab
        tab.panelAppID = app.id
        if app.desktop { tab.setDesktop(true) }
        load(app.url)
        enforceDockLimit()
    }

    func focusPanelTab(_ tab: BrowserTab) {
        if tab.isHome && tab.hasPage { tab.isHome = false }
        selectTab(tab.id)
    }

    /// Más de 4 apps abiertas: se suspende la que lleve más tiempo sin usarse
    /// (nunca la que estás viendo ni una que esté sonando).
    func enforceDockLimit() {
        let running = panelTabs
        guard running.count > Self.maxDockApps else { return }
        let candidates = running
            .filter { $0.id != activeTabID && !$0.isPlayingAudio }
            .sorted { $0.lastUsed < $1.lastUsed }
        guard let victim = candidates.first else { return }
        let name = PanelStore.shared.resolve(victim)?.name ?? victim.host
        closeTab(victim.id)
        PanelStore.shared.flash("\(name) se ha suspendido para liberar memoria")
    }

    /// Se llama cada 2 s: sonido, reproductor y no leídos de cada pestaña.
    /// Resumen del estado de medios: si cambia, se avisa a la interfaz (mini reproductor, asa, panel).
    private var mediaSignature: String {
        tabs.map { t in
            "\(t.id.uuidString):\(t.isPlayingAudio ? 1 : 0)\(t.nowPlaying == nil ? 0 : 1)\(t.nowPlaying?.paused == true ? 1 : 0)\(t.isMuted ? 1 : 0)\(t.unreadCount)"
        }.joined(separator: "|")
    }

    func pollAudioState() {
        let before = mediaSignature
        let wasPlaying = Set(tabs.filter { $0.isPlayingAudio }.map { $0.id })
        let group = DispatchGroup()
        for tab in tabs {
            group.enter()
            tab.pollMedia { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // «Solo una app con sonido»: al empezar a sonar una, se pausan las demás.
            if Prefs.flag("panelExclusiveAudio", default: false) {
                let started = self.tabs.filter { $0.isPlayingAudio && !wasPlaying.contains($0.id) }
                if let newest = started.last {
                    for other in self.tabs where other.id != newest.id && other.isPlayingAudio {
                        other.mediaCommand(.pause)
                    }
                }
            }
            if self.mediaSignature != before { self.objectWillChange.send() }
            self.enforceDockLimit()
        }
    }
}

// MARK: - Medios de cada pestaña

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var artwork: URL?
    var position: Double
    var duration: Double
    var paused: Bool
    var polledAt: Date

    /// Posición estimada entre lecturas (la barra avanza suave aunque se lea cada 2 s).
    func position(at date: Date) -> Double {
        guard !paused, duration > 0 else { return position }
        return min(duration, position + date.timeIntervalSince(polledAt))
    }

    /// Identifica la pista (para el botón de cerrar del mini reproductor).
    var trackKey: String { title + "|" + artist }

    static func == (a: NowPlaying, b: NowPlaying) -> Bool {
        a.title == b.title && a.artist == b.artist && a.artwork == b.artwork && a.paused == b.paused
            && abs(a.position - b.position) < 0.75 && abs(a.duration - b.duration) < 0.5
    }
}

enum MediaCommand {
    case toggle, play, pause, next, previous
    case mute(Bool)
}

extension BrowserTab {
    private static let probeJS = #"""
    (function () {
      var ms = Array.prototype.slice.call(document.querySelectorAll('video,audio'));
      var live = ms.filter(function (m) { return m.readyState > 0 && (m.currentTime > 0 || !m.paused); });
      var main = live.filter(function (m) { return !m.paused; })[0] || live[0] || null;
      var playing = ms.some(function (m) { return !m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState > 2; });
      var md = (navigator.mediaSession && navigator.mediaSession.metadata) || null;
      var art = '';
      try { if (md && md.artwork && md.artwork.length) { art = md.artwork[md.artwork.length - 1].src || ''; } } catch (e) {}
      return {
        playing: playing,
        has: !!main || !!(md && md.title),
        paused: main ? main.paused : !playing,
        muted: ms.length > 0 && ms.every(function (m) { return m.muted; }),
        title: md ? String(md.title || '') : '',
        artist: md ? String(md.artist || md.album || '') : '',
        art: String(art),
        t: main ? (main.currentTime || 0) : 0,
        d: (main && isFinite(main.duration)) ? main.duration : 0,
        doc: String(document.title || '')
      };
    })();
    """#

    private static let controlJS = #"""
    (function (action) {
      function q(list) { for (var i = 0; i < list.length; i++) { var b = document.querySelector(list[i]); if (b && !b.disabled) return b; } return null; }
      function go(m) { try { var p = m.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
      var media = Array.prototype.slice.call(document.querySelectorAll('video,audio')).filter(function (m) { return m.readyState > 0; });
      var main = media.filter(function (m) { return !m.paused; })[0] || media.sort(function (a, b) { return (b.duration || 0) - (a.duration || 0); })[0];
      var SEL = {
        toggle: ['[data-testid="control-button-playpause"]', 'ytmusic-player-bar #play-pause-button', '.ytp-play-button', '.playControl', 'button.player-control-play-pause-icon'],
        next: ['[data-testid="control-button-skip-forward"]', 'ytmusic-player-bar .next-button', '.ytp-next-button', '.skipControl__next', 'button[aria-label*="Next" i]', 'button[aria-label*="Siguiente" i]'],
        previous: ['[data-testid="control-button-skip-back"]', 'ytmusic-player-bar .previous-button', '.ytp-prev-button', '.skipControl__previous', 'button[aria-label*="Previous" i]', 'button[aria-label*="Anterior" i]']
      };
      if (action === 'mute' || action === 'unmute') { media.forEach(function (m) { m.muted = (action === 'mute'); }); return true; }
      if (action === 'pause') { media.forEach(function (m) { if (!m.paused) m.pause(); }); return true; }
      if (action === 'play') { if (main && main.paused) go(main); return true; }
      if (action === 'toggle') {
        if (/spotify\.com|music\.youtube\.com|soundcloud\.com/.test(location.hostname)) { var sb = q(SEL.toggle); if (sb) { sb.click(); return true; } }
        if (main) { if (main.paused) go(main); else main.pause(); return true; }
        var tb = q(SEL.toggle); if (tb) { tb.click(); return true; }
        return false;
      }
      var b = q(SEL[action] || []);
      if (b) { b.click(); return true; }
      if (main && action === 'previous') { main.currentTime = 0; return true; }
      if (main && action === 'next' && isFinite(main.duration)) { main.currentTime = Math.max(0, main.duration - 0.25); return true; }
      return false;
    })('__ACTION__');
    """#

    private static let unreadPrefix = try! NSRegularExpression(pattern: "^\\((\\d{1,4})\\+?\\)")
    private static let unreadInbox = try! NSRegularExpression(pattern: "(?:Recibidos|Inbox|Bandeja de entrada)\\s*\\((\\d{1,5})\\)", options: [.caseInsensitive])

    /// «(3) WhatsApp», «(12) Discord», «Recibidos (5) - Gmail» → número de no leídos.
    static func unread(fromTitle title: String) -> Int {
        let range = NSRange(location: 0, length: (title as NSString).length)
        for rx in [unreadPrefix, unreadInbox] {
            if let m = rx.firstMatch(in: title, range: range), m.numberOfRanges > 1 {
                return Int((title as NSString).substring(with: m.range(at: 1))) ?? 0
            }
        }
        return 0
    }

    /// Lee el estado de audio, el reproductor (Media Session) y los no leídos.
    func pollMedia(_ done: @escaping () -> Void) {
        guard hasPage else {
            if isPlayingAudio { isPlayingAudio = false }
            if nowPlaying != nil { nowPlaying = nil }
            if unreadCount != 0 { unreadCount = 0 }
            done()
            return
        }
        webView.evaluateJavaScript(Self.probeJS) { [weak self] result, _ in
            defer { done() }
            guard let self = self else { return }
            let d = result as? [String: Any] ?? [:]
            let num: (String) -> Double = { (d[$0] as? NSNumber)?.doubleValue ?? 0 }
            let flag: (String) -> Bool = { (d[$0] as? NSNumber)?.boolValue ?? false }
            let str: (String) -> String = { (d[$0] as? String) ?? "" }

            let playing = flag("playing")
            if playing != self.isPlayingAudio { self.isPlayingAudio = playing }
            let muted = flag("muted")
            if muted != self.isMuted { self.isMuted = muted }

            let docTitle = str("doc")
            let unread = Self.unread(fromTitle: docTitle)
            if unread != self.unreadCount { self.unreadCount = unread }

            var np: NowPlaying?
            if flag("has") {
                var title = str("title")
                if title.isEmpty {
                    // Sin Media Session: el título de la página sin el «(3)» ni el « - YouTube».
                    title = docTitle.replacingOccurrences(of: "^\\(\\d+\\+?\\)\\s*", with: "", options: .regularExpression)
                    for suffix in [" - YouTube", " - YouTube Music", " | SoundCloud", " | Twitch"] where title.hasSuffix(suffix) {
                        title = String(title.dropLast(suffix.count))
                    }
                }
                if title.isEmpty { title = self.host }
                let artURL = URL(string: str("art"))
                np = NowPlaying(title: title, artist: str("artist"),
                                artwork: (artURL?.scheme == "https" || artURL?.scheme == "http") ? artURL : nil,
                                position: num("t"), duration: num("d"), paused: flag("paused"), polledAt: Date())
            }
            if np != self.nowPlaying { self.nowPlaying = np }
        }
    }

    func mediaCommand(_ cmd: MediaCommand) {
        let action: String
        switch cmd {
        case .toggle: action = "toggle"
        case .play: action = "play"
        case .pause: action = "pause"
        case .next: action = "next"
        case .previous: action = "previous"
        case .mute(let on):
            action = on ? "mute" : "unmute"
            isMuted = on
        }
        let js = Self.controlJS.replacingOccurrences(of: "__ACTION__", with: action)
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.pollMedia {} }
        }
    }
}

extension UIImage {
    /// Icono pequeño (96 px) para guardar con una app anclada desde el sitio actual.
    func panelIconPNG() -> Data? {
        let size = CGSize(width: 96, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
