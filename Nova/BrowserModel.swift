import SwiftUI
import WebKit

/// Una pestaña independiente de Nova. Cada pestaña conserva su propio WKWebView,
/// historial, URL y estado de carga; WKWebsiteDataStore.default() comparte cookies
/// y sesiones entre pestañas, como en un navegador convencional.
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView

    @Published var title = "Nueva pestaña"
    @Published var host = "Página de inicio"
    @Published var currentURL: URL?
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var isHome = true

    var onStateChange: (() -> Void)?
    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.025, green: 0.028, blue: 0.065, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0.025, green: 0.028, blue: 0.065, alpha: 1)

        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self

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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }

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
    @Published var host = ""
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var isSecure = true
    @Published var progress: Double = 0
    @Published var isHome = true

    override init() {
        super.init()
        let firstTab = makeTab()
        tabs = [firstTab]
        activeTabID = firstTab.id
        refreshFromActiveTab()
    }

    var activeTab: BrowserTab {
        if let id = activeTabID, let tab = tabs.first(where: { $0.id == id }) {
            return tab
        }
        // Siempre existe al menos una pestaña, incluso después de cerrar la última.
        return tabs[0]
    }

    var webView: WKWebView { activeTab.webView }
    var tabCount: Int { tabs.count }
    var backEnabled: Bool { activeTab.hasPage }

    private func makeTab() -> BrowserTab {
        let tab = BrowserTab()
        tab.onStateChange = { [weak self, weak tab] in
            guard let self = self, let tab = tab, self.activeTabID == tab.id else { return }
            self.refreshFromActiveTab()
        }
        return tab
    }

    /// Crea una pestaña nueva y la selecciona inmediatamente.
    func createTab() {
        let tab = makeTab()
        tabs.append(tab)
        activeTabID = tab.id
        refreshFromActiveTab()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        refreshFromActiveTab()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closingActiveTab = activeTabID == id
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = makeTab()
            tabs = [replacement]
            activeTabID = replacement.id
        } else if closingActiveTab {
            let nextIndex = min(index, tabs.count - 1)
            activeTabID = tabs[nextIndex].id
        }
        refreshFromActiveTab()
    }

    func closeAllTabs() {
        let replacement = makeTab()
        tabs = [replacement]
        activeTabID = replacement.id
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
    }
}
