import SwiftUI

// MARK: - Maqueta del inicio (para ver cómo quedará el fondo)

/// Reloj, buscador y accesos dibujados a escala sobre el fondo, como se verán en el inicio.
struct HomeMockOverlay: View {
    let width: CGFloat

    var body: some View {
        let k = width / 393
        VStack(spacing: 20 * k) {
            HStack {
                HStack(spacing: 6 * k) {
                    NovaMark(size: 26 * k)
                    Text("Nova").font(.system(size: 16 * k, weight: .bold))
                }
                Spacer()
                Circle().fill(Color.white.opacity(0.16)).frame(width: 34 * k, height: 34 * k)
            }
            .padding(.top, 14 * k)

            Spacer(minLength: 0)

            Text("BUENAS NOCHES")
                .font(.system(size: 9.5 * k, weight: .semibold, design: .rounded))
                .tracking(1.8 * k)
                .padding(.horizontal, 12 * k).padding(.vertical, 6 * k)
                .background(Capsule().fill(Color.black.opacity(0.25)))
            Text("09:41")
                .font(.system(size: 88 * k, weight: .ultraLight))
                .monospacedDigit()
                .shadow(color: .black.opacity(0.35), radius: 10 * k, y: 3 * k)
            Text("Sábado  ·  31 de octubre")
                .font(.system(size: 14 * k, weight: .medium))
                .opacity(0.85)

            RoundedRectangle(cornerRadius: 20 * k, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: 20 * k, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(height: 52 * k)
                .padding(.top, 6 * k)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8 * k), count: 4), spacing: 14 * k) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16 * k, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 56 * k)
                }
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20 * k)
        .foregroundColor(.white)
        .allowsHitTesting(false)
    }
}

/// Miniatura con forma de iPhone del fondo ya ajustado.
struct BackgroundPhonePreview: View {
    let image: UIImage?
    let size: CGSize
    let tf: BGTransform
    let height: CGFloat
    var dim: Double = 0.35
    var blur: Double = 0

    var body: some View {
        let w = height * BGScreen.ratio
        ZStack {
            NovaBackground()
            if let image = image {
                BackgroundMediaLayer(image: image, videoURL: nil, size: size, tf: tf,
                                     blur: blur * Double(w / BGScreen.width))
                Color.black.opacity(dim)
                HomeMockOverlay(width: w)
            }
        }
        .frame(width: w, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NovaTheme.ink(0.25), lineWidth: 2))
        .shadow(color: NovaTheme.shadow(0.25), radius: 10, y: 4)
    }
}

// MARK: - Editor (arrastrar, zoom, girar) al estilo del editor de perfil de Discord

struct BackgroundEditorView: View {
    let draft: BGDraft
    var onApply: (BGTransform) -> Void
    var onCancel: () -> Void

    @State private var tf: BGTransform
    @State private var dragStart: (x: Double, y: Double)?
    @State private var zoomStart: Double?
    @State private var showMock = true
    @AppStorage("bgDim") private var dim = 0.35
    @AppStorage("bgBlur") private var blur = 0.0

    init(draft: BGDraft, onApply: @escaping (BGTransform) -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onApply = onApply
        self.onCancel = onCancel
        _tf = State(initialValue: draft.tf)
    }

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                GeometryReader { geo in
                    let availH = geo.size.height - 24
                    let availW = geo.size.width - 40
                    let fh = min(availH, availW / BGScreen.ratio)
                    let fw = fh * BGScreen.ratio
                    stage(width: fw, height: fh)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                controls
            }
        }
        .novaAppearance()
    }

    // MARK: Piezas

    private var header: some View {
        HStack {
            Text("Editar fondo")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(NovaTheme.text)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMock.toggle() }
                Haptics.select()
            } label: {
                Image(systemName: showMock ? "eye.fill" : "eye.slash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(showMock ? NovaTheme.accent : NovaTheme.dim)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(NovaTheme.surfaceHi))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(showMock ? "Ocultar vista previa del inicio" : "Mostrar vista previa del inicio")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func stage(width fw: CGFloat, height fh: CGFloat) -> some View {
        let container = CGSize(width: fw, height: fh)
        return ZStack {
            BackgroundMediaLayer(image: draft.image, videoURL: draft.videoURL, size: draft.size,
                                 tf: tf, blur: blur * Double(fw / BGScreen.width))
            Color.black.opacity(dim)
            if showMock { HomeMockOverlay(width: fw).transition(.opacity) }
        }
        .frame(width: fw, height: fh)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white, lineWidth: 3))
        .shadow(color: NovaTheme.shadow(0.35), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .gesture(
            DragGesture()
                .onChanged { v in
                    if dragStart == nil { dragStart = (tf.x, tf.y) }
                    var t = tf
                    t.x = (dragStart?.x ?? 0) + Double(v.translation.width / fw)
                    t.y = (dragStart?.y ?? 0) + Double(v.translation.height / fh)
                    tf = t.clamped(container: container, media: draft.size)
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { m in
                    if zoomStart == nil { zoomStart = tf.scale }
                    var t = tf
                    t.scale = (zoomStart ?? 1) * Double(m)
                    tf = t.clamped(container: container, media: draft.size)
                }
                .onEnded { _ in zoomStart = nil }
        )
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.15), value: tf.rot)
        .overlay(alignment: .bottom) {
            Text("Arrastra para mover · pellizca para hacer zoom")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(.bottom, 28)
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(NovaTheme.dim)
                Slider(value: Binding(get: { tf.scale },
                                      set: { setScale($0) }), in: 1...5)
                    .tint(NovaTheme.accent)
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(NovaTheme.dim)
                Button {
                    Haptics.tap()
                    var t = tf
                    t.rot = (t.rot + 1) % 4
                    tf = t.clamped(container: containerSize, media: draft.size)
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(NovaTheme.text)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(NovaTheme.surfaceHi))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Girar 90 grados")
            }

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { tf = BGTransform() }
                } label: {
                    Text("Restablecer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(NovaTheme.dim)
                        .padding(.horizontal, 6)
                }
                Spacer()
                Button(action: onCancel) {
                    Text("Cancelar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(NovaTheme.text)
                        .padding(.horizontal, 20)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.surfaceHi))
                }
                .buttonStyle(PressableStyle())
                Button { onApply(tf) } label: {
                    Text("Aplicar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accentGradient))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    /// Tamaño del recuadro del teléfono (misma proporción que la pantalla).
    private var containerSize: CGSize {
        let w = BGScreen.width
        return CGSize(width: w, height: w / BGScreen.ratio)
    }

    private func setScale(_ s: Double) {
        var t = tf
        t.scale = s
        tf = t.clamped(container: containerSize, media: draft.size)
    }
}
