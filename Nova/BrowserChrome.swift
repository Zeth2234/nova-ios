import SwiftUI
import WebKit

final class BrowserWebViewHost: UIView {
    private weak var displayedWebView: WKWebView?

    func display(_ webView: WKWebView) {
        guard displayedWebView !== webView else { return }
        displayedWebView?.removeFromSuperview()
        displayedWebView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> BrowserWebViewHost {
        let host = BrowserWebViewHost()
        host.backgroundColor = .clear
        host.display(webView)
        return host
    }

    func updateUIView(_ uiView: BrowserWebViewHost, context: Context) {
        // SwiftUI conserva el contenedor; sustituimos el WKWebView hijo al cambiar de pestaña.
        uiView.display(webView)
    }
}

// MARK: - Barra de direcciones

struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill((model.isSecure ? NovaTheme.good : Color.orange).opacity(0.13))
                        .frame(width: 30, height: 30)
                    Image(systemName: model.isSecure ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(model.isSecure ? NovaTheme.good : Color.orange)
                }

                ZStack(alignment: .leading) {
                    TextField("Buscar o escribir una dirección", text: $model.addressText)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .tint(NovaTheme.accent)
                        .opacity(focused ? 1 : 0)
                        .onSubmit(submit)

                    if !focused {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.host.isEmpty ? "Buscar o escribir una dirección" : model.host)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                            if !model.host.isEmpty && model.currentURL != nil {
                                Text("Conexión \(model.isSecure ? "segura" : "no segura")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(model.isSecure ? NovaTheme.good.opacity(0.9) : Color.orange.opacity(0.9))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

                Button {
                    if focused {
                        model.addressText = ""
                    } else {
                        model.reloadOrStop()
                    }
                } label: {
                    Image(systemName: focused ? "xmark.circle.fill" : (model.isLoading ? "xmark" : "arrow.clockwise"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(NovaTheme.dim)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(focused ? "Borrar dirección" : (model.isLoading ? "Detener carga" : "Recargar página"))
            }
            .padding(.horizontal, 11)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(NovaTheme.surface))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(focused ? NovaTheme.accent.opacity(0.75) : NovaTheme.stroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 9, y: 3)

            Button {
                focused = false
                model.createTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NovaTheme.surfaceHi))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nueva pestaña")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { progressLine }
        .animation(.easeOut(duration: 0.18), value: focused)
        .onChange(of: model.activeTabID) { _ in focused = false }
    }

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.clear)
                Rectangle()
                    .fill(NovaTheme.accentGradient)
                    .frame(width: geo.size.width * CGFloat(model.progress), height: 2)
                    .opacity(model.isLoading ? 1 : 0)
            }
            .clipped()
        }
        .frame(height: 2)
    }

    private func submit() {
        let value = model.addressText
        focused = false
        model.load(value)
    }
}

// MARK: - Barra de navegación inferior

struct BottomBar: View {
    @ObservedObject var model: BrowserModel
    var openSettings: () -> Void
    var openTabs: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: model.back) { icon("chevron.left", enabled: model.backEnabled) }
                .disabled(!model.backEnabled)
                .accessibilityLabel("Atrás")
            Button(action: model.forward) { icon("chevron.right", enabled: model.canGoForward) }
                .disabled(!model.canGoForward)
                .accessibilityLabel("Adelante")
            Button(action: model.goHome) {
                icon(model.isHome ? "house.fill" : "house", tint: model.isHome ? NovaTheme.accent : nil)
            }
            .accessibilityLabel("Inicio")

            Button(action: openTabs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    Text("\(model.tabCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(NovaTheme.accent))
                        .overlay(Capsule().stroke(NovaTheme.surface, lineWidth: 1.5))
                        .offset(x: -12, y: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pestañas abiertas: \(model.tabCount)")

            if let url = model.currentURL, !model.isHome {
                ShareLink(item: url) { icon("square.and.arrow.up") }
                    .accessibilityLabel("Compartir página")
            } else {
                icon("square.and.arrow.up", enabled: false)
                    .accessibilityLabel("Compartir página")
            }
            Button(action: openSettings) { icon("slider.horizontal.3") }
                .accessibilityLabel("Configuración")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 15, y: 5)
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 5)
    }

    private func icon(_ name: String, enabled: Bool = true, tint: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(tint ?? (enabled ? Color.white.opacity(0.92) : Color.white.opacity(0.28)))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
