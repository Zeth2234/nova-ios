import SwiftUI
import UIKit

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
    // Grafito azulado con acentos violeta/azul: contraste alto sin neón excesivo.
    static let bg        = Color(hex: 0x070A12)
    static let surface   = Color(hex: 0x0F1522)
    static let surfaceHi = Color(hex: 0x182030)
    static let stroke    = Color.white.opacity(0.085)
    static let accent    = Color(hex: 0x8D7CFF)
    static let accent2   = Color(hex: 0x57A7FF)
    static let dim       = Color.white.opacity(0.58)
    static let faint     = Color.white.opacity(0.36)
    static let good      = Color(hex: 0x47D5A1)
    static let warn      = Color(hex: 0xFFAA4D)
    static let danger    = Color(hex: 0xFF6B85)

    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Interacción

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Botón con respuesta táctil sutil (escala + opacidad) para toda la interfaz.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension View {
    /// Tarjeta oscura con borde fino, como las de Configuración de Nova.
    func novaCard(radius: CGFloat = 16) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(NovaTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
    }

    /// Superficie de cristal: material translúcido + tinte + borde con degradado + sombra.
    func novaGlass(radius: CGFloat = 18, shadow: Bool = true) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(NovaTheme.surface.opacity(0.80))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadow ? 0.30 : 0), radius: 14, y: 6)
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
            LinearGradient(colors: [Color(hex: 0x0D1322), NovaTheme.bg],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x49389B, opacity: 0.38), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color(hex: 0x543B70, opacity: 0.16), .clear],
                           center: UnitPoint(x: 1.0, y: 0.60), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Color(hex: 0x226A78, opacity: 0.20), .clear],
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
