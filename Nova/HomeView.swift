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
            HStack(spacing: 8) {
                NovaMark(size: 30)
                Text("Nova")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Button(action: openSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(NovaTheme.accentGradient))
                    Text("Personalizar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().stroke(NovaTheme.accent.opacity(0.55), lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

// MARK: - Reloj

struct ClockView: View {
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE, d 'de' MMMM"
        return f
    }()

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            VStack(spacing: 6) {
                Text(Self.timeFmt.string(from: ctx.date))
                    .font(.system(size: 64, weight: .thin))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Self.capitalized(Self.dateFmt.string(from: ctx.date)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
            }
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
        VStack(spacing: 30) {
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
                    Button(e.name) { engineRaw = e.rawValue }
                }
            } label: {
                HStack(spacing: 5) {
                    EngineBadge(engine: engine, size: 30)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NovaTheme.dim)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
            }

            TextField("", text: $query,
                      prompt: Text("Busca con \(engine.name) o escribe una dirección")
                        .foregroundColor(Color.white.opacity(0.5)))
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .tint(NovaTheme.accent)
                .onSubmit(go)

            Button(action: go) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(NovaTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(NovaTheme.accent.opacity(0.18)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().stroke(focused ? NovaTheme.accent.opacity(0.7) : NovaTheme.stroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 16, y: 8)
        .animation(.easeOut(duration: 0.2), value: focused)
    }

    private var shortcutGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
            ForEach(shortcuts) { s in
                Button {
                    focused = false
                    model.load(s.url)
                } label: {
                    VStack(spacing: 7) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.40))
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(NovaTheme.stroke, lineWidth: 1)
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
                        .frame(width: 56, height: 56)
                        Text(s.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    private func go() {
        let q = query
        query = ""
        focused = false
        model.load(q)
    }
}
