import SwiftUI
import WebKit

// MARK: - Ajustes

struct EQSettings: Codable, Equatable {
    var enabled = false
    var preset = "Plano"
    var preamp = 0.0
    var bands = [Double](repeating: 0, count: 13)
    var bass = 0.0        // Graves (dB)
    var treble = 0.0      // Brillo (dB)
    var width = 1.0       // Estéreo (0…2, 1 = 100 %)
    var balance = 0.0     // -1…1
    var loudness = 0.0    // Sonoridad 0…1
    var limiter = true
    var mono = false
    var compat = false    // modo compatible (experimental)
}

enum EQPresets {
    static let all: [(name: String, bands: [Double])] = [
        ("Plano", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Bass and High Boost", [14.2, 7.8, 3.5, 1.5, -0.5, -2.1, -3.7, -3.7, -0.5, 0.8, 2.3, 6.7, 8.5]),
        ("Bass Boost", [9, 7, 5, 3, 1.5, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Voz", [-3, -3, -2, -1, 0, 1, 2.5, 3.5, 3, 2, 0.5, -1, -2]),
        ("Rock", [5, 4, 3, 1.5, -1, -2, -1, 0.5, 2, 3.5, 4.5, 4, 3])
    ]
}

// MARK: - Modelo (global: afecta a todas las pestañas)

final class EQModel: ObservableObject {
    static let shared = EQModel()
    static let freqs: [Double] = [10, 21, 42, 83, 166, 333, 577, 1000, 2000, 4000, 8000, 16000, 20000]
    static let labels = ["10", "21", "42", "83", "166", "333", "577", "1k", "2k", "4k", "8k", "16k", "20k"]

    @Published var s: EQSettings { didSet { save(); push() } }
    @Published var spectrum: [Double] = []
    @Published var status: [String: Any]?
    var webViews: () -> [WKWebView] = { [] }
    var activeWebView: () -> WKWebView? = { nil }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "nova.eq"),
           let saved = try? JSONDecoder().decode(EQSettings.self, from: data) {
            s = saved
        } else {
            s = EQSettings()
        }
    }

    private var json: String {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: "nova.eq") }
    private func push() {
        let js = "window.__novaEQ && window.__novaEQ.apply(\(json));"
        webViews().forEach { $0.evaluateJavaScript(js, completionHandler: nil) }
    }

