import SwiftUI
import UIKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Ajuste del fondo (zoom, posición y giro)

/// Cómo se coloca el fondo dentro de la pantalla. Las posiciones son relativas al
/// tamaño de la pantalla, así que el editor y el inicio real se ven igual.
struct BGTransform: Codable, Equatable {
    var scale: Double = 1      // 1 = rellena la pantalla
    var x: Double = 0          // desplazamiento horizontal (fracción del ancho)
    var y: Double = 0          // desplazamiento vertical (fracción del alto)
    var rot: Int = 0           // giros de 90° en sentido horario (0...3)

    /// Evita que se vean bordes vacíos: el medio siempre cubre toda la pantalla.
    func clamped(container: CGSize, media: CGSize) -> BGTransform {
        var t = self
        t.scale = min(max(t.scale, 1), 5)
        let l = BGLayout(container: container, media: media, tf: t)
        t.x = min(max(t.x, -l.maxX), l.maxX)
        t.y = min(max(t.y, -l.maxY), l.maxY)
        return t
    }
}

struct BGLayout {
    let mediaW: CGFloat
    let mediaH: CGFloat
    let maxX: Double
    let maxY: Double

    init(container: CGSize, media: CGSize, tf: BGTransform) {
        let cw = max(container.width, 1), ch = max(container.height, 1)
        let mw = max(media.width, 1), mh = max(media.height, 1)
        let odd = tf.rot % 2 != 0
        let rw = odd ? mh : mw, rh = odd ? mw : mh
        let s = max(cw / rw, ch / rh)
        mediaW = mw * s
        mediaH = mh * s
        let dispW = rw * s, dispH = rh * s
        maxX = Double(max(0, (dispW * CGFloat(tf.scale) - cw) / 2) / cw)
        maxY = Double(max(0, (dispH * CGFloat(tf.scale) - ch) / 2) / ch)
    }
}

enum BGScreen {
    /// Proporción ancho/alto de la pantalla del iPhone (modo vertical).
    static var ratio: CGFloat {
        let b = UIScreen.main.bounds.size
        let w = min(b.width, b.height), h = max(b.width, b.height)
        return w / h
    }
    static var width: CGFloat { min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) }
}

/// Fondo en preparación: se muestra en el editor y solo se guarda al pulsar «Aplicar».
struct BGDraft: Identifiable {
    enum Source { case data(Data), video(URL), existing }
    let id = UUID()
    let image: UIImage
    let size: CGSize
    let videoURL: URL?
    let source: Source
    var tf: BGTransform
}

/// Vídeo elegido en la fototeca (se copia a un archivo temporal propio).
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("nova-pick-\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

// MARK: - Almacén del fondo personalizado (foto, GIF o vídeo)

/// Guarda el archivo original en Application Support y mantiene una versión
/// reducida en memoria. Los GIFs se convierten en una animación optimizada y los
/// vídeos se reproducen en bucle y sin sonido.
final class HomeBackgroundStore: ObservableObject {
    static let shared = HomeBackgroundStore()

    /// Imagen mostrada (en vídeos, el primer fotograma).
    @Published private(set) var image: UIImage?
    @Published private(set) var isAnimated = false
    @Published private(set) var videoURL: URL?
    @Published private(set) var mediaSize: CGSize = .zero
    @Published private(set) var transform = BGTransform()
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?

    private static let maxStaticPixels = 2200
    private static let maxGIFPixels = 720
    private static let maxGIFFrames = 40
    private static let tfKey = "bgTransform"
    private static let videoKey = "bgVideoFile"

    private static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var fileURL: URL { supportDir.appendingPathComponent("home_background.dat") }
    private static var savedVideoURL: URL? {
        guard let name = UserDefaults.standard.string(forKey: videoKey) else { return nil }
        let url = supportDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.tfKey),
           let t = try? JSONDecoder().decode(BGTransform.self, from: data) {
            transform = t
        }
        if let video = Self.savedVideoURL {
            DispatchQueue.global(qos: .userInitiated).async {
                let poster = Self.poster(for: video)
                DispatchQueue.main.async {
                    if let poster = poster {
                        self.image = poster
                        self.mediaSize = poster.size
                        self.videoURL = video
                        self.isAnimated = true
                    }
                }
            }
        } else if let data = try? Data(contentsOf: Self.fileURL) {
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.decode(data)
                DispatchQueue.main.async {
                    if let result = result {
                        self.image = result.image
                        self.mediaSize = result.image.size
                        self.isAnimated = result.animated
                    }
                }
            }
        }
    }

    // MARK: Borradores y guardado

    /// Prepara una foto o GIF para editarla.
    func makeDraft(data: Data, completion: @escaping (BGDraft?) -> Void) {
        beginWork()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.decode(data)
            DispatchQueue.main.async {
                self.endWork(failed: result == nil, message: "No se pudo leer ese archivo. Prueba con otra foto, GIF o vídeo.")
                completion(result.map {
                    BGDraft(image: $0.image, size: $0.image.size, videoURL: nil, source: .data(data), tf: BGTransform())
                })
            }
        }
    }

    /// Prepara un vídeo para editarlo.
    func makeDraft(movie url: URL, completion: @escaping (BGDraft?) -> Void) {
        beginWork()
        DispatchQueue.global(qos: .userInitiated).async {
            let poster = Self.poster(for: url)
            DispatchQueue.main.async {
                self.endWork(failed: poster == nil, message: "No se pudo abrir ese vídeo.")
                completion(poster.map {
                    BGDraft(image: $0, size: $0.size, videoURL: url, source: .video(url), tf: BGTransform())
                })
            }
        }
    }

    /// Borrador del fondo actual, para reajustarlo sin volver a elegirlo.
    func currentDraft() -> BGDraft? {
        guard let image = image else { return nil }
        return BGDraft(image: image, size: mediaSize == .zero ? image.size : mediaSize,
                       videoURL: videoURL, source: .existing, tf: transform)
    }

    func commit(_ draft: BGDraft, transform t: BGTransform) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch draft.source {
            case .data(let data):
                Self.removeVideoFile()
                try? data.write(to: Self.fileURL, options: .atomic)
            case .video(let url):
                try? FileManager.default.removeItem(at: Self.fileURL)
                Self.removeVideoFile()
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let name = "home_background_video.\(ext)"
                let dst = Self.supportDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dst)
                if (try? FileManager.default.copyItem(at: url, to: dst)) != nil {
                    UserDefaults.standard.set(name, forKey: Self.videoKey)
                }
            case .existing:
                break
            }
            DispatchQueue.main.async {
                var video: URL? = nil
                if case .video = draft.source { video = Self.savedVideoURL }
                else if case .existing = draft.source { video = self.videoURL }
                self.image = draft.image
                self.mediaSize = draft.size
                self.videoURL = video
                self.isAnimated = draft.image.images != nil || video != nil
                self.setTransform(t)
                self.errorMessage = nil
                Haptics.success()
            }
        }
    }

    private func setTransform(_ t: BGTransform) {
        transform = t
        if let data = try? JSONEncoder().encode(t) { UserDefaults.standard.set(data, forKey: Self.tfKey) }
    }

    private func beginWork() { isProcessing = true; errorMessage = nil }
    private func endWork(failed: Bool, message: String) {
        isProcessing = false
        if failed { errorMessage = message }
    }

    func fail(_ message: String) {
        isProcessing = false
        errorMessage = message
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        Self.removeVideoFile()
        UserDefaults.standard.removeObject(forKey: Self.tfKey)
        image = nil
        videoURL = nil
        mediaSize = .zero
        transform = BGTransform()
        isAnimated = false
        errorMessage = nil
    }

    private static func removeVideoFile() {
        if let url = savedVideoURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: videoKey)
    }

    private static func poster(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1600, height: 1600)
        guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
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

