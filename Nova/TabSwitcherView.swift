import SwiftUI

/// Panel de gestión de pestañas: cuadrícula de tarjetas para cambiar, abrir y cerrar páginas.
struct TabSwitcherView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCloseAll = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [NovaTheme.accent.opacity(0.18), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.tabs) { tab in
                            TabCard(tab: tab,
                                    isActive: tab.id == model.activeTabID,
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
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("¿Cerrar todas las pestañas?", isPresented: $confirmCloseAll, titleVisibility: .visible) {
            Button("Cerrar todas", role: .destructive) {
                model.closeAllTabs()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Nova abrirá una pestaña nueva en blanco.")
        }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pestañas")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Text(model.tabCount == 1 ? "1 abierta" : "\(model.tabCount) abiertas")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()

            if model.tabs.count > 1 {
                Menu {
                    Button(role: .destructive) {
                        confirmCloseAll = true
                    } label: {
                        Label("Cerrar todas las pestañas", systemImage: "xmark.circle")
                    }
                } label: {
                    roundIcon("ellipsis", filled: false)
                }
                .accessibilityLabel("Más opciones")
            }

            Button {
                Haptics.tap()
                model.createTab()
                dismiss()
            } label: {
                roundIcon("plus", filled: true)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Añadir pestaña")

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
                Circle().fill(filled ? AnyShapeStyle(NovaTheme.accentGradient)
                                     : AnyShapeStyle(NovaTheme.surfaceHi))
            )
            .overlay(Circle().stroke(filled ? Color.clear : NovaTheme.stroke, lineWidth: 1))
    }

    // MARK: Tarjeta "nueva pestaña"

    private var newTabCard: some View {
        Button {
            Haptics.tap()
            model.createTab()
            dismiss()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(NovaTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NovaTheme.accent.opacity(0.14)))
                Text("Nueva pestaña")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, minHeight: 124)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.surface.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NovaTheme.accent.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Tarjeta de pestaña

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                TabFaviconView(tab: tab, isActive: isActive)
                Spacer(minLength: 12)
                Text(tab.isHome ? "Nueva pestaña" : tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if isActive {
                        Circle().fill(NovaTheme.accent).frame(width: 5, height: 5)
                    }
                    Text(tab.isHome ? "Página de inicio" : tab.host)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isActive ? NovaTheme.accent.opacity(0.95) : NovaTheme.dim)
                        .lineLimit(1)
                }
                .padding(.top, 3)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isActive ? NovaTheme.surfaceHi : NovaTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isActive ? NovaTheme.accent.opacity(0.65) : NovaTheme.stroke,
                        lineWidth: isActive ? 1.5 : 1))
            .shadow(color: isActive ? NovaTheme.accent.opacity(0.22) : .clear, radius: 12, y: 4)
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isActive ? NovaTheme.accent.opacity(0.19) : NovaTheme.surfaceHi)
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
                Image(systemName: tab.isHome ? "house.fill" : "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(isActive ? NovaTheme.accent : Color.white.opacity(0.78))
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
