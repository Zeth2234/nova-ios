import SwiftUI
import WebKit

final class BrowserWebViewHost: UIView {
    /// Todas las pestañas permanecen dentro de la jerarquía (la activa visible, las demás
    /// transparentes). Si un WKWebView sale de la ventana, iOS pausa su audio.
    func display(_ webViews: [WKWebView], active: WKWebView) {
        for old in subviews.compactMap({ $0 as? WKWebView }) where !webViews.contains(old) {
            old.removeFromSuperview()
        }
        for web in webViews {
            if web.superview !== self {
                web.translatesAutoresizingMaskIntoConstraints = false
                addSubview(web)
                NSLayoutConstraint.activate([
                    web.leadingAnchor.constraint(equalTo: leadingAnchor),
                    web.trailingAnchor.constraint(equalTo: trailingAnchor),
                    web.topAnchor.constraint(equalTo: topAnchor),
                    web.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
            }
            let isActive = web === active
            web.alpha = isActive ? 1 : 0
            web.isUserInteractionEnabled = isActive
            if isActive { bringSubviewToFront(web) }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webViews: [WKWebView]
    let active: WKWebView

    func makeUIView(context: Context) -> BrowserWebViewHost {
        let host = BrowserWebViewHost()
        host.backgroundColor = .clear
        host.display(webViews, active: active)
        return host
    }

    func updateUIView(_ uiView: BrowserWebViewHost, context: Context) {
        uiView.display(webViews, active: active)
    }
}

// MARK: - Barra superior (identidad del sitio + dirección + recarga)

struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @Binding var isEditing: Bool

    private let radius: CGFloat = 19

    private var tint: Color { model.isSecure ? NovaTheme.good : NovaTheme.warn }
    private var looksLikeURL: Bool {
        let t = model.omniText
        return t.contains(".") && !t.contains(" ")
    }

    var body: some View {
        HStack(spacing: 10) {
            field

            if isEditing {
                Button(action: cancel) {
                    Text("Cancelar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(NovaTheme.accent)
                }
                .buttonStyle(PressableStyle())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                newTabButton
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isEditing)
        .onChange(of: model.activeTabID) { _ in isEditing = false }
    }

    // MARK: Cápsula principal

    private var field: some View {
        HStack(spacing: 10) {
            if isEditing { editingContent } else { idleContent }
        }
        .padding(.leading, isEditing ? 15 : 6)
        .padding(.trailing, 7)
        .frame(height: 54)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(NovaTheme.surface.opacity(0.80))
            }
        )
        .overlay(alignment: .bottom) { progressLine }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isEditing ? (model.isPrivate ? PrivateTheme.accent : NovaTheme.accent).opacity(0.85)
                                        : (model.isPrivate ? PrivateTheme.accent.opacity(0.38) : Color.white.opacity(0.11)),
                              lineWidth: isEditing ? 1.4 : 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 14, y: 6)
    }

    // Estado normal: [icono del sitio] [dominio / estado] [recargar]
    private var idleContent: some View {
        HStack(spacing: 10) {
            siteMenu

            Button(action: startEditing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.host.isEmpty ? "Buscar o escribir una dirección" : model.host)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    statusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dirección: \(model.host). Toca para editar")

            reloadButton
        }
    }

    // Estado de edición: [lupa] [campo] [borrar]
    private var editingContent: some View {
        HStack(spacing: 10) {
            Image(systemName: looksLikeURL ? "globe" : "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(NovaTheme.dim)

            AddressField(text: $model.omniText,
                         isFocused: $isEditing,
                         placeholder: "Buscar o escribir una dirección",
                         onSubmit: submit)
                .frame(height: 40)

            if !model.omniText.isEmpty {
                Button { model.omniText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(NovaTheme.faint)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Borrar texto")
            }
        }
    }

    // MARK: Piezas

    private var statusLine: some View {
        Group {
            if model.isLoading {
                HStack(spacing: 5) {
                    Text("Cargando…")
                    Text("\(Int(min(max(model.progress, 0), 1) * 100))%")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(NovaTheme.accent2)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: model.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(model.isSecure ? "Conexión segura" : "Conexión no segura")
                        .font(.system(size: 11, weight: .medium))
                    if model.isPrivate {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(PrivateTheme.accent)
                        Text("Privada")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PrivateTheme.accent)
                    }
                    if model.activeTab.desktopMode {
                        Text("· Escritorio")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(NovaTheme.dim)
                    }
                }
                .foregroundColor(tint.opacity(0.95))
            }
        }
        .lineLimit(1)
    }

    /// Icono real del sitio. Al tocarlo: opciones de la página.
    private var siteMenu: some View {
        Menu {
            if let url = model.currentURL {
                ShareLink(item: url) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    Haptics.success()
                } label: {
                    Label("Copiar enlace", systemImage: "link")
                }
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("Abrir en Safari", systemImage: "safari")
                }
            }
            Button { model.toggleDesktop() } label: {
                Label(model.activeTab.desktopMode ? "Versión para móvil" : "Versión de ordenador",
                      systemImage: model.activeTab.desktopMode ? "iphone" : "desktopcomputer")
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                if let img = model.activeTab.faviconImage {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: model.isSecure ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .accessibilityLabel("Opciones del sitio")
    }

    private var reloadButton: some View {
        Button {
            Haptics.tap()
            model.reloadOrStop()
        } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.07))
                if model.isLoading {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 2)
                        .padding(2)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(model.progress, 0.04), 1)))
                        .stroke(NovaTheme.accentGradient,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }
                Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.88))
            }
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.2), value: model.progress)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(model.isLoading ? "Detener carga" : "Recargar página")
    }

    private var newTabButton: some View {
        Button {
            Haptics.tap()
            model.createTab(private: model.isPrivate)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .novaGlass(radius: radius)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Nueva pestaña")
    }

    /// Línea de progreso integrada en el borde inferior de la cápsula.
    private var progressLine: some View {
        GeometryReader { geo in
            if model.isLoading {
                Capsule()
                    .fill(NovaTheme.accentGradient)
                    .frame(width: max(16, geo.size.width * CGFloat(min(max(model.progress, 0.04), 1))),
                           height: 2.5)
                    .shadow(color: NovaTheme.accent.opacity(0.7), radius: 4)
                    .transition(.opacity)
            }
        }
        .frame(height: 2.5)
        .animation(.easeOut(duration: 0.22), value: model.progress)
        .animation(.easeInOut(duration: 0.2), value: model.isLoading)
        .allowsHitTesting(false)
    }

    // MARK: Acciones

    private func startEditing() {
        Haptics.tap()
        model.omniText = model.currentURL?.absoluteString ?? ""
        isEditing = true
    }

    private func cancel() {
        isEditing = false
        model.omniText = model.currentURL?.absoluteString ?? ""
    }

    private func submit() {
        let value = model.omniText
        isEditing = false
        model.load(value)
    }
}

