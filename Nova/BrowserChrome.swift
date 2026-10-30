import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Barra de direcciones

struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: model.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(model.isSecure ? NovaTheme.accent : Color.orange)

                ZStack(alignment: .leading) {
                    TextField("Busca o escribe una dirección", text: $model.addressText)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .tint(NovaTheme.accent)
                        .opacity(focused ? 1 : 0)
                        .onSubmit {
                            model.load(model.addressText)
                            focused = false
                        }
                    if !focused {
                        Text(model.host)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }

                Button(action: model.reloadOrStop) {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(NovaTheme.dim)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NovaTheme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? NovaTheme.accent.opacity(0.7) : NovaTheme.stroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { progressLine }
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private var progressLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(NovaTheme.accentGradient)
                .frame(width: geo.size.width * CGFloat(model.progress), height: 2)
                .opacity(model.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: model.progress)
        }
        .frame(height: 2)
    }
}

// MARK: - Barra inferior

struct BottomBar: View {
    @ObservedObject var model: BrowserModel
    var openSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: model.back) { icon("chevron.left", enabled: model.backEnabled) }
                .disabled(!model.backEnabled)
            Button(action: model.forward) { icon("chevron.right", enabled: model.canGoForward) }
                .disabled(!model.canGoForward)
            Button(action: model.goHome) {
                icon(model.isHome ? "house.fill" : "house", tint: model.isHome ? NovaTheme.accent : nil)
            }
            if let url = model.currentURL, !model.isHome {
                ShareLink(item: url) { icon("square.and.arrow.up") }
            } else {
                icon("square.and.arrow.up", enabled: false)
            }
            Button(action: openSettings) { icon("slider.horizontal.3") }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func icon(_ name: String, enabled: Bool = true, tint: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(tint ?? (enabled ? Color.white.opacity(0.92) : Color.white.opacity(0.28)))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