    var userScript: WKUserScript {
        WKUserScript(source: EQEngine.js.replacingOccurrences(of: "__INIT__", with: json),
                     injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    func pollSpectrum() {
        activeWebView()?.evaluateJavaScript("window.__novaEQ ? window.__novaEQ.snapshot() : ''") { [weak self] r, _ in
            var sp: [Double] = [], st: [String: Any]?
            if let str = r as? String, !str.isEmpty,
               let obj = (try? JSONSerialization.jsonObject(with: Data(str.utf8))) as? [String: Any] {
                sp = (obj["sp"] as? [NSNumber])?.map { $0.doubleValue } ?? []
                st = obj["st"] as? [String: Any]
            }
            DispatchQueue.main.async { self?.spectrum = sp; self?.status = st }
        }
    }

    func playTestTone() {
        activeWebView()?.evaluateJavaScript("window.__novaEQ && window.__novaEQ.test()", completionHandler: nil)
    }

    /// Mensaje claro sobre por qué funciona o no en la pestaña actual.
    var diagnosis: (text: String, ok: Bool, lines: [String]) {
        guard let st = status else { return ("Abre una página web para usar el ecualizador.", false, []) }
        let ctx = st["ctx"] as? String ?? "none"
        let err = st["err"] as? String ?? ""
        let els = (st["els"] as? [[String: Any]]) ?? []
        let lines = els.map { e -> String in
            let tag = e["tag"] as? String ?? "media"
            let playing = e["playing"] as? Bool ?? false
            let att = e["att"] as? Bool ?? false
            let reason = e["reason"] as? String ?? ""
            return "\(tag) · \(playing ? "suena" : "sin sonido") · " + (att ? "conectado" : (reason.isEmpty ? "sin conectar" : "no compatible: \(reason)"))
        }
        let playing = els.filter { ($0["playing"] as? Bool) == true }
        if !err.isEmpty && !els.contains(where: { ($0["att"] as? Bool) == true }) { return ("Error del motor: \(err)", false, lines) }
        if !s.enabled { return ("Ecualizador apagado. Actívalo con el interruptor de arriba.", false, lines) }
        if els.isEmpty { return ("Esta página no tiene audio ni vídeo ahora mismo.", false, lines) }
        if playing.isEmpty { return ("No hay nada sonando en esta página. Dale a reproducir y vuelve a abrir el panel.", false, lines) }
        if let bad = playing.first(where: { ($0["att"] as? Bool) != true }) {
            let r = bad["reason"] as? String ?? "sin conectar"
            return ("Lo que suena en esta página no se puede ecualizar en iOS (\(r)). El ecualizador funciona, pero ese audio no pasa por él. Usa «Probar con tono» para comprobarlo.", false, lines)
        }
        if ctx == "suspended" { return ("Motor en pausa: cierra el panel, toca la web una vez y vuelve a abrirlo.", false, lines) }
        if (spectrum.max() ?? 0) < 0.02 {
            return ("El audio figura como conectado, pero no llega nada al ecualizador mientras suena. iOS parece seguir reproduciéndolo por su ruta nativa (límite de WebKit con YouTube y similares). Sube a la gráfica: si las barras no se mueven, no se puede ecualizar.", false, lines)
        }
        return ("Activo: el audio que suena está conectado al ecualizador.", true, lines)
    }

    func apply(preset name: String) {
        guard let p = EQPresets.all.first(where: { $0.name == name }) else { return }
        var t = s; t.bands = p.bands; t.preset = name; s = t
    }
}

// MARK: - Motor de audio (Web Audio dentro de cada página)

enum EQEngine {
    static let js = #"""
    (function () {
      if (window.__novaEQ) return;
      var F = [10,21,42,83,166,333,577,1000,2000,4000,8000,16000,20000];
      var S = __INIT__;
      if (S.compat && !window.MediaSource && window.ManagedMediaSource) { window.MediaSource = window.ManagedMediaSource; }
      var st = { err: '', reason: '', att: 0, media: 0 }, force = false;
      var ctx = null, inp, pre, filt = [], bassF, trebF, loL, loH, gLL, gRL, gLR, gRR, comp, an, seen = new WeakSet();

      function mk(type, f, q) { var b = ctx.createBiquadFilter(); b.type = type; b.frequency.value = f; b.Q.value = q || 1; return b; }
      function build() {
        try { build0(); } catch (e) {
          st.err = 'build: ' + (e && e.message || e);
          try { ctx && ctx.close(); } catch (_) {}
          ctx = null; filt = [];
        }
      }
      function build0() {
        var C = window.AudioContext || window.webkitAudioContext; if (!C) return;
        ctx = new C({ latencyHint: 'playback' });
        inp = ctx.createGain(); pre = ctx.createGain();
        inp.connect(pre);
        var last = pre;
        F.forEach(function (f, i) {
          var b = mk(i === 0 ? 'lowshelf' : (i === F.length - 1 ? 'highshelf' : 'peaking'), f, 1.0);
          last.connect(b); last = b; filt.push(b);
        });
        bassF = mk('lowshelf', 120); trebF = mk('highshelf', 6000); loL = mk('lowshelf', 100); loH = mk('highshelf', 8000);
        [bassF, trebF, loL, loH].forEach(function (n) { last.connect(n); last = n; });
        last.channelCount = 2; last.channelCountMode = 'explicit'; last.channelInterpretation = 'speakers';
        var sp = ctx.createChannelSplitter(2), mg = ctx.createChannelMerger(2);
        last.connect(sp);
        gLL = ctx.createGain(); gRL = ctx.createGain(); gLR = ctx.createGain(); gRR = ctx.createGain();
        sp.connect(gLL, 0); sp.connect(gLR, 0); sp.connect(gRL, 1); sp.connect(gRR, 1);
        gLL.connect(mg, 0, 0); gRL.connect(mg, 0, 0); gLR.connect(mg, 0, 1); gRR.connect(mg, 0, 1);
        comp = ctx.createDynamicsCompressor();
        an = ctx.createAnalyser(); an.fftSize = 1024; an.smoothingTimeConstant = 0.8;
        mg.connect(comp); comp.connect(an); an.connect(ctx.destination);
        update();
      }
      function set(p, v) { p.setTargetAtTime(v, ctx.currentTime, 0.03); }
      function update() {
        if (!ctx) return;
        var on = !!S.enabled;
        set(pre.gain, on ? Math.pow(10, S.preamp / 20) : 1);
        filt.forEach(function (b, i) { set(b.gain, on ? S.bands[i] : 0); });
        set(bassF.gain, on ? S.bass : 0); set(trebF.gain, on ? S.treble : 0);
        set(loL.gain, on ? S.loudness * 8 : 0); set(loH.gain, on ? S.loudness * 4 : 0);
        var w = on ? (S.mono ? 0 : S.width) : 1, a = (1 + w) / 2, b = (1 - w) / 2;
        var bal = on ? Math.max(-1, Math.min(1, S.balance)) : 0;
        var lg = bal > 0 ? 1 - bal : 1, rg = bal < 0 ? 1 + bal : 1;
        set(gLL.gain, lg * a); set(gRL.gain, lg * b); set(gLR.gain, rg * b); set(gRR.gain, rg * a);
        var lim = on && S.limiter;
        comp.threshold.value = lim ? -3 : 0; comp.knee.value = 0; comp.ratio.value = lim ? 20 : 1;
        comp.attack.value = 0.003; comp.release.value = 0.1;
        if (ctx.state === 'suspended') ctx.resume().catch(function () {});
      }
      function why(el) {
        var u = el.currentSrc || el.src; if (!u) return 'sin fuente';
        if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) return '';
        try { if (new URL(u, location.href).origin === location.origin) return ''; } catch (e) {}
        return /\.m3u8|manifest|playlist/i.test(u) ? 'HLS nativo de iOS' : 'audio de otro dominio';
      }
      function attach(el) {
        if (seen.has(el)) return;
        var r = why(el); if (r) { st.reason = r; return; }
        try { ctx.createMediaElementSource(el).connect(inp); seen.add(el); st.att++; st.reason = ''; }
        catch (e) { st.err = String(e && e.message || e); }
      }
      function sync() {
        try {
          var m = document.querySelectorAll('video,audio'); st.media = m.length;
          if (!ctx && ((S.enabled && m.length) || force)) build();
          if (ctx) { update(); m.forEach(attach); }
        } catch (e) { st.err = String(e && e.message || e); }
      }
      function down(s) {
        for (var i = 0; i < window.frames.length; i++) { try { window.frames[i].postMessage({ novaEQ: s }, '*'); } catch (e) {} }
      }
      window.__novaEQ = {
        snapshot: function () {
          var els = Array.prototype.map.call(document.querySelectorAll('video,audio'), function (el) {
            return { tag: el.tagName.toLowerCase(), playing: !el.paused && !el.ended && !el.muted && el.readyState > 2,
                     att: seen.has(el), reason: why(el) };
          });
          return JSON.stringify({ sp: this.spectrum(), st: { ctx: ctx ? ctx.state : 'none', els: els, err: st.err } });
        },
        test: function () {
          force = true; sync(); if (!ctx) return;
          var b = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate), d = b.getChannelData(0);
          for (var i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
          var n = ctx.createBufferSource(); n.buffer = b; n.loop = true;
          var g = ctx.createGain(); g.gain.value = 0.12; n.connect(g); g.connect(inp); n.start();
          if (ctx.state === 'suspended') ctx.resume().catch(function () {});
          setTimeout(function () { try { n.stop(); } catch (e) {} force = false; }, 4000);
        },
        apply: function (s) { S = s; sync(); down(s); },
        spectrum: function () {
          if (!an) return [];
          var d = new Uint8Array(an.frequencyBinCount); an.getByteFrequencyData(d);
          var out = [], n = 40, lo = 2, hi = d.length - 1;
          for (var i = 0; i < n; i++) {
            var a = Math.floor(lo * Math.pow(hi / lo, i / n)), b = Math.max(a + 1, Math.floor(lo * Math.pow(hi / lo, (i + 1) / n))), m = 0;
            for (var j = a; j < b; j++) m = Math.max(m, d[j]);
            out.push(m / 255);
          }
          return out;
        }
      };
      window.addEventListener('message', function (e) {
        if (e.data && e.data.novaEQ) { S = e.data.novaEQ; sync(); down(S); }
        else if (e.data && e.data.novaEQreq && e.source) { e.source.postMessage({ novaEQ: S }, '*'); }
      });
      if (window !== window.top) { try { window.parent.postMessage({ novaEQreq: 1 }, '*'); } catch (e) {} }
      ['play', 'playing', 'loadeddata'].forEach(function (ev) { document.addEventListener(ev, sync, true); });
      ['touchend', 'click'].forEach(function (ev) {
        document.addEventListener(ev, function () { if (ctx && ctx.state === 'suspended') ctx.resume().catch(function () {}); }, true);
      });
      setInterval(sync, 1500);
    })();
    """#
}

// MARK: - Controles

private let eqPink = Color(hex: 0xFF6FB5)
private let eqCyan = Color(hex: 0x4FD1E8)

struct VGainSlider: View {
    @Binding var value: Double
    let label: String
    private let range = -15.0...15.0
    @State private var start: Double?

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: "%+.1f", value))
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundColor(value >= 0 ? eqPink : eqCyan)
                .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { g in
                let h = g.size.height
                let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let y = h * (1 - frac)
                ZStack(alignment: .top) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(width: 4).frame(maxWidth: .infinity)
                    Capsule().fill(NovaTheme.accentGradient)
                        .frame(width: 4, height: abs(h / 2 - y))
                        .offset(y: min(y, h / 2))
                        .frame(maxWidth: .infinity)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: 0xE9E6FF))
                        .frame(width: 22, height: 13)
                        .shadow(color: NovaTheme.accent.opacity(0.5), radius: 4)
                        .offset(y: y - 6.5)
                        .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    if start == nil { start = value }
                    let span = range.upperBound - range.lowerBound
                    let raw = (start ?? value) - Double(v.translation.height / h) * span
                    value = (min(max(raw, range.lowerBound), range.upperBound) * 10).rounded() / 10
                }.onEnded { _ in start = nil })
                .onTapGesture(count: 2) { value = 0 }
            }
            .frame(height: 150)
            Text(label).font(.system(size: 8.5, weight: .medium)).foregroundColor(NovaTheme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EQKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutral: Double
    let title: String
    let display: String
    @State private var start: Double?

    var body: some View {
        let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        VStack(spacing: 5) {
            ZStack {
                Circle().trim(from: 0, to: 0.75).rotation(.degrees(135))
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().trim(from: 0, to: 0.75 * frac).rotation(.degrees(135))
                    .stroke(NovaTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().fill(NovaTheme.surfaceHi).padding(7)
                Capsule().fill(Color.white).frame(width: 2.5, height: 9)
                    .offset(y: -13).rotationEffect(.degrees(-135 + 270 * frac))
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in
                if start == nil { start = value }
                let span = range.upperBound - range.lowerBound
                value = min(max((start ?? value) + Double(v.translation.width) / 140 * span, range.lowerBound), range.upperBound)
            }.onEnded { _ in start = nil })
            .onTapGesture(count: 2) { value = neutral }
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            Text(display).font(.system(size: 10, weight: .medium)).foregroundColor(NovaTheme.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Panel

struct EQSheet: View {
    let host: String
    var openTest: () -> Void = {}
    @ObservedObject private var eq = EQModel.shared
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    private var live: Bool { (eq.spectrum.max() ?? 0) > 0.03 }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                presets
                graph
                preampRow
                bandsCard
                knobsCard
                togglesRow
                diagnosticCard
                Text("Mandos: arrastra de lado. Doble toque restablece. Afecta a todas las pestañas.")
                    .font(.system(size: 11)).foregroundColor(NovaTheme.dim).multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(NovaBackground().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onReceive(timer) { _ in eq.pollSpectrum() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(NovaTheme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(NovaTheme.surfaceHi))
            VStack(alignment: .leading, spacing: 4) {
                Text("Ecualizador").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                HStack(spacing: 6) {
                    if live {
                        HStack(spacing: 4) {
                            Circle().fill(NovaTheme.good).frame(width: 5, height: 5)
                            Text("EN DIRECTO").font(.system(size: 8.5, weight: .bold)).foregroundColor(NovaTheme.good)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(NovaTheme.good.opacity(0.14)))
                    }
                    Text(host).font(.system(size: 11)).foregroundColor(NovaTheme.dim).lineLimit(1)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { eq.s.enabled }, set: { var t = eq.s; t.enabled = $0; eq.s = t }))
                .labelsHidden().tint(NovaTheme.accent)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NovaTheme.dim).frame(width: 30, height: 30)
            }.buttonStyle(.plain)
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EQPresets.all, id: \.name) { p in
                    let on = eq.s.preset == p.name
                    Button { eq.apply(preset: p.name) } label: {
                        Text(p.name).font(.system(size: 13, weight: .semibold))
                            .foregroundColor(on ? .white : NovaTheme.dim)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(on ? AnyShapeStyle(NovaTheme.accentGradient) : AnyShapeStyle(NovaTheme.surface)))
                            .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var graph: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.18)))
            let n = eq.spectrum.count
            if n > 0 {
                let bw = w / CGFloat(n)
                for (i, v) in eq.spectrum.enumerated() {
                    let bh = CGFloat(v) * h * 0.9
                    ctx.fill(Path(CGRect(x: CGFloat(i) * bw + 1, y: h - bh, width: bw - 2, height: bh)),
                             with: .color(NovaTheme.accent.opacity(0.35)))
                }
            }
            var zero = Path(); zero.move(to: CGPoint(x: 0, y: h / 2)); zero.addLine(to: CGPoint(x: w, y: h / 2))
            ctx.stroke(zero, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
            let lo = log10(10.0), hi = log10(20000.0)
            let pts: [CGPoint] = EQModel.freqs.enumerated().map { i, f in
                CGPoint(x: CGFloat((log10(f) - lo) / (hi - lo)) * w,
                        y: h / 2 - CGFloat(eq.s.bands[i] / 15) * (h / 2 - 8))
            }
            var curve = Path(); curve.move(to: pts[0])
            for i in 1..<pts.count {
                let mx = (pts[i - 1].x + pts[i].x) / 2
                curve.addCurve(to: pts[i], control1: CGPoint(x: mx, y: pts[i - 1].y), control2: CGPoint(x: mx, y: pts[i].y))
            }
            ctx.stroke(curve, with: .color(NovaTheme.accent), lineWidth: 2.2)
            for (i, p) in pts.enumerated() {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(eq.s.bands[i] >= 0 ? eqPink : eqCyan))
            }
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
        .opacity(eq.s.enabled ? 1 : 0.55)
    }

    private var preampRow: some View {
        HStack(spacing: 12) {
            Text("PREAMP").font(.system(size: 10, weight: .bold)).foregroundColor(NovaTheme.dim)
            Slider(value: Binding(get: { eq.s.preamp }, set: { var t = eq.s; t.preamp = ($0 * 10).rounded() / 10; eq.s = t }),
                   in: -12...12).tint(NovaTheme.accent)
            Text(String(format: "%+.1f dB", eq.s.preamp))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var bandsCard: some View {
        HStack(spacing: 0) {
            ForEach(0..<13, id: \.self) { i in
                VGainSlider(value: Binding(get: { eq.s.bands[i] },
                                           set: { var t = eq.s; t.bands[i] = $0; t.preset = "Personalizado"; eq.s = t }),
                            label: EQModel.labels[i])
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
        .novaCard()
        .opacity(eq.s.enabled ? 1 : 0.55)
    }

    private func bind(_ kp: WritableKeyPath<EQSettings, Double>) -> Binding<Double> {
        Binding(get: { eq.s[keyPath: kp] }, set: { var t = eq.s; t[keyPath: kp] = $0; eq.s = t })
    }

    private var knobsCard: some View {
        HStack(spacing: 0) {
            EQKnob(value: bind(\.bass), range: -12...12, neutral: 0, title: "Graves",
                   display: abs(eq.s.bass) < 0.5 ? "Off" : String(format: "%+.0f dB", eq.s.bass))
            EQKnob(value: bind(\.treble), range: -12...12, neutral: 0, title: "Brillo",
                   display: abs(eq.s.treble) < 0.5 ? "Off" : String(format: "%+.0f dB", eq.s.treble))
            EQKnob(value: bind(\.width), range: 0...2, neutral: 1, title: "Estéreo",
                   display: "\(Int((eq.s.width * 100).rounded()))%")
            EQKnob(value: bind(\.balance), range: -1...1, neutral: 0, title: "Balance",
                   display: abs(eq.s.balance) < 0.03 ? "Centro" : "\(eq.s.balance < 0 ? "L" : "R") \(Int(abs(eq.s.balance) * 100))%")
            EQKnob(value: bind(\.loudness), range: 0...1, neutral: 0, title: "Sonoridad",
                   display: eq.s.loudness < 0.03 ? "Off" : "\(Int(eq.s.loudness * 100))%")
        }
        .padding(.vertical, 14).padding(.horizontal, 4)
        .novaCard()
        .opacity(eq.s.enabled ? 1 : 0.55)
    }

    private var diagnosticCard: some View {
        let d = eq.diagnosis
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: d.ok ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundColor(d.ok ? NovaTheme.good : Color.orange)
                Text(d.text).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(d.lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10.5, design: .monospaced)).foregroundColor(NovaTheme.dim)
            }
            Button { eq.playTestTone() } label: {
                Label("Probar con tono (4 s)", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.surfaceHi))
            }.buttonStyle(.plain)
            Button(action: openTest) {
                Label("Abrir audio de prueba (sin YouTube)", systemImage: "play.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accent.opacity(0.35)))
            }.buttonStyle(.plain)
            Button { var t = EQSettings(); t.enabled = eq.s.enabled; t.compat = eq.s.compat; eq.s = t } label: {
                Label("Restablecer todo", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(NovaTheme.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.plain)
            Toggle(isOn: Binding(get: { eq.s.compat }, set: { var t = eq.s; t.compat = $0; eq.s = t })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo compatible (experimental)").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    Text("Intenta que YouTube use un formato ecualizable. Aplica solo a pestañas nuevas.")
                        .font(.system(size: 10.5)).foregroundColor(NovaTheme.dim)
                }
            }.tint(NovaTheme.accent)
        }
        .padding(12).novaCard(radius: 14)
    }

    private var togglesRow: some View {
        HStack(spacing: 10) {
            toggleCard("Limitador", "Evita la saturación",
                       Binding(get: { eq.s.limiter }, set: { var t = eq.s; t.limiter = $0; eq.s = t }))
            toggleCard("Mono", "Un solo canal",
                       Binding(get: { eq.s.mono }, set: { var t = eq.s; t.mono = $0; eq.s = t }))
        }
    }

    private func toggleCard(_ title: String, _ sub: String, _ b: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(sub).font(.system(size: 10.5)).foregroundColor(NovaTheme.dim)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: b).labelsHidden().tint(NovaTheme.accent)
        }
        .padding(12).novaCard(radius: 14)
    }
}

// MARK: - Página de prueba (audio sencillo, sin YouTube)

extension EQEngine {
    static let testPage = #"""
    <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Audio de prueba</title>
    <style>body{background:#080B14;color:#fff;font-family:-apple-system,sans-serif;padding:28px;line-height:1.5}
    audio{width:100%;margin:18px 0}h2{margin:0 0 8px}p{color:#aab;font-size:15px}</style></head><body>
    <h2>Audio de prueba</h2>
    <p>1. Pulsa ▶ (suenan 3 notas: grave, media y aguda).<br>2. Abre el ecualizador y activa el interruptor.<br>
    3. Sube mucho los graves y baja los agudos (o al revés).<br>Si el sonido cambia, el ecualizador funciona y el límite es solo de YouTube.</p>
    <audio id="a" controls loop></audio>
    <script>
    var r=44100,n=r*4,b=new ArrayBuffer(44+n*2),v=new DataView(b);
    function w(o,t){for(var i=0;i<t.length;i++)v.setUint8(o+i,t.charCodeAt(i));}
    w(0,'RIFF');v.setUint32(4,36+n*2,true);w(8,'WAVEfmt ');v.setUint32(16,16,true);v.setUint16(20,1,true);v.setUint16(22,1,true);
    v.setUint32(24,r,true);v.setUint32(28,r*2,true);v.setUint16(32,2,true);v.setUint16(34,16,true);w(36,'data');v.setUint32(40,n*2,true);
    for(var i=0;i<n;i++){var t=i/r;v.setInt16(44+i*2,2600*(Math.sin(6.2832*110*t)+Math.sin(6.2832*1000*t)+Math.sin(6.2832*6000*t)),true);}
    document.getElementById('a').src=URL.createObjectURL(new Blob([b],{type:'audio/wav'}));
    </script></body></html>
    """#
}

extension BrowserTab {
    func loadEQTestPage() {
        isHome = false
        webView.loadHTMLString(EQEngine.testPage, baseURL: URL(string: "https://nova.local"))
        onStateChange?()
    }
}
