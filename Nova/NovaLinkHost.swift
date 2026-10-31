import SwiftUI
import WebKit
import UIKit
import ReplayKit
import CoreImage

// ════════════════════════════════════════════════════════════════════════════════════
//  Pestañas del PC que se ejecutan en este iPhone (v91).
//  · La página se carga en vista de ORDENADOR (1280 × 800, como en el PC).
//  · Modo 60 fps: la página se muestra en la pantalla del iPhone (girada) y la graba
//    ReplayKit, que entrega 60 imágenes por segundo sin gastar CPU; se recorta, se gira y
//    se codifica en H.264 por hardware. Si no das permiso para grabar, se usa el modo lento.
// ════════════════════════════════════════════════════════════════════════════════════

/// Recorte + giro + escalado en la GPU y codificación. Trabaja en el hilo de ReplayKit.
final class ScreenPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var transform: CGAffineTransform?
    private var winWidth: CGFloat = 0
    private var inFlight = 0
    private(set) var frames = 0
    let encoder: H264Encoder
    let outW: Int, outH: Int

    init(encoder: H264Encoder) {
        self.encoder = encoder
        outW = encoder.width
        outH = encoder.height
    }

    /// Dónde está la página en la pantalla (en puntos): borde derecho, borde superior, escala y ancho de ventana.
    func setGeometry(x1: CGFloat, y0: CGFloat, k: CGFloat, winWidth: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        self.winWidth = winWidth
        // Guardamos los datos; la transformación exacta depende del tamaño del búfer (se calcula al llegar).
        geo = (x1, y0, k)
        transform = nil
    }
    private var geo: (CGFloat, CGFloat, CGFloat)?

    func sendDone() { lock.lock(); inFlight = max(0, inFlight - 1); lock.unlock() }
    func takeFrames() -> Int { lock.lock(); defer { lock.unlock() }; let f = frames; frames = 0; return f }

    func process(_ sample: CMSampleBuffer) {
        guard let src = CMSampleBufferGetImageBuffer(sample) else { return }
        lock.lock()
        if inFlight > 2 { lock.unlock(); return }
        let wb = CGFloat(CVPixelBufferGetWidth(src)), hb = CGFloat(CVPixelBufferGetHeight(src))
        guard let g = geo, winWidth > 0, hb > wb else { lock.unlock(); return }
        if transform == nil {
            // Página girada 90° a la derecha en pantalla: el punto (u, v) de la web está en
            // pantalla en (x1 − v·k, y0 + u·k). CoreImage tiene el origen abajo a la izquierda.
            let s = wb / winWidth
            let q = CGFloat(outW) / 1280
            let a = q / (s * g.2)
            transform = CGAffineTransform(a: 0, b: a, c: -a, d: 0, tx: a * (hb - s * g.1), ty: q * 800 - a * s * g.0)
        }
        let t = transform!
        inFlight += 1
        frames += 1
        lock.unlock()
        guard let dst = encoder.makeBuffer() else { sendDone(); return }
        let img = CIImage(cvPixelBuffer: src).transformed(by: t).cropped(to: CGRect(x: 0, y: 0, width: outW, height: outH))
        ci.render(img, to: dst, bounds: CGRect(x: 0, y: 0, width: outW, height: outH), colorSpace: CGColorSpaceCreateDeviceRGB())
        encoder.encode(dst)
    }
}

@MainActor
final class RemoteTabHost: NSObject, ObservableObject, Identifiable {
    let id: String
    let webView: WKWebView
    @Published private(set) var title = ""
    @Published private(set) var urlText = ""
    @Published private(set) var fps = 0
    /// true = se ve en la pantalla del iPhone y se graba a 60 fps.
    @Published private(set) var onScreen = false

