import SwiftUI

struct Shortcut: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let symbol: String?
    let glyph: String?
    let color: Color
}

private let shortcuts: [Shortcut] = [
    Shortcut(name: "Twitch",   url: "https://www.twitch.tv",     symbol: "play.tv.fill",         glyph: nil, color: Color(hex: 0x9146FF)),
    Shortcut(name: "X",        url: "https://x.com",             symbol: nil,                    glyph: "𝕏", color: .white),
    Shortcut(name: "WhatsApp", url: "https://web.whatsapp.com",  symbol: "message.fill",         glyph: nil, color: Color(hex: 0x25D366)),
    Shortcut(name: "Discord",  url: "https://discord.com/app",   symbol: "gamecontroller.fill",  glyph: nil, color: Color(hex: 0x5865F2)),
    Shortcut(name: "Spotify",  url: "https://open.spotify.com",  symbol: "waveform",             glyph: nil, color: Color(hex: 0x1ED760)),
    Shortcut(name: "YouTube",  url: "https://www.youtube.com",   symbol: "play.rectangle.fill",  glyph: nil, color: Color(hex: 0xFF2D2D)),
    Shortcut(name: "Gemini",   url: "https://gemini.google.com", symbol: "sparkle",              glyph: nil, color: Color(hex: 0x6EA8FF)),
    Shortcut(name: "Gmail",    url: "https://mail.google.com",   symbol: "envelope.fill",        glyph: nil, color: Color(hex: 0xEA4335))
]

// MARK: - Barra superior de inicio

struct HomeTopBar: View {
    var openSettings: () -> Void
    var body: some View {
        HStack {
            HStack(spacing: 9) {
                NovaMark(size: 30)
                Text("Nova")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Button {
                Haptics.tap()
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
                    .novaGlass(radius: 14, shadow: false)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Configuración")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

// MARK: - Reloj

struct ClockView: View {
    private static let hourFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH"
        return f
    }()
    private static let minuteFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "mm"
        return f
    }()
    private static let weekdayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE"
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d 'de' MMMM"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let part = Self.dayPart(for: ctx.date)
            VStack(spacing: 10) {
                // Saludo en cápsula de cristal con icono según la hora
                HStack(spacing: 7) {
                    Image(systemName: part.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(part.tint)
                    Text(part.text.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.0)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().fill(Color.black.opacity(0.18)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))

                // Hora: trazo ultrafino, dígitos tabulares y dos puntos con acento
                (Text(Self.hourFmt.string(from: ctx.date))
                    .foregroundColor(.white)
                 + Text(":")
                    .foregroundColor(NovaTheme.accent2.opacity(0.9))
                 + Text(Self.minuteFmt.string(from: ctx.date))
                    .foregroundColor(.white))
                    .font(.system(size: 92, weight: .ultraLight))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 4)

                // Fecha: día de la semana destacado + resto en tono suave
                (Text(Self.capitalized(Self.weekdayFmt.string(from: ctx.date)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                 + Text("  ·  ")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.35))
                 + Text(Self.dayFmt.string(from: ctx.date))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.75)))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(part.text), son las \(Self.hourFmt.string(from: ctx.date)) y \(Self.minuteFmt.string(from: ctx.date))")
        }
    }

    private static func dayPart(for date: Date) -> (text: String, symbol: String, tint: Color) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<13: return ("Buenos días", "sunrise.fill", Color(hex: 0xFFB45C))
        case 13..<20: return ("Buenas tardes", "sun.max.fill", Color(hex: 0xFFC94D))
        default: return ("Buenas noches", "moon.stars.fill", NovaTheme.accent2)
        }
    }

    private static func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}

// MARK: - Inicio

struct HomeView: View {
    @ObservedObject var model: BrowserModel
    @AppStorage("showShortcuts") private var showShortcuts = true
    @AppStorage("engine") private var engineRaw = SearchEngine.google.rawValue
    @State private var query = ""
    @FocusState private var focused: Bool

    private var engine: SearchEngine { SearchEngine(rawValue: engineRaw) ?? .google }

    var body: some View {
        VStack(spacing: 34) {
            Spacer()
            ClockView()
            searchPill
            if showShortcuts { shortcutGrid }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture { focused = false }
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SearchEngine.allCases) { e in
                    Button {
                        engineRaw = e.rawValue
                        Haptics.select()
                    } label: {
                        if e == engine {
                            Label(e.name, systemImage: "checkmark")
                        } else {
                            Text(e.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    EngineBadge(engine: engine, size: 32)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.dim)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.07)))
            }
            .accessibilityLabel("Buscador: \(engine.name)")

            TextField("", text: $query,
                      prompt: Text("Busca con \(engine.name) o escribe una dirección")
                        .foregroundColor(Color.white.opacity(0.45)))
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .tint(NovaTheme.accent)
                .onSubmit(go)

            Button(action: go) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(query.isEmpty ? AnyShapeStyle(Color.white.opacity(0.08))
                                                            : AnyShapeStyle(NovaTheme.accentGradient)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Buscar")
        }
        .padding(.leading, 8)
        .padding(.trailing, 9)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(NovaTheme.surface.opacity(0.82))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(focused ? NovaTheme.accent.opacity(0.8) : Color.white.opacity(0.11),
                          lineWidth: focused ? 1.4 : 1))
        .shadow(color: Color.black.opacity(0.30), radius: 18, y: 8)
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.easeOut(duration: 0.2), value: query.isEmpty)
    }

    private var shortcutGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACCESOS RÁPIDOS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(NovaTheme.faint)
                .padding(.leading, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 20) {
                ForEach(shortcuts) { s in
                    Button {
                        Haptics.tap()
                        focused = false
                        model.load(s.url)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(LinearGradient(colors: [s.color.opacity(0.24), s.color.opacity(0.07)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                                if let symbol = s.symbol {
                                    Image(systemName: symbol)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundColor(s.color)
                                } else if let glyph = s.glyph {
                                    Text(glyph)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(s.color)
                                }
                            }
                            .frame(width: 60, height: 60)
                            Text(s.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(s.name)
                }
            }
        }
    }

    private func go() {
        let q = query
        query = ""
        focused = false
        model.load(q)
    }
}
