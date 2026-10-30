import SwiftUI
import UIKit
import ImageIO

// MARK: - Almacén del fondo personalizado (foto o GIF)

/// Guarda el archivo original en Application Support y mantiene una versión
/// reducida en memoria. Los GIFs se convierten en una animación optimizada.
final class HomeBackgroundStore: ObservableObject {
    static let shared = HomeBackgroundStore()

    @Published private(set) var image: UIImage?
    @Published private(set) var isAnimated = false
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?

    private static let maxStaticPixels = 2200
    private static let maxGIFPixels = 640
    private static let maxGIFFrames = 40

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("home_background.dat")
    }

    private init() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.decode(data)
            DispatchQueue.main.async {
                if let result = result {
                    self.image = result.image
                    self.isAnimated = result.animated
                }
            }
        }
    }

    /// Procesa y guarda una imagen elegida por el usuario.
    func set(data: Data) {
        isProcessing = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.decode(data)
            if result != nil { try? data.write(to: Self.fileURL, options: .atomic) }
            DispatchQueue.main.async {
                self.isProcessing = false
                if let result = result {
                    self.image = result.image
                    self.isAnimated = result.animated
                    Haptics.success()
                } else {
                    self.errorMessage = "No se pudo leer ese archivo. Prueba con otra foto o GIF."
                }
            }
        }
    }

    func fail(_ message: String) {
        isProcessing = false
        errorMessage = message
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        image = nil
        isAnimated = false
        errorMessage = nil
    }

    // MARK: Decodificación

    private static func decode(_ data: Data) -> (image: UIImage, animated: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        let isGIF = data.prefix(4) == Data("GIF8".utf8)

        if isGIF && count > 1 {
            let step = max(1, Int((Double(count) / Double(maxGIFFrames)).rounded(.up)))
            var frames: [UIImage] = []
            var total = 0.0
            for index in 0..<count {
                total += frameDelay(source, index)
                if index % step == 0, let cg = thumbnail(source, index: index, maxPixel: maxGIFPixels) {
                    frames.append(UIImage(cgImage: cg))
                }
            }
            guard !frames.isEmpty,
                  let animated = UIImage.animatedImage(with: frames, duration: max(total, 0.5)) else { return nil }
            return (animated, true)
        }

        guard let cg = thumbnail(source, index: 0, maxPixel: maxStaticPixels) else { return nil }
        return (UIImage(cgImage: cg), false)
    }

    private static func thumbnail(_ source: CGImageSource, index: Int, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
    }

    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        return delay < 0.011 ? 0.1 : delay
    }
}

// MARK: - Vista UIKit que anima GIFs y rellena el espacio (aspect fill)

private struct FillImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.image = image
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}

// MARK: - Fondo del inicio

struct HomeBackgroundView: View {
    @ObservedObject private var store = HomeBackgroundStore.shared
    @AppStorage("bgDim") private var dim = 0.35
    @AppStorage("bgBlur") private var blur = 0.0

    var body: some View {
        ZStack {
            if let image = store.image {
                Color.clear
                    .overlay(
                        FillImageView(image: image)
                            .scaleEffect(blur > 0 ? 1.1 : 1)
                            .blur(radius: CGFloat(blur))
                    )
                    .clipped()
                Color.black.opacity(dim)
                LinearGradient(colors: [Color.black.opacity(0.30), .clear, Color.black.opacity(0.40)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}