// MARK: - Superficie que muestra la imagen/GIF o reproduce el vídeo

private final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class MediaHostView: UIView {
    private let imageView = UIImageView()
    private let playerView = PlayerLayerView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        for v in [imageView, playerView] as [UIView] {
            v.frame = bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(v)
        }
        playerView.playerLayer.videoGravity = .resize
        playerView.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(image: UIImage, videoURL: URL?, playing: Bool) {
        if imageView.image !== image { imageView.image = image }
        if videoURL != currentURL {
            teardown()
            currentURL = videoURL
            if let url = videoURL {
                let q = AVQueuePlayer()
                q.isMuted = true
                q.allowsExternalPlayback = false
                q.preventsDisplaySleepDuringVideoPlayback = false
                looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
                playerView.playerLayer.player = q
                playerView.isHidden = false
                player = q
            }
        }
        if playing { player?.play() } else { player?.pause() }
    }

    func teardown() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerView.playerLayer.player = nil
        playerView.isHidden = true
        player = nil
        currentURL = nil
    }
}

struct MediaSurface: UIViewRepresentable {
    let image: UIImage
    let videoURL: URL?
    var playing: Bool = true

    func makeUIView(context: Context) -> MediaHostView {
        let v = MediaHostView()
        v.configure(image: image, videoURL: videoURL, playing: playing)
        return v
    }
    func updateUIView(_ v: MediaHostView, context: Context) {
        v.configure(image: image, videoURL: videoURL, playing: playing)
    }
    static func dismantleUIView(_ v: MediaHostView, coordinator: ()) { v.teardown() }
}

/// Dibuja el fondo con el ajuste elegido (zoom, posición y giro) dentro de su contenedor.
struct BackgroundMediaLayer: View {
    let image: UIImage
    let videoURL: URL?
    let size: CGSize
    let tf: BGTransform
    var blur: Double = 0
    var playing: Bool = true

    var body: some View {
        GeometryReader { g in
            let l = BGLayout(container: g.size, media: size == .zero ? image.size : size, tf: tf)
            MediaSurface(image: image, videoURL: videoURL, playing: playing)
                .frame(width: l.mediaW, height: l.mediaH)
                .rotationEffect(.degrees(Double(tf.rot) * 90))
                .scaleEffect(CGFloat(tf.scale) * (blur > 0 ? 1.1 : 1))
                .blur(radius: CGFloat(blur))
                .position(x: g.size.width / 2 + CGFloat(tf.x) * g.size.width,
                          y: g.size.height / 2 + CGFloat(tf.y) * g.size.height)
        }
        .clipped()
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
                BackgroundMediaLayer(image: image, videoURL: store.videoURL, size: store.mediaSize,
                                     tf: store.transform, blur: blur)
                Color.black.opacity(dim)
                LinearGradient(colors: [Color.black.opacity(0.30), .clear, Color.black.opacity(0.40)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
    }
}
