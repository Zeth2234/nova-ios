import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Barra de direcciones
            HStack(spacing: 8) {
                TextField("Buscar o escribir dirección", text: $model.addressText)
                    .focused($addressFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .onSubmit {
                        model.load(model.addressText)
                        addressFocused = false
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if model.isLoading {
                    ProgressView()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Página web
            WebViewContainer(webView: model.webView)

            // Botones inferiores
            HStack {
                Button(action: model.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                Spacer()
                Button(action: model.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                Spacer()
                Button(action: model.reload) { Image(systemName: "arrow.clockwise") }
            }
            .font(.title3)
            .padding(.horizontal, 32)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
    }
}
