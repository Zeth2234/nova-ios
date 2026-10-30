import SwiftUI
import WebKit

/// Guarda el WKWebView y el estado que muestra la interfaz.
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView

    @Published var addressText: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        load("https://www.google.com")
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
            url = URL(string: "https://www.google.com/search?q=" + q)
        }
        if let url = url {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let url = webView.url?.absoluteString { addressText = url }
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refreshState() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { refreshState() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshState() }
}
