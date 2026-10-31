import SwiftUI
import WebKit

/// Una pestaña independiente de Nova. Cada pestaña conserva su propio WKWebView,
/// historial, URL y estado de carga; WKWebsiteDataStore.default() comparte cookies
/// y sesiones entre pestañas, como en un navegador convencional.
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    /// true en pestañas privadas: datos de sitio solo en memoria, sin favicons en caché ni contraseñas.
    let isPrivate: Bool

    /// Almacén compartido por todas las pestañas privadas. Al cerrar la última se descarta
    /// y se crea uno nuevo, con lo que cookies y datos desaparecen.
    static var privateStore = WKWebsiteDataStore.nonPersistent()
    static func resetPrivateStore() { privateStore = WKWebsiteDataStore.nonPersistent() }
    private static let privateSession = URLSession(configuration: .ephemeral)

    @Published var title = "Nueva pestaña"
    @Published var host = "Página de inicio"
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var isHome = true
    /// Icono real declarado por el sitio web (favicon / apple-touch-icon).
    @Published var faviconImage: UIImage?
    /// true si la página reproduce audio ahora mismo (alimenta el panel de apps).
    @Published var isPlayingAudio = false
    /// Versión de ordenador: user agent de Safari de Mac + modo de contenido de escritorio.
    @Published var desktopMode = false
    /// Panel de apps: app del panel que abrió esta pestaña, reproductor, no leídos y silencio.
    @Published var panelAppID: String?
    @Published var nowPlaying: NowPlaying?
    @Published var unreadCount = 0
    @Published var isMuted = false
    /// Última vez que se usó (para suspender la app más antigua si hay más de 4).
    var lastUsed = Date()

    var onStateChange: (() -> Void)?
    private var observers: [NSKeyValueObservation] = []
    private var faviconPageKey: String?
    private var faviconTask: URLSessionDataTask?
    private static let faviconCache = NSCache<NSURL, UIImage>()

    init(isPrivate: Bool = false) {
        self.isPrivate = isPrivate
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? BrowserTab.privateStore : WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        config.allowsPictureInPictureMediaPlayback = true
        // Hace creer a la web que siempre está visible, para que YouTube/Spotify no se pausen solos.
        let keepAlive = WKUserScript(source: """
        (function() {
            try {
                Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
                Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
                document.addEventListener('visibilitychange', e => e.stopImmediatePropagation(), true);
                window.addEventListener('pagehide', e => e.stopImmediatePropagation(), true);
            } catch (e) {}
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(keepAlive)
        config.userContentController.addUserScript(EQModel.shared.userScript) // ecualizador global
        config.userContentController.addUserScript(QuickLoginScripts.passkeyShim)
        if !isPrivate { config.userContentController.addUserScript(QuickLoginScripts.credentials) }

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = NovaTheme.uiBg
        webView.scrollView.backgroundColor = NovaTheme.uiBg

        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        let controller = webView.configuration.userContentController
        controller.add(WeakScriptHandler(self), name: "novaPasskey")
        if isPrivate {
            if Prefs.flag("blockTrackers") { TrackerBlocker.install(on: controller) }
        } else {
            controller.add(WeakScriptHandler(self), name: "novaCreds")
        }

        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.progress = webView.estimatedProgress
                self?.notifyStateChange()
            }
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })
        observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })
    }

    /// Libera la pestaña: detiene la carga y suelta los manejadores de scripts.
    func teardown() {
        faviconTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        if isPrivate { webView.loadHTMLString("", baseURL: nil) }
    }

    var hasPage: Bool { webView.url != nil }
    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }

    /// Acepta una dirección web o convierte el texto en una búsqueda.
    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var url: URL?
        if text.contains("."), !text.contains(" ") {
            url = URL(string: text.hasPrefix("http") ? text : "https://" + text)
        }
        if url == nil {
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            url = URL(string: SearchEngine.current.searchPrefix + query)
        }

        if let url = url {
            isHome = false
            notifyStateChange()
            webView.load(URLRequest(url: url))
        }
    }

    func goHome() {
        isHome = true
        notifyStateChange()
    }

    func setDesktop(_ on: Bool) {
        desktopMode = on
        webView.customUserAgent = on
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            : nil
        guard var comps = webView.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else {
            notifyStateChange(); return
        }
        // Los subdominios móviles (m.youtube.com…) siguen sirviendo la versión móvil: se pasa al dominio normal.
        if on, let h = comps.host, h.hasPrefix("m.") || h.hasPrefix("mobile.") {
            comps.host = String(h.drop(while: { $0 != "." }).dropFirst())
            if comps.host?.contains(".") == true, !(comps.host?.hasPrefix("www.") ?? false) { comps.host = "www." + (comps.host ?? "") }
        }
        if let url = comps.url { isHome = false; webView.load(URLRequest(url: url)) }
        notifyStateChange()
    }

    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
        } else if webView.url != nil {
            webView.reload()
        }
        refreshState()
    }

    private func refreshState() {
        currentURL = webView.url
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        if let url = webView.url {
            host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
            let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            title = pageTitle.isEmpty ? host : pageTitle
        } else if isHome {
            title = "Nueva pestaña"
            host = "Página de inicio"
        }
        notifyStateChange()
    }

    private func notifyStateChange() {
        onStateChange?()
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = desktopMode ? .desktop : .mobile
        decisionHandler(.allow, preferences)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshState()
        refreshFavicon()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }

    // MARK: Favicon del sitio
    // Se consulta el icono que declara la propia página y se descarga como imagen.
    // El icono queda asociado a esta pestaña, no a la pestaña activa global.
    private func refreshFavicon() {
        guard let pageURL = webView.url,
              let host = pageURL.host,
              pageURL.scheme == "https" || pageURL.scheme == "http" else { return }

        let pageKey = "\(pageURL.scheme ?? "https")://\(host)"
        guard faviconPageKey != pageKey else { return }
        faviconPageKey = pageKey
        faviconTask?.cancel()
        faviconImage = nil

        let script = """
        (function() {
            const links = Array.from(document.querySelectorAll('link[rel*="icon"], link[rel*="apple-touch-icon"]'));
            const rank = (link) => {
                const rel = (link.rel || '').toLowerCase();
                const type = (link.type || '').toLowerCase();
                const href = (link.href || '').toLowerCase();
                if (rel.includes('apple-touch-icon')) return 0;
                if (type.includes('png') || ['.png', '.webp', '.jpg', '.jpeg'].some(ext => href.includes(ext))) return 1;
                if (type.includes('svg') || href.includes('.svg')) return 3;
                return 2;
            };
            links.sort((a, b) => rank(a) - rank(b));
            return links.length ? links[0].href : '';
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self = self,
                      self.webView.url?.host == host,
                      self.faviconPageKey == pageKey else { return }

                let declaredURL = (result as? String).flatMap { value -> URL? in
                    guard !value.isEmpty else { return nil }
                    return URL(string: value, relativeTo: pageURL)?.absoluteURL
                }
                let fallbackURLs = [
                    URL(string: "/apple-touch-icon.png", relativeTo: pageURL)?.absoluteURL,
                    URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL
                ].compactMap { $0 }
                var candidates = declaredURL.map { [$0] } ?? []
                candidates.append(contentsOf: fallbackURLs)
                candidates = candidates.reduce(into: [URL]()) { result, candidate in
                    if !result.contains(candidate) { result.append(candidate) }
                }
                candidates = candidates.filter { candidate in
                    candidate.scheme == "https" || candidate.scheme == "http"
                }
                self.downloadFavicon(from: candidates, pageKey: pageKey)
            }
        }
    }

    private func downloadFavicon(from candidates: [URL], index: Int = 0, pageKey: String) {
        guard faviconPageKey == pageKey, index < candidates.count else { return }
        let url = candidates[index]
        let cacheKey = url as NSURL
        if !isPrivate, let cached = Self.faviconCache.object(forKey: cacheKey) {
            faviconImage = cached
            notifyStateChange()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = isPrivate ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
        let session = isPrivate ? Self.privateSession : URLSession.shared
        faviconTask = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self, self.faviconPageKey == pageKey else { return }
            let image: UIImage? = {
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let data = data,
                      data.count <= 2_000_000 else { return nil }
                return UIImage(data: data)
            }()

            if let image = image {
                if !self.isPrivate { Self.faviconCache.setObject(image, forKey: cacheKey) }
                DispatchQueue.main.async {
                    guard self.faviconPageKey == pageKey,
                          self.webView.url?.host == URL(string: pageKey)?.host else { return }
                    self.faviconImage = image
                    self.notifyStateChange()
                }
            } else {
                // Si el sitio solo ofrece SVG/ICO no compatible, prueba el
                // apple-touch-icon y después /favicon.ico, sin pedir servicios externos.
                DispatchQueue.main.async {
                    guard self.faviconPageKey == pageKey,
                          self.webView.url?.host == URL(string: pageKey)?.host else { return }
                    self.downloadFavicon(from: candidates, index: index + 1, pageKey: pageKey)
                }
            }
        }
        faviconTask?.resume()
    }

    // MARK: WKUIDelegate
    // Conserva el comportamiento anterior: los target=_blank se abren en esta pestaña.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Estado y acciones globales del navegador. Gestiona la colección de pestañas y
/// mantiene las propiedades que consume la interfaz sincronizadas con la activa.
final class BrowserModel: NSObject, ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var activeTabID: UUID?

    // Estado de navegación expuesto para las barras que ya utiliza Nova.
    @Published var addressText = ""
    /// Texto que el usuario está escribiendo en la barra (no lo pisan las actualizaciones de carga).
    @Published var omniText = ""
    @Published var host = ""
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var isSecure = true
    @Published var progress: Double = 0
    @Published var isHome = true
    @Published var isPrivate = false

    override init() {
        super.init()
        let firstTab = makeTab(private: false)
        tabs = [firstTab]
        activeTabID = firstTab.id
        refreshFromActiveTab()
        EQModel.shared.webViews = { [weak self] in self?.tabs.map { $0.webView } ?? [] }
        EQModel.shared.activeWebView = { [weak self] in self?.webView }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.pollAudioState()
        }
    }

    var activeTab: BrowserTab {
        if let id = activeTabID, let tab = tabs.first(where: { $0.id == id }) {
            return tab
        }
        // Siempre existe al menos una pestaña, incluso después de cerrar la última.
        return tabs[0]
    }

    var webView: WKWebView { activeTab.webView }
    /// Número de pestañas del modo activo (normal o privado).
    var tabCount: Int { modeTabs(activeTab.isPrivate).count }

    func modeTabs(_ priv: Bool) -> [BrowserTab] { tabs.filter { $0.isPrivate == priv } }
    var backEnabled: Bool { activeTab.hasPage }

    private func makeTab(private priv: Bool) -> BrowserTab {
        let tab = BrowserTab(isPrivate: priv)
        tab.onStateChange = { [weak self, weak tab] in
            guard let self = self, let tab = tab else { return }
            self.objectWillChange.send() // el panel de apps también refleja pestañas en segundo plano
            if self.activeTabID == tab.id { self.refreshFromActiveTab() }
        }
        return tab
    }

    /// Crea una pestaña nueva (normal o privada) y la selecciona inmediatamente.
    func createTab(private priv: Bool = false) {
        let tab = makeTab(private: priv)
        tabs.append(tab)
        activeTabID = tab.id
        refreshFromActiveTab()
    }

    func selectTab(_ id: UUID) {
        guard let target = tabs.first(where: { $0.id == id }) else { return }
        if !tabs.isEmpty { activeTab.lastUsed = Date() }
        target.lastUsed = Date()
        activeTabID = id
        refreshFromActiveTab()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        let wasActive = activeTabID == id
        tabs.remove(at: index)
        closing.teardown()
        if closing.isPrivate { discardPrivateDataIfUnused() }

        if wasActive {
            // Prefiere la pestaña más cercana del mismo modo; si no queda, una normal.
            let sameMode = tabs.enumerated()
                .filter { $0.element.isPrivate == closing.isPrivate }
                .min { abs($0.offset - index) < abs($1.offset - index) }
            if let next = sameMode?.element {
                activeTabID = next.id
            } else if let normal = tabs.last(where: { !$0.isPrivate }) {
                activeTabID = normal.id
            } else {
                let replacement = makeTab(private: false)
                tabs.append(replacement)
                activeTabID = replacement.id
            }
        }
        ensureNormalTab()
        refreshFromActiveTab()
    }

    /// Cierra todas las pestañas del modo indicado.
    func closeAllTabs(private priv: Bool = false) {
        let closing = tabs.filter { $0.isPrivate == priv }
        tabs.removeAll { $0.isPrivate == priv }
        closing.forEach { $0.teardown() }
        if priv { discardPrivateDataIfUnused() }

        if let id = activeTabID, tabs.contains(where: { $0.id == id }) {
            // La pestaña activa sigue existiendo.
        } else if let normal = tabs.last(where: { !$0.isPrivate }) {
            activeTabID = normal.id
        } else {
            let replacement = makeTab(private: false)
            tabs.append(replacement)
            activeTabID = replacement.id
        }
        ensureNormalTab()
        refreshFromActiveTab()
    }

    /// Vuelve a las pestañas normales sin cerrar las privadas.
    func leavePrivateMode() {
        if let normal = tabs.last(where: { !$0.isPrivate }) {
            selectTab(normal.id)
        } else {
            createTab()
        }
    }

    private func ensureNormalTab() {
        if !tabs.contains(where: { !$0.isPrivate }) {
            tabs.append(makeTab(private: false))
        }
        if activeTabID == nil || !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = tabs.last(where: { !$0.isPrivate })?.id ?? tabs.first?.id
        }
    }

    private func discardPrivateDataIfUnused() {
        if !tabs.contains(where: { $0.isPrivate }) { BrowserTab.resetPrivateStore() }
    }

    func toggleDesktop() {
        activeTab.setDesktop(!activeTab.desktopMode)
        refreshFromActiveTab()
    }

    /// Acepta una URL o un texto de búsqueda en la pestaña activa.
    func load(_ input: String) {
        activeTab.load(input)
        refreshFromActiveTab()
    }

    // MARK: Navegación
    func back() {
        let tab = activeTab
        if tab.isHome {
            if tab.hasPage { tab.isHome = false }
        } else if tab.webView.canGoBack {
            tab.webView.goBack()
        } else {
            tab.goHome()
        }
        refreshFromActiveTab()
    }

    func forward() {
        let tab = activeTab
        guard tab.webView.canGoForward else { return }
        tab.isHome = false
        tab.webView.goForward()
        refreshFromActiveTab()
    }

    func goHome() {
        activeTab.goHome()
        refreshFromActiveTab()
    }

    func reloadOrStop() {
        activeTab.reloadOrStop()
        refreshFromActiveTab()
    }

    private func refreshFromActiveTab() {
        guard !tabs.isEmpty else { return }
        let tab = activeTab
        addressText = tab.currentURL?.absoluteString ?? ""
        host = tab.host
        currentURL = tab.currentURL
        canGoBack = tab.canGoBack
        canGoForward = tab.canGoForward
        isLoading = tab.isLoading
        isSecure = tab.currentURL?.scheme != "http"
        progress = tab.progress
        isHome = tab.isHome
        isPrivate = tab.isPrivate
    }
}