    private var frameTimer: Timer?
    private var statsTimer: Timer?
    private var inFlight = false
    private var sentAt = Date.distantPast
    private var frames = 0
    private var closed = false
    private var observers: [NSKeyValueObservation] = []
    private(set) var mode = "h264"
    private(set) var outW = 1920
    private(set) var outH = 1200
    private var encoder: H264Encoder?
    private var pipeline: ScreenPipeline?
    private var displayLink: CADisplayLink?
    private var pendingSends = 0
    private var drawMs: Double = 0
    private var halfRate = false
    private var skip = false

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
    /// Solo una pestaña puede usar la grabación de pantalla a la vez.
    static weak var recording: RemoteTabHost?

    init(rid: String, url: String, mode: String = "h264", width: Int = 1920) {
        id = rid
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Sin ventanas nuevas: los enlaces que abrirían otra pestaña se abren en esta.
        config.userContentController.addUserScript(WKUserScript(source: """
        (function(){
          try { window.open = function(u){ if (u) { location.href = u; } return null; }; } catch (e) {}
          document.addEventListener('click', function(e){
            var a = e.target && e.target.closest ? e.target.closest('a[target]') : null;
            if (a && a.target !== '_self') a.target = '_self';
          }, true);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        webView.customUserAgent = RemoteTabHost.desktopUA
        webView.isUserInteractionEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        super.init()
        urlText = url
        self.mode = mode == "jpeg" ? "jpeg" : "h264"
        outW = max(960, min(1920, width)) & ~1
        outH = (outW * 800 / 1280) & ~1
        UIDevice.current.isBatteryMonitoringEnabled = true
        observers.append(webView.observe(\.title, options: [.new]) { wv, _ in
            let t = wv.title ?? ""
            Task { @MainActor [weak self] in self?.title = t }
        })
        observers.append(webView.observe(\.url, options: [.new]) { wv, _ in
            let u = wv.url?.absoluteString ?? ""
            Task { @MainActor [weak self] in if !u.isEmpty { self?.urlText = u } }
        })
        attach()
        if let u = URL(string: url) { webView.load(URLRequest(url: u)) }
        startCapture()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendStats() }
        }
    }

    private var window: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }

    /// Escondida detrás de toda la interfaz (modo lento), encogida para quedar entera dentro de la ventana.
    private func attach() {
        guard let win = window else { return }
        webView.removeFromSuperview()
        webView.transform = .identity
        webView.bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let k = min(1, min(win.bounds.width / 1280, win.bounds.height / 800))
        win.insertSubview(webView, at: 0)
        webView.transform = CGAffineTransform(scaleX: k, y: k)
        webView.center = CGPoint(x: 640 * k, y: 400 * k)
        if onScreen { NovaLink.shared.shareRegionHeight = 0 }
        onScreen = false
    }

    /// Modo 60 fps: la página se ve en la pantalla del iPhone, girada para aprovecharla (como un vídeo apaisado).
    private func showOnScreen() -> (x1: CGFloat, y0: CGFloat, k: CGFloat, winWidth: CGFloat)? {
        guard let win = window else { return nil }
        let safeTop = win.safeAreaInsets.top
        let W = win.bounds.width, H = win.bounds.height
        let k = min((W - 12) / 800, (H - safeTop - 250) / 1280)
        let w = 800 * k, h = 1280 * k
        let x0 = ((W - w) / 2).rounded(), y0 = (safeTop + 10).rounded()
        webView.removeFromSuperview()
        webView.transform = .identity
        webView.bounds = CGRect(x: 0, y: 0, width: 1280, height: 800)
        win.addSubview(webView)
        webView.transform = CGAffineTransform(rotationAngle: .pi / 2).scaledBy(x: k, y: k)
        webView.center = CGPoint(x: x0 + w / 2, y: y0 + h / 2)
        webView.layer.cornerRadius = 0
        onScreen = true
        NovaLink.shared.shareRegionHeight = h + 18
        return (x0 + w, y0, k, W)
    }

    // MARK: Captura

    private func startCapture() {
        stopCapture()
        guard mode == "h264", let enc = H264Encoder(width: outW, height: outH, fps: 60, bitrate: outW >= 1900 ? 9_000_000 : 5_000_000) else {
            startJPEG(); return
        }
        let rid = id, ew = enc.width, eh = enc.height
        enc.onConfig = { @Sendable avcc in
            Task { @MainActor in NovaLink.shared.sendVideoConfig(rid: rid, width: ew, height: eh, avcc: avcc) }
        }
        encoder = enc
        if RemoteTabHost.recording == nil, RPScreenRecorder.shared().isAvailable, let geo = showOnScreen() {
            let pipe = ScreenPipeline(encoder: enc)
            pipe.setGeometry(x1: geo.x1, y0: geo.y0, k: geo.k, winWidth: geo.winWidth)
            pipeline = pipe
            enc.onFrame = { @Sendable data, key in
                Task { @MainActor in
                    NovaLink.shared.sendVideoFrame(rid: rid, key: key, data: data) { pipe.sendDone() }
                }
            }
            RemoteTabHost.recording = self
            let rec = RPScreenRecorder.shared()
            rec.isMicrophoneEnabled = false
            rec.startCapture(handler: { sample, type, _ in
                if type == .video { pipe.process(sample) }
            }, completionHandler: { error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, !self.closed else { return }
                    NovaLink.shared.flash("Sin permiso para grabar la pantalla: modo lento (30 fps).")
                    if RemoteTabHost.recording === self { RemoteTabHost.recording = nil }
                    self.pipeline = nil
                    self.attach()
                    self.startDrawLoop()
                }
            })
        } else {
            startDrawLoop()
        }
    }

    /// Modo lento (sin grabación de pantalla): dibuja la página oculta en el búfer del codificador.
    private func startDrawLoop() {
        guard let enc = encoder else { startJPEG(); return }
        let rid = id
        enc.onFrame = { @Sendable [weak self] data, key in
            Task { @MainActor in
                guard let self = self, !self.closed else { return }
                self.pendingSends += 1
                NovaLink.shared.sendVideoFrame(rid: rid, key: key, data: data) { [weak self] in
                    Task { @MainActor in if let self = self { self.pendingSends = max(0, self.pendingSends - 1) } }
                }
            }
        }
        enc.forceKey = true
        let link = CADisplayLink(target: DisplayLinkProxy { [weak self] in self?.videoTick() }, selector: #selector(DisplayLinkProxy.fire))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func startJPEG() {
        mode = "jpeg"
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureFrame() }
        }
    }

    private func stopCapture() {
        displayLink?.invalidate(); displayLink = nil
        frameTimer?.invalidate(); frameTimer = nil
        if RemoteTabHost.recording === self {
            RPScreenRecorder.shared().stopCapture(handler: nil)
            RemoteTabHost.recording = nil
        }
        pipeline = nil
        encoder?.invalidate(); encoder = nil
        pendingSends = 0
        inFlight = false
    }

    /// Cambia de modo o de resolución (lo pide el PC).
    func setMode(_ m: String, width: Int) {
        guard !closed else { return }
        mode = m == "jpeg" ? "jpeg" : "h264"
        outW = max(960, min(1920, width)) & ~1
        outH = (outW * 800 / 1280) & ~1
        attach()
        startCapture()
    }

    func requestKeyFrame() { encoder?.forceKey = true }

    private func videoTick() {
        guard !closed, let enc = encoder, webView.superview != nil else { return }
        if pendingSends > 2 { return }
        skip.toggle()
        if halfRate && skip { return }
        let t0 = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - t0) * 1000
            drawMs = drawMs * 0.9 + ms * 0.1
            if drawMs > 15 { halfRate = true } else if drawMs < 10 { halfRate = false }
        }
        guard let pb = enc.makeBuffer() else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: CGFloat(w) / 1280, y: -CGFloat(h) / 800)
            ctx.interpolationQuality = .low
            UIGraphicsPushContext(ctx)
            webView.drawHierarchy(in: CGRect(x: 0, y: 0, width: 1280, height: 800), afterScreenUpdates: false)
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        enc.encode(pb)
        frames += 1
    }

    private func captureFrame() {
        guard !closed, webView.superview != nil else { return }
        if inFlight && Date().timeIntervalSince(sentAt) < 2 { return }
        inFlight = true
        sentAt = Date()
        let cfg = WKSnapshotConfiguration()
        cfg.rect = CGRect(x: 0, y: 0, width: 1280, height: 800)
        cfg.snapshotWidth = NSNumber(value: Double(outW) / Double(max(1, UIScreen.main.scale)))
        webView.takeSnapshot(with: cfg) { [weak self] image, _ in
            let jpeg = image?.jpegData(compressionQuality: 0.8)
            Task { @MainActor in
                guard let self = self, !self.closed else { return }
                guard let jpeg = jpeg else { self.inFlight = false; return }
                self.frames += 1
                await NovaLink.shared.sendFrame(rid: self.id, jpeg: jpeg)
            }
        }
    }

    func frameAcked() { inFlight = false }

    private func sendStats() {
        guard !closed else { return }
        fps = frames + (pipeline?.takeFrames() ?? 0)
        frames = 0
        let dev = UIDevice.current
        let level = dev.batteryLevel
        let charging = dev.batteryState == .charging || dev.batteryState == .full
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "normal"
        case .fair: thermal = "templado"
        case .serious: thermal = "caliente"
        case .critical: thermal = "muy caliente"
        @unknown default: thermal = "—"
        }
        let stats: [String: Any] = ["memMB": RemoteTabHost.appMemoryMB(), "battery": level < 0 ? -1 : Int(level * 100),
                                    "charging": charging, "fps": fps, "thermal": thermal,
                                    "mode": pipeline != nil ? "pantalla" : mode, "width": outW, "height": outH]
        NovaLink.shared.send(["t": "rtab:stats", "rid": id, "title": webView.title ?? "", "url": webView.url?.absoluteString ?? urlText,
                              "canBack": webView.canGoBack, "canForward": webView.canGoForward, "stats": stats])
    }

    static func appMemoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { p in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), p, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : 0
    }

    // MARK: Entrada desde el PC

    func input(_ m: JSONValue) {
        let x = m["x"].double ?? 0, y = m["y"].double ?? 0
        switch m["kind"].str {
        case "click":
            run("""
            (function(x,y){x=x*innerWidth/1280;y=y*innerHeight/800;var e=document.elementFromPoint(x,y);if(!e)return;
              var o={bubbles:true,cancelable:true,composed:true,clientX:x,clientY:y,view:window,button:0,pointerId:1,isPrimary:true};
              try{e.dispatchEvent(new PointerEvent('pointerdown',o));}catch(_){}
              e.dispatchEvent(new MouseEvent('mousedown',o));
              try{e.dispatchEvent(new PointerEvent('pointerup',o));}catch(_){}
              e.dispatchEvent(new MouseEvent('mouseup',o));
              var f=e.closest&&e.closest('input,textarea,select,[contenteditable],[tabindex]'); if(f&&f.focus)f.focus();
              if(typeof e.click==='function')e.click();else e.dispatchEvent(new MouseEvent('click',o));
            })(\(x),\(y))
            """)
        case "scroll":
            let dx = m["dx"].double ?? 0, dy = m["dy"].double ?? 0
            run("""
            (function(x,y,dx,dy){x=x*innerWidth/1280;y=y*innerHeight/800;var e=document.elementFromPoint(x,y);
              while(e&&e!==document.body&&e!==document.documentElement){var s=getComputedStyle(e);
                if((/(auto|scroll)/.test(s.overflowY)&&e.scrollHeight>e.clientHeight)||(/(auto|scroll)/.test(s.overflowX)&&e.scrollWidth>e.clientWidth)){e.scrollBy(dx,dy);return;}
                e=e.parentElement;}
              window.scrollBy(dx,dy);})(\(x),\(y),\(dx),\(dy))
            """)
        case "text":
            run("""
            (function(t){var a=document.activeElement;if(!a)return;
              try{if(document.execCommand('insertText',false,t))return;}catch(_){}
              if('value' in a){var s=a.selectionStart==null?a.value.length:a.selectionStart,en=a.selectionEnd==null?s:a.selectionEnd;
                a.value=a.value.slice(0,s)+t+a.value.slice(en);a.dispatchEvent(new Event('input',{bubbles:true}));}})(\(jsString(m["text"].str)))
            """)
        case "key":
            run("""
            (function(k){var a=document.activeElement||document.body;
              var codes={Enter:13,Backspace:8,Tab:9,Escape:27,ArrowUp:38,ArrowDown:40,ArrowLeft:37,ArrowRight:39,Delete:46,PageUp:33,PageDown:34,Home:36,End:35,Space:32};
              var key=k==='Space'?' ':k;
              var ev=new KeyboardEvent('keydown',{key:key,code:k,keyCode:codes[k]||0,which:codes[k]||0,bubbles:true,cancelable:true});
              var ok=a.dispatchEvent(ev);
              a.dispatchEvent(new KeyboardEvent('keyup',{key:key,code:k,keyCode:codes[k]||0,which:codes[k]||0,bubbles:true}));
              if(!ok)return;
              var editable=a.isContentEditable||/^(INPUT|TEXTAREA)$/.test(a.tagName);
              if(k==='Enter'){ if(a.tagName==='INPUT'&&a.form){ if(a.form.requestSubmit)a.form.requestSubmit(); else a.form.submit(); }
                else if(editable){document.execCommand('insertLineBreak')||document.execCommand('insertText',false,'\\n');}
                else if(a.click)a.click(); return; }
              if(k==='Backspace'&&editable){document.execCommand('delete');return;}
              if(k==='Delete'&&editable){document.execCommand('forwardDelete');return;}
              if(k==='Space'&&editable){document.execCommand('insertText',false,' ');return;}
              if(k==='Tab'){var f=[].slice.call(document.querySelectorAll('a[href],button,input,select,textarea,[tabindex]:not([tabindex="-1"])')).filter(function(n){return !n.disabled&&n.offsetParent!==null;});
                var i=f.indexOf(a);if(f.length)f[(i+1)%f.length].focus();return;}
              if(editable)return;
              var m={ArrowDown:[0,60],ArrowUp:[0,-60],ArrowRight:[60,0],ArrowLeft:[-60,0],PageDown:[0,700],PageUp:[0,-700],Space:[0,700]};
              if(m[k])window.scrollBy(m[k][0],m[k][1]);
              if(k==='Home')window.scrollTo(0,0); if(k==='End')window.scrollTo(0,document.body.scrollHeight);
            })(\(jsString(m["key"].str)))
            """)
        default:
            break
        }
    }

    func navigate(_ action: String, url: String) {
        switch action {
        case "back": if webView.canGoBack { webView.goBack() }
        case "forward": if webView.canGoForward { webView.goForward() }
        case "reload": webView.reload()
        case "go": if let u = URL(string: url), u.scheme?.hasPrefix("http") == true { webView.load(URLRequest(url: u)) }
        default: break
        }
    }

    private func run(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// notify = true: lo detuvo el iPhone (el PC muestra que ya no se ejecuta).
    func shutdown(notify: Bool) {
        guard !closed else { return }
        closed = true
        stopCapture()
        statsTimer?.invalidate(); statsTimer = nil
        observers.removeAll()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
        if notify { NovaLink.shared.send(["t": "rtab:closed", "rid": id]) }
        onScreen = false
    }
}

// ════════════════════════════════════════════════════════════════════════════════════
//  Cuando una web del iPhone pide un archivo y el PC está enlazado: «Este iPhone»
//  (selector normal de iOS) o «Mi PC» (carpetas que compartiste en Nova para Windows).
// ════════════════════════════════════════════════════════════════════════════════════

enum NovaLinkScripts {
    static let filePicker = WKUserScript(source: """
    (function(){
      if (window.__novaFP) return; window.__novaFP = true;
      var bypass = null;
      document.addEventListener('click', function(ev){
        var i = ev.target;
        if (!(i instanceof HTMLInputElement) || i.type !== 'file' || i.disabled) return;
        if (bypass === i) { bypass = null; return; }
        if (!window.__novaLinked || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.novaFile) return;
        ev.preventDefault(); ev.stopImmediatePropagation();
        show(i);
      }, true);
      function show(input){
        var host = document.createElement('div');
        host.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647';
        var root = host.attachShadow({mode:'closed'});
        root.innerHTML = '<style>'
          + '.bg{position:fixed;inset:0;background:rgba(0,0,0,.42);display:flex;align-items:flex-end;justify-content:center;font:15px -apple-system,system-ui,sans-serif;color:#eef0fb}'
          + '.sh{width:100%;max-width:520px;background:#121626;border-radius:22px 22px 0 0;padding:18px 16px calc(18px + env(safe-area-inset-bottom));box-shadow:0 -10px 40px rgba(0,0,0,.4)}'
          + 'b{display:block;font-size:17px;margin:0 4px 2px}p{margin:0 4px 14px;color:#9aa1bb;font-size:13px}'
          + 'button{all:unset;box-sizing:border-box;display:block;width:100%;padding:14px 16px;border-radius:14px;background:#1b2135;margin-bottom:10px;cursor:pointer}'
          + 'button span{display:block;color:#9aa1bb;font-size:12.5px;margin-top:2px}.c{text-align:center;background:transparent;color:#8d7cff;font-weight:600}'
          + '</style><div class="bg"><div class="sh"><b>Elegir archivo</b><p>Esta web pide un archivo. ¿De dónde lo sacas?</p>'
          + '<button data-a="phone">Este iPhone<span>Fotos, Archivos o cámara</span></button>'
          + '<button data-a="pc">Mi PC<span>Carpetas que compartiste en Nova para Windows</span></button>'
          + '<button class="c" data-a="x">Cancelar</button></div></div>';
        var close = function(){ host.remove(); };
        root.querySelector('[data-a=phone]').onclick = function(){ close(); bypass = input; input.click(); };
        root.querySelector('[data-a=pc]').onclick = function(){ close(); window.__novaPendingInput = input; window.webkit.messageHandlers.novaFile.postMessage({multiple: !!input.multiple}); };
        root.querySelector('[data-a=x]').onclick = close;
        root.querySelector('.bg').addEventListener('click', function(e){ if (e.target === root.querySelector('.bg')) close(); });
        (document.body || document.documentElement).appendChild(host);
      }
      window.__novaDeliver = function(name, type, b64){
        var input = window.__novaPendingInput; if (!input) return false;
        try {
          var bin = atob(b64), arr = new Uint8Array(bin.length);
          for (var k = 0; k < bin.length; k++) arr[k] = bin.charCodeAt(k);
          var dt = new DataTransfer();
          dt.items.add(new File([arr], name, {type: type || 'application/octet-stream', lastModified: Date.now()}));
          input.files = dt.files;
          input.dispatchEvent(new Event('input', {bubbles: true}));
          input.dispatchEvent(new Event('change', {bubbles: true}));
          window.__novaPendingInput = null;
          return true;
        } catch (e) { return false; }
      };
    })();
    """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
}

/// Recibe «Mi PC» desde la web y abre el selector de archivos del PC.
final class NovaFileBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    init(webView: WKWebView) { self.webView = webView }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let wv = webView
        Task { @MainActor in NovaLink.shared.pcPick = PCPickRequest(webView: wv) }
    }
}
