import SwiftUI
import WebKit

/// Guarda el WKWebView y el estado que muestra la interfaz.
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView

    @Published var addressText: String = ""
    @Published var host: String = ""
    @Published var currentURL: URL? = nil
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var isSecure = true
    @Published var progress: Double = 0
    /// true = se muestra la pantalla de inicio de Nova en vez de la web.
    @Published var isHome = true

    private var observers: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.10, alpha: 1)
        webView.scrollView.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.10, alpha: 1)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self

        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshState() }
        })
    }

    /// Acepta una URL o un texto de búsqueda.
    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var url: URL?
        if text.contains("."), !text.contains(" ") {
            url = URL(string: text.hasPrefix("http") ? text : "https://" + text)
        }
        if url == nil {
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            url = URL(string: SearchEngine.current.searchPrefix + q)
        }
        if let url = url {
            isHome = false
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: Navegación

    var hasPage: Bool { webView.url != nil }
    var backEnabled: Bool { isHome ? hasPage : true }

    func back() {
        if isHome {
            if hasPage { isHome = false }
        } else if webView.canGoBack {
            webView.goBack()
        } else {
            isHome = true
        }
    }

    func forward() {
        if webView.canGoForward {
            isHome = false
            webView.goForward()
        }
    }

    func goHome() { isHome = true }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        currentURL = webView.url
        isSecure = webView.url?.scheme != "http"
        if let url = webView.url {
            addressText = url.absoluteString
            host = (url.host ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
        }
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }

    // MARK: WKUIDelegate — los enlaces que abren "nueva pestaña" se cargan aquí
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
