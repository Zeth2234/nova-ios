import SwiftUI

/// Panel de gestión de pestañas: cuadrícula de tarjetas para cambiar, abrir y cerrar páginas.
/// Incluye un selector Normales / Privadas; las privadas piden Face ID si está activado.
struct TabSwitcherView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var privacy = PrivacyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCloseAll = false
    @State private var showPrivate: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(model: BrowserModel) {
        _model = ObservedObject(wrappedValue: model)
        _showPrivate = State(initialValue: model.activeTab.isPrivate)
    }

    private var accent: Color { showPrivate ? PrivateTheme.accent : NovaTheme.accent }
    private var visibleTabs: [BrowserTab] { model.modeTabs(showPrivate) }

    var body: some View {
        ZStack {
            if showPrivate {
                PrivateBackground().ignoresSafeArea()
            } else {
                NovaTheme.bg.ignoresSafeArea()
                RadialGradient(colors: [NovaTheme.accent.opacity(0.18), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                modePicker
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleTabs) { tab in
                            TabCard(tab: tab,
                                    isActive: tab.id == model.activeTabID,
                                    accent: accent,
                                    select: {
                                        Haptics.tap()
                                        model.selectTab(tab.id)
                                        dismiss()
                                    },
                                    close: {
                                        Haptics.tap()
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                            model.closeTab(tab.id)
                                        }
                                    })
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                        newTabCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: showPrivate)
        .confirmationDialog(showPrivate ? "¿Cerrar y borrar las pestañas privadas?" : "¿Cerrar todas las pestañas?",
                            isPresented: $confirmCloseAll, titleVisibility: .visible) {
            Button(showPrivate ? "Cerrar y borrar" : "Cerrar todas", role: .destructive) {
                model.closeAllTabs(private: showPrivate)
                if showPrivate { showPrivate = false } else { dismiss() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(showPrivate ? "Se eliminarán sus cookies y datos de sitios."
                             : "Nova abrirá una pestaña nueva en blanco.")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(showPrivate ? "Pestañas privadas" : "Pestañas")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                let count = visibleTabs.count
                Text(count == 1 ? "1 abierta" : "\(count) abiertas")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()

            if showPrivate ? !visibleTabs.isEmpty : visibleTabs.count > 1 {
                Menu {
                    Button(role: .destructive) {
                        confirmCloseAll = true
                    } label: {
                        Label(showPrivate ? "Cerrar y borrar todas" : "Cerrar todas las pestañas",
                              systemImage: "xmark.circle")
                    }
                } label: {
                    roundIcon("ellipsis", filled: false)
                }
                .accessibilityLabel("Más opciones")
            }

            Button {
                Haptics.tap()
                model.createTab(private: showPrivate)
                dismiss()
            } label: {
                roundIcon("plus", filled: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(showPrivate ? "Añadir pestaña privada" : "Añadir pestaña")

            Button { dismiss() } label: {
                roundIcon("xmark", filled: false)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar panel de pestañas")
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(NovaTheme.stroke).frame(height: 1) }
    }

    private func roundIcon(_ symbol: String, filled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(filled ? .white : NovaTheme.dim)
            .frame(width: 38, height: 38)
            .background(
                Circle().fill(filled
                              ? AnyShapeStyle(showPrivate
                                              ? AnyShapeStyle(PrivateTheme.accent)
                                              : AnyShapeStyle(NovaTheme.accentGradient))
                              : AnyShapeStyle(NovaTheme.surfaceHi))
            )
            .overlay(Circle().stroke(filled ? Color.clear : NovaTheme.stroke, lineWidth: 1))
    }

    // MARK: Selector Normales / Privadas

    private var modePicker: some View {
        HStack(spacing: 4) {
            segment(title: "Normales", count: model.modeTabs(false).count,
                    symbol: "square.on.square", selected: !showPrivate, tint: NovaTheme.accent) {
                showPrivate = false
            }
            segment(title: "Privadas", count: model.modeTabs(true).count,
                    symbol: "eye.slash.fill", selected: showPrivate, tint: PrivateTheme.accent) {
                guard !showPrivate else { return }
                privacy.requestPrivateAccess { ok in
                    if ok {
                        Haptics.select()
                        showPrivate = true
                    }
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(NovaTheme.surface))
        .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
    }

    private func segment(title: String, count: Int, symbol: String, selected: Bool,
                         tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(title) · \(count)")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selected ? .white : NovaTheme.dim)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(selected ? tint.opacity(0.28) : Color.clear))
            .overlay(Capsule().stroke(selected ? tint.opacity(0.7) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tarjeta "nueva pestaña"

    private var newTabCard: some View {
        Button {
            Haptics.tap()
            model.createTab(private: showPrivate)
            dismiss()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: showPrivate ? "eye.slash.fill" : "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(accent.opacity(0.14)))
                Text(showPrivate ? "Nueva pestaña privada" : "Nueva pestaña")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.surface.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Tarjeta de pestaña

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let accent: Color
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                TabFaviconView(tab: tab, isActive: isActive, accent: accent)
                Spacer(minLength: 12)
                Text(tab.isHome ? (tab.isPrivate ? "Nueva pestaña privada" : "Nueva pestaña") : tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if isActive {
                        Circle().fill(accent).frame(width: 5, height: 5)
                    }
                    Text(tab.isHome ? (tab.isPrivate ? "Navegación privada" : "Página de inicio") : tab.host)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive ? accent.opacity(0.95) : NovaTheme.dim)
                        .lineLimit(1)
                }
                .padding(.top, 3)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tab.isPrivate ? PrivateTheme.surface : (isActive ? NovaTheme.surfaceHi : NovaTheme.surface)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isActive ? accent.opacity(0.65) : NovaTheme.stroke,
                        lineWidth: isActive ? 1.5 : 1))
            .shadow(color: isActive ? accent.opacity(0.22) : .clear, radius: 12, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .padding(9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar pestaña \(tab.title)")
        }
    }
}

/// Muestra el favicon de cada web; solo recurre al icono genérico si la página
/// no publica una imagen que iOS pueda decodificar.
private struct TabFaviconView: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isActive ? accent.opacity(0.19) : NovaTheme.surfaceHi)
                .frame(width: 42, height: 42)

            if let favicon = tab.faviconImage {
                Image(uiImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            } else {
                Image(systemName: tab.isHome ? (tab.isPrivate ? "eye.slash.fill" : "house.fill") : "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(isActive ? accent : Color.white.opacity(0.78))
                    .frame(width: 42, height: 42)
            }

            if tab.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: NovaTheme.accent2))
                    .scaleEffect(0.55)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(NovaTheme.surfaceHi))
                    .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
                    .offset(x: 4, y: 4)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: tab.faviconImage != nil)
        .accessibilityLabel(tab.faviconImage == nil ? (tab.isHome ? "Inicio" : "Icono del sitio") : "Icono de \(tab.host)")
    }
}
