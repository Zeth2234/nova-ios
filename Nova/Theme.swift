import SwiftUI

// MARK: - Paleta Nova

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum NovaTheme {
    static let bg        = Color(hex: 0x07071A)
    static let surface   = Color(hex: 0x10101F)
    static let surfaceHi = Color(hex: 0x1A1A2E)
    static let stroke    = Color.white.opacity(0.09)
    static let accent    = Color(hex: 0x8B6CFF)
    static let accent2   = Color(hex: 0x5B8CFF)
    static let dim       = Color.white.opacity(0.55)
    static let good      = Color(hex: 0x3DDC97)

    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    /// Tarjeta oscura con borde fino, como las de Configuración de Nova.
    func novaCard(radius: CGFloat = 16) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(NovaTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Logo

struct NShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct NovaMark: View {
    var size: CGFloat = 30
    var body: some View {
        NShape()
            .stroke(NovaTheme.accentGradient,
                    style: StrokeStyle(lineWidth: size * 0.2, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.58, height: size * 0.58)
            .frame(width: size, height: size)
            .shadow(color: NovaTheme.accent.opacity(0.55), radius: size * 0.25)
    }
}

// MARK: - Fondo espacial

struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 42
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / 2147483648.0
            }
            for _ in 0..<90 {
                let x = next() * Double(size.width)
                let y = next() * Double(size.height)
                let r = 0.8 + next() * 1.1
                let o = 0.10 + next() * 0.35
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color.white.opacity(o)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct NovaBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A0A22), Color(hex: 0x07071A)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x4B2FB8, opacity: 0.70), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color(hex: 0x8A3C7E, opacity: 0.38), .clear],
                           center: UnitPoint(x: 1.0, y: 0.60), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(hex: 0x1E7F8F, opacity: 0.40), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 440)
            StarField()
        }
    }
}

// MARK: - Buscadores

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckduckgo, bing, brave
    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        }
    }
    var searchPrefix: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        case .bing: return "https://www.bing.com/search?q="
        case .brave: return "https://search.brave.com/search?q="
        }
    }
    var letter: String {
        switch self {
        case .google: return "G"
        case .duckduckgo: return "D"
        case .bing: return "B"
        case .brave: return "Br"
        }
    }
    var letterColor: Color {
        switch self {
        case .google: return Color(hex: 0x4285F4)
        case .duckduckgo: return Color(hex: 0xDE5833)
        case .bing: return Color(hex: 0x008373)
        case .brave: return Color(hex: 0xFB542B)
        }
    }
    static var current: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .google
    }
}

struct EngineBadge: View {
    let engine: SearchEngine
    var size: CGFloat = 30
    var body: some View {
        Text(engine.letter)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundColor(engine.letterColor)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Color.white))
    }
}
