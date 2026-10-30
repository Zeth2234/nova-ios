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

// MARK: - Apariencia (Sistema / Claro / Oscuro)

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    /// nil = seguir el ajuste del sistema.
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var uiStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    static var current: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    /// Aplica el modo a todas las ventanas (teclado, menús, alertas y páginas web incluidos).
    static func applyToWindows(_ mode: AppearanceMode) {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.overrideUserInterfaceStyle = mode.uiStyle }
        }
    }
}

/// Aplica el tema elegido en Configuración. Se pone en la raíz de la app y de cada hoja.
struct NovaAppearanceModifier: ViewModifier {
    @AppStorage("appearance") private var raw = AppearanceMode.system.rawValue
    private var mode: AppearanceMode { AppearanceMode(rawValue: raw) ?? .system }

    func body(content: Content) -> some View {
        // No se usa preferredColorScheme: al volver a «Sistema» (nil) SwiftUI deja pegado el
        // último tema en las hojas ya abiertas. El estilo de la ventana sí vuelve a seguir al sistema.
        content
            .onAppear {
                AppearanceMode.applyToWindows(mode)
                DispatchQueue.main.async { AppearanceMode.applyToWindows(mode) }
            }
            .onChange(of: raw) { _ in AppearanceMode.applyToWindows(mode) }
    }
}

extension View {
    func novaAppearance() -> some View { modifier(NovaAppearanceModifier()) }
}

// MARK: - Colores adaptables

extension UIColor {
    static func nova(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
    convenience init(hex: UInt32, opacity: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(opacity))
    }
}

extension Color {
    /// Color que cambia solo entre tema claro y oscuro.
    static func nova(light: Color, dark: Color) -> Color {
        Color(UIColor.nova(light: UIColor(light), dark: UIColor(dark)))
    }
}

enum NovaTheme {
    // Tinta: blanco en oscuro, azul noche en claro (texto, bordes y rellenos sutiles).
    private static let lightInk: UInt32 = 0x0E1424

    static func uiInk(_ o: Double) -> UIColor {
        .nova(light: UIColor(hex: lightInk, opacity: min(1, o * 1.05)),
              dark: UIColor.white.withAlphaComponent(o))
    }
    /// Texto/relleno/borde que se invierte con el tema. `ink(1)` = texto principal.
    static func ink(_ o: Double) -> Color { Color(uiInk(o)) }

    static let uiText = uiInk(1)
    static let text = Color(uiText)

    // Oscuro: grafito azulado con acentos violeta/azul. Claro: blanco azulado limpio.
    static let uiBg = UIColor.nova(light: UIColor(hex: 0xF2F4FA), dark: UIColor(hex: 0x070A12))
    static let bg        = Color(uiBg)
    static let surface   = Color.nova(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x0F1522))
    static let surfaceHi = Color.nova(light: Color(hex: 0xE7EBF5), dark: Color(hex: 0x182030))
    static let stroke    = Color.nova(light: Color(hex: lightInk, opacity: 0.10), dark: Color.white.opacity(0.085))
    static let accent    = Color.nova(light: Color(hex: 0x6A55E6), dark: Color(hex: 0x8D7CFF))
    static let accent2   = Color.nova(light: Color(hex: 0x2A7FE0), dark: Color(hex: 0x57A7FF))
    static let dim       = Color.nova(light: Color(hex: lightInk, opacity: 0.62), dark: Color.white.opacity(0.58))
    static let faint     = Color.nova(light: Color(hex: lightInk, opacity: 0.44), dark: Color.white.opacity(0.36))
    static let good      = Color.nova(light: Color(hex: 0x12A06F), dark: Color(hex: 0x47D5A1))
    static let warn      = Color.nova(light: Color(hex: 0xD97B10), dark: Color(hex: 0xFFAA4D))
    static let danger    = Color.nova(light: Color(hex: 0xE03A5A), dark: Color(hex: 0xFF6B85))

    /// Sombra suave: más ligera en tema claro.
    static func shadow(_ dark: Double) -> Color {
        Color.nova(light: Color.black.opacity(dark * 0.32), dark: Color.black.opacity(dark))
    }

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
    /// Tarjeta con borde fino, como las de Configuración de Nova.
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
                        LinearGradient(colors: [NovaTheme.ink(0.16), NovaTheme.ink(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: NovaTheme.shadow(shadow ? 0.30 : 0), radius: 14, y: 6)
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(colors: [Color(hex: 0x0D1322), Color(hex: 0x070A12)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x49389B, opacity: 0.38), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(hex: 0x543B70, opacity: 0.16), .clear],
                               center: UnitPoint(x: 1.0, y: 0.60), startRadius: 0, endRadius: 380)
                RadialGradient(colors: [Color(hex: 0x226A78, opacity: 0.20), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 440)
                StarField()
            } else {
                LinearGradient(colors: [Color(hex: 0xF8F9FE), Color(hex: 0xEDF0F9)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x8D7CFF, opacity: 0.22), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 560)
                RadialGradient(colors: [Color(hex: 0xC9A6F5, opacity: 0.14), .clear],
                               center: UnitPoint(x: 1.0, y: 0.60), startRadius: 0, endRadius: 380)
                RadialGradient(colors: [Color(hex: 0x57C2FF, opacity: 0.20), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 440)
            }
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