// MARK: - Barra inferior flotante

struct BottomBar: View {
    @ObservedObject var model: BrowserModel
    var openSettings: () -> Void
    var openTabs: () -> Void
    var openEQ: () -> Void = {}
    var eqOn = false
    var newPrivateTab: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            NavButton(symbol: "chevron.left", label: "Atrás",
                      enabled: model.backEnabled, action: model.back)
            NavButton(symbol: "chevron.right", label: "Adelante",
                      enabled: model.canGoForward, action: model.forward)
            NavButton(symbol: model.isHome ? "house.fill" : "house", label: "Inicio",
                      active: model.isHome, action: model.goHome)
            tabsButton
            NavButton(symbol: "waveform", label: "Ecualizador",
                      active: eqOn, action: openEQ)
            moreMenu
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .novaGlass(radius: 24)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var tabsButton: some View {
        Button {
            Haptics.tap()
            openTabs()
        } label: {
            Text("\(min(model.tabCount, 99))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(model.isPrivate ? PrivateTheme.accent : Color.white.opacity(0.92))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(model.isPrivate ? PrivateTheme.accent : Color.white.opacity(0.9), lineWidth: 1.7)
                )
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Pestañas abiertas: \(model.tabCount)")
    }

    private var moreMenu: some View {
        Menu {
            if let url = model.currentURL, !model.isHome {
                ShareLink(item: url) {
                    Label("Compartir página", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    Haptics.success()
                } label: {
                    Label("Copiar enlace", systemImage: "link")
                }
            }
            if model.isPrivate {
                Button { model.leavePrivateMode() } label: {
                    Label("Salir del modo privado", systemImage: "eye")
                }
            } else {
                Button(action: newPrivateTab) {
                    Label("Nueva pestaña privada", systemImage: "eye.slash")
                }
            }
            Button(action: openSettings) {
                Label("Configuración", systemImage: "gearshape")
            }
        } label: {
            NavIcon(symbol: "ellipsis", enabled: true, active: false)
        }
        .accessibilityLabel("Más opciones")
    }
}

private struct NavIcon: View {
    let symbol: String
    let enabled: Bool
    let active: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(active ? NovaTheme.accent
                             : (enabled ? Color.white.opacity(0.92) : Color.white.opacity(0.26)))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if active {
                    Capsule()
                        .fill(NovaTheme.accent.opacity(0.14))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
            }
            .contentShape(Rectangle())
    }
}

private struct NavButton: View {
    let symbol: String
    let label: String
    var enabled = true
    var active = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            NavIcon(symbol: symbol, enabled: enabled, active: active)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
