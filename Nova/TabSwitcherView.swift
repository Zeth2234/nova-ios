import SwiftUI

/// Panel de gestión de pestañas: permite cambiar, abrir y cerrar páginas.
struct TabSwitcherView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmCloseAll = false

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            RadialGradient(colors: [NovaTheme.accent.opacity(0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 400)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tu espacio de navegación")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Cambia entre páginas o libera las que ya no necesitas.")
                                    .font(.system(size: 12))
                                    .foregroundColor(NovaTheme.dim)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 17)

                        LazyVStack(spacing: 9) {
                            ForEach(model.tabs) { tab in
                                TabRow(tab: tab,
                                       isActive: tab.id == model.activeTabID,
                                       select: {
                                           model.selectTab(tab.id)
                                           dismiss()
                                       },
                                       close: {
                                           withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                               model.closeTab(tab.id)
                                           }
                                       })
                            }
                        }

                        Button {
                            model.createTab()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(NovaTheme.accent)
                                    .frame(width: 42, height: 42)
                                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.accent.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Abrir nueva pestaña")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Empieza una página desde cero")
                                        .font(.system(size: 11))
                                        .foregroundColor(NovaTheme.dim)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(NovaTheme.dim)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(NovaTheme.surface.opacity(0.76)))
                            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(NovaTheme.accent.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 3)

                        if model.tabs.count > 1 {
                            Button(role: .destructive) {
                                confirmCloseAll = true
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "xmark.circle")
                                    Text("Cerrar todas las pestañas")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: 0xFF718B))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 18)
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

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NovaTheme.accentGradient)
                    .frame(width: 38, height: 38)
                Image(systemName: "square.on.square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Pestañas")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.white)
                Text("\(model.tabCount) abiertas")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
            }
            Spacer()
            Button {
                model.createTab()
                dismiss()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Añadir pestaña")
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(NovaTheme.surfaceHi))
                    .overlay(Circle().stroke(NovaTheme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar panel de pestañas")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(NovaTheme.bg.opacity(0.95))
        .overlay(alignment: .bottom) { Rectangle().fill(NovaTheme.stroke).frame(height: 1) }
    }
}

private struct TabRow: View {
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isActive ? NovaTheme.accent.opacity(0.19) : NovaTheme.surfaceHi)
                            .frame(width: 43, height: 43)
                        Image(systemName: tab.isHome ? "house.fill" : "globe")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(isActive ? NovaTheme.accent : Color.white.opacity(0.78))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(tab.isHome ? "Página de inicio" : tab.host)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(NovaTheme.dim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if isActive {
                        Text("ACTIVA")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundColor(NovaTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(NovaTheme.accent.opacity(0.13)))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 31, height: 31)
                    .background(Circle().fill(Color.white.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar pestaña \(tab.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isActive ? NovaTheme.surfaceHi.opacity(0.95) : NovaTheme.surface.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(isActive ? NovaTheme.accent.opacity(0.48) : NovaTheme.stroke, lineWidth: 1))
    }
}
