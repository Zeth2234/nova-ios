import SwiftUI
import WebKit
import LocalAuthentication
import Security

// MARK: - Preferencias

enum Prefs {
    static func flag(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

// MARK: - Almacén de contraseñas (Keychain protegido con Face ID)

struct SavedLogin: Identifiable, Hashable {
    let host: String
    let username: String
    var id: String { host + "|" + username }
}

/// Las contraseñas se guardan en el Keychain con control de acceso `.userPresence`:
/// iOS pide Face ID (o el código) cada vez que se lee una. En UserDefaults solo queda
/// un índice con sitio + usuario (sin contraseñas) para poder listar y ofrecer el acceso.
enum Vault {
    private static let indexKey = "vaultIndex"

    static func normalize(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// Dominio "base" aproximado (accounts.google.com -> google.com, bbc.co.uk -> bbc.co.uk).
    static func baseDomain(_ host: String) -> String {
        let labels = normalize(host).split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let last = labels[labels.count - 1]
        let second = labels[labels.count - 2]
        let take = (last.count == 2 && second.count <= 3) ? 3 : 2
        return labels.suffix(take).joined(separator: ".")
    }

    static var all: [SavedLogin] {
        let raw = UserDefaults.standard.array(forKey: indexKey) as? [[String: String]] ?? []
        let list: [SavedLogin] = raw.compactMap { d in
            guard let h = d["h"], let u = d["u"] else { return nil }
            return SavedLogin(host: h, username: u)
        }
        return list.sorted { ($0.host, $0.username) < ($1.host, $1.username) }
    }

    static func logins(for pageHost: String) -> [SavedLogin] {
        let base = baseDomain(pageHost)
        return all.filter { baseDomain($0.host) == base }
    }

    private static func writeIndex(_ list: [SavedLogin]) {
        UserDefaults.standard.set(list.map { ["h": $0.host, "u": $0.username] }, forKey: indexKey)
    }

    @discardableResult
    static func save(host: String, username: String, password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: host,
            kSecAttrAccount as String: username
        ]
        SecItemDelete(base as CFDictionary)

        guard let acl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else { return false }

        var add = base
        add[kSecAttrLabel as String] = "Nova · \(host)"
        add[kSecAttrAccessControl as String] = acl
        add[kSecValueData as String] = data
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return false }

        var list = all.filter { !($0.host == host && $0.username == username) }
        list.append(SavedLogin(host: host, username: username))
        writeIndex(list)
        return true
    }

    static func delete(_ login: SavedLogin) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: login.host,
            kSecAttrAccount as String: login.username
        ]
        SecItemDelete(q as CFDictionary)
        writeIndex(all.filter { $0.id != login.id })
    }

    /// Lee la contraseña: iOS muestra Face ID. El resultado llega en el hilo principal.
    static func password(for login: SavedLogin, reason: String,
                         completion: @escaping (String?, OSStatus) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = LAContext()
            ctx.localizedReason = reason
            let q: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: login.host,
                kSecAttrAccount as String: login.username,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: ctx
            ]
            var out: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &out)
            var pw: String?
            if status == errSecSuccess, let d = out as? Data { pw = String(data: d, encoding: .utf8) }
            DispatchQueue.main.async { completion(pw, status) }
        }
    }
}

// MARK: - Scripts inyectados en las páginas

enum QuickLoginScripts {
    /// Hace que los sitios no ofrezcan passkeys (WebAuthn): WKWebView no puede usarlas en una
    /// app instalada con AltStore, y el intento termina en error. Con esto la web cae al
    /// formulario de contraseña, que Nova rellena con Face ID.
    static let passkeyShim = WKUserScript(source: #"""
    (function() {
      try {
        var notify = function() {
          try { window.webkit.messageHandlers.novaPasskey.postMessage({type: 'blocked'}); } catch (e) {}
        };
        if (window.PublicKeyCredential) {
          var no = function() { return Promise.resolve(false); };
          ['isUserVerifyingPlatformAuthenticatorAvailable', 'isConditionalMediationAvailable'].forEach(function(n) {
            try { Object.defineProperty(window.PublicKeyCredential, n, { value: no, configurable: true, writable: true }); } catch (e) {}
          });
        }
        if (navigator.credentials) {
          ['get', 'create'].forEach(function(n) {
            var orig = navigator.credentials[n];
            if (!orig) return;
            navigator.credentials[n] = function(opts) {
              if (opts && opts.publicKey) {
                if (opts.mediation !== 'conditional') notify();
                return Promise.reject(new DOMException('Passkeys no disponibles en Nova', 'NotAllowedError'));
              }
              return orig.apply(this, arguments);
            };
          });
        }
      } catch (e) {}
    })();
    """#, injectionTime: .atDocumentStart, forMainFrameOnly: false)

    /// Detecta formularios de inicio de sesión, captura envíos y expone window.__novaFill.
    static let credentials = WKUserScript(source: #"""
    (function() {
      if (window.__novaCreds) return;
      window.__novaCreds = true;
      var post = function(o) {
        try { window.webkit.messageHandlers.novaCreds.postMessage(o); } catch (e) {}
      };
      var visible = function(el) {
        if (!el || !el.getBoundingClientRect) return false;
        var r = el.getBoundingClientRect();
        var s = getComputedStyle(el);
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
      };
      var pwField = function() {
        var l = document.querySelectorAll('input[type=password]');
        for (var i = 0; i < l.length; i++) if (visible(l[i])) return l[i];
        return null;
      };
      var TEXTY = 'input:not([type]), input[type=text], input[type=email], input[type=tel], input[type=username]';
      var userField = function(pw) {
        var scope = (pw && pw.form) || document;
        var l = scope.querySelectorAll(TEXTY);
        var before = null, first = null;
        for (var i = 0; i < l.length; i++) {
          var e = l[i];
          if (!visible(e)) continue;
          if (!first) first = e;
          if (pw && (e.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING)) before = e;
        }
        return before || first;
      };
      var looksLikeLoginUser = function() {
        var l = document.querySelectorAll('input[type=email], input[autocomplete*=username], input[autocomplete*=email]');
        for (var i = 0; i < l.length; i++) if (visible(l[i])) return true;
        return false;
      };
      var setVal = function(el, v) {
        try {
          var d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value');
          if (d && d.set) d.set.call(el, v); else el.value = v;
        } catch (e) { el.value = v; }
        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
      };
      var go = function(el) {
        var f = el.form, btn = null;
        if (f) btn = f.querySelector('button[type=submit], input[type=submit]');
        if (!btn) {
          var bs = document.querySelectorAll('button, input[type=submit], [role=button]');
          for (var i = 0; i < bs.length; i++) {
            var b = bs[i];
            if (!visible(b)) continue;
            var t = ((b.innerText || b.value || '') + '').toLowerCase();
            if (/(siguiente|next|continu|iniciar|entrar|acceder|log ?in|sign ?in)/.test(t)) { btn = b; break; }
          }
        }
        if (btn) btn.click();
        else el.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
      };

      window.__novaFill = function(u, p, submit) {
        var pw = pwField();
        var uf = userField(pw);
        if (uf && u) { uf.focus(); setVal(uf, u); }
        if (pw && p) { pw.focus(); setVal(pw, p); }
        var target = pw || uf;
        if (submit && target) setTimeout(function() { go(target); }, 250);
        return !!target;
      };

      var lastUser = '';
      try { lastUser = sessionStorage.getItem('__nova_u') || ''; } catch (e) {}
      var capture = function() {
        var pw = pwField();
        var uf = userField(pw);
        var uval = (uf && uf.value) ? uf.value : '';
        if (!pw) {
          if (uval) { lastUser = uval; try { sessionStorage.setItem('__nova_u', uval); } catch (e) {} }
          return;
        }
        if (!pw.value) return;
        post({type: 'submit', username: uval || lastUser, password: pw.value});
      };
      document.addEventListener('submit', capture, true);
      document.addEventListener('click', function(e) {
        var t = e.target && e.target.closest ? e.target.closest('button, input[type=submit], [role=button]') : null;
        if (t) capture();
      }, true);
      document.addEventListener('keydown', function(e) { if (e.key === 'Enter') capture(); }, true);

      var lastKey = null, timer = null;
      var report = function() {
        var hasPw = !!pwField();
        var hasUser = !hasPw && looksLikeLoginUser();
        var key = hasPw + '|' + hasUser;
        if (key === lastKey) return;
        lastKey = key;
        post({type: 'form', hasPassword: hasPw, hasUser: hasUser});
      };
      var schedule = function() { clearTimeout(timer); timer = setTimeout(report, 450); };
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', schedule);
      else schedule();
      window.addEventListener('load', schedule);
      try { new MutationObserver(schedule).observe(document.documentElement, {childList: true, subtree: true}); } catch (e) {}
    })();
    """#, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
}

/// Evita el ciclo de retención entre WKUserContentController y la pestaña.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

extension BrowserTab: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch message.name {
        case "novaCreds": QuickLogin.shared.handle(body, from: self)
        case "novaPasskey": QuickLogin.shared.passkeyBlocked()
        default: break
        }
    }
}

// MARK: - Lógica del inicio rápido

final class QuickLogin: ObservableObject {
    static let shared = QuickLogin()

    struct Offer: Equatable {
        let tabID: UUID
        let host: String
        let logins: [SavedLogin]
        let userOnly: Bool
    }
    struct Pending {
        let tabID: UUID
        let host: String
        let username: String
        let password: String
        let date: Date
    }
    struct Recent {
        let host: String
        let username: String
        let password: String
        let date: Date
        var used: Bool
    }

    @Published var offer: Offer?
    @Published var savePrompt: Pending?
    @Published var toast: String?

    private var pending: Pending?
    private var recent: Recent?
    private var filled: [String: String] = [:]
    private var lastPasskeyToast = Date.distantPast

    private init() {}

    // MARK: Mensajes de la página

    func handle(_ body: [String: Any], from tab: BrowserTab) {
        guard !tab.isPrivate, Prefs.flag("quickLogin"),
              let type = body["type"] as? String else { return }
        let host = Vault.normalize(tab.webView.url?.host ?? "")
        guard !host.isEmpty else { return }

        switch type {
        case "form":
            let hasPw = body["hasPassword"] as? Bool ?? false
            let hasUser = body["hasUser"] as? Bool ?? false
            if hasPw || hasUser {
                // Segundo paso de un login en dos pantallas: rellena solo, ya se autenticó hace segundos.
                if hasPw, var r = recent, !r.used,
                   Date().timeIntervalSince(r.date) < 120,
                   Vault.baseDomain(r.host) == Vault.baseDomain(host) {
                    r.used = true
                    recent = r
                    offer = nil
                    fill(username: r.username, password: r.password, userOnly: false, tab: tab)
                    return
                }
                let logins = Vault.logins(for: host)
                if logins.isEmpty {
                    if offer?.tabID == tab.id { offer = nil }
                } else {
                    offer = Offer(tabID: tab.id, host: host, logins: logins, userOnly: !hasPw)
                }
            } else {
                if offer?.tabID == tab.id { offer = nil }
                if let p = pending, p.tabID == tab.id, Date().timeIntervalSince(p.date) < 25 {
                    askToSave(p)
                }
            }
        case "submit":
            let user = (body["username"] as? String) ?? ""
            let pw = (body["password"] as? String) ?? ""
            guard !pw.isEmpty else { return }
            pending = Pending(tabID: tab.id, host: host, username: user, password: pw, date: Date())
        default:
            break
        }
    }

    func passkeyBlocked() {
        guard Date().timeIntervalSince(lastPasskeyToast) > 20 else { return }
        lastPasskeyToast = Date()
        show("Este sitio pidió una passkey y Nova aún no las admite. Usa tu contraseña con Inicio rápido (Face ID) o abre la página en Safari.")
    }

    // MARK: Guardar

    private func askToSave(_ p: Pending) {
        pending = nil
        guard !p.username.isEmpty else { return }
        let never = UserDefaults.standard.stringArray(forKey: "vaultNever") ?? []
        if never.contains(Vault.baseDomain(p.host)) { return }

        if let existing = Vault.logins(for: p.host).first(where: { $0.username == p.username }) {
            // Ya guardada: solo se pregunta si se sabe que la contraseña cambió.
            guard let previous = filled[existing.id], previous != p.password else { return }
        }
        savePrompt = p
    }

    func confirmSave() {
        guard let p = savePrompt else { return }
        savePrompt = nil
        let host = Vault.logins(for: p.host).first(where: { $0.username == p.username })?.host ?? p.host
        if Vault.save(host: host, username: p.username, password: p.password) {
            filled[host + "|" + p.username] = p.password
            Haptics.success()
            show("Guardada. La próxima vez entrarás con \(PrivacyStore.biometryName).")
        } else {
            show("No se pudo guardar. Comprueba que el iPhone tenga código y \(PrivacyStore.biometryName) activados.")
        }
    }

    func dismissSave() { savePrompt = nil }

    func neverSave() {
        guard let p = savePrompt else { return }
        var never = UserDefaults.standard.stringArray(forKey: "vaultNever") ?? []
        never.append(Vault.baseDomain(p.host))
        UserDefaults.standard.set(never, forKey: "vaultNever")
        savePrompt = nil
    }

    // MARK: Usar

    func use(_ login: SavedLogin, userOnly: Bool, in tab: BrowserTab) {
        Vault.password(for: login, reason: "Iniciar sesión en \(login.host)") { [weak self, weak tab] pw, status in
            guard let self = self, let tab = tab else { return }
            guard let pw = pw else {
                if status != errSecUserCanceled && status != errSecAuthFailed {
                    self.show("No se pudo leer la contraseña (código \(status)). Vuelve a guardarla desde Configuración.")
                }
                return
            }
            self.filled[login.id] = pw
            self.recent = Recent(host: login.host, username: login.username,
                                 password: pw, date: Date(), used: false)
            self.offer = nil
            Haptics.success()
            self.fill(username: login.username, password: pw, userOnly: userOnly, tab: tab)
        }
    }

    private func fill(username: String, password: String, userOnly: Bool, tab: BrowserTab) {
        let submit = Prefs.flag("quickAutoSubmit") ? "true" : "false"
        let js = "window.__novaFill && window.__novaFill(\(Self.js(username)), \(Self.js(userOnly ? "" : password)), \(submit));"
        tab.webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func js(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]),
              let t = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(t.dropFirst().dropLast())
    }

    func show(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.toast == text { self?.toast = nil }
        }
    }
}

// MARK: - Interfaz: botón de inicio rápido, aviso de guardado y aviso informativo

struct QuickLoginPill: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var login = QuickLogin.shared

    var body: some View {
        if let offer = login.offer, offer.tabID == model.activeTabID, !model.isHome {
            HStack(spacing: 2) {
                if offer.logins.count == 1, let only = offer.logins.first {
                    Button { go(only, offer) } label: {
                        label(subtitle: only.username)
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    Menu {
                        ForEach(offer.logins) { l in
                            Button(l.username) { go(l, offer) }
                        }
                    } label: {
                        label(subtitle: "\(offer.logins.count) cuentas guardadas")
                    }
                }
                Button {
                    login.offer = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(NovaTheme.dim)
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Ocultar inicio rápido")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .novaGlass(radius: 22)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func label(subtitle: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "faceid")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NovaTheme.accentGradient))
            VStack(alignment: .leading, spacing: 1) {
                Text("Iniciar sesión rápido")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(NovaTheme.text)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 4)
    }

    private func go(_ l: SavedLogin, _ offer: QuickLogin.Offer) {
        Haptics.tap()
        login.use(l, userOnly: offer.userOnly, in: model.activeTab)
    }
}

struct SavePasswordCard: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var login = QuickLogin.shared

    var body: some View {
        if let p = login.savePrompt, p.tabID == model.activeTabID {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(NovaTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(NovaTheme.accent.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿Guardar contraseña?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NovaTheme.text)
                        Text("\(p.username) · \(p.host)")
                            .font(.system(size: 12))
                            .foregroundColor(NovaTheme.dim)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    Button { login.confirmSave() } label: {
                        Text("Guardar con \(PrivacyStore.biometryName)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NovaTheme.accentGradient))
                    }
                    .buttonStyle(PressableStyle())
                    Button { login.dismissSave() } label: {
                        Text("Ahora no")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(NovaTheme.ink(0.85))
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NovaTheme.surfaceHi))
                    }
                    .buttonStyle(PressableStyle())
                    Menu {
                        Button(role: .destructive) { login.neverSave() } label: {
                            Label("Nunca para este sitio", systemImage: "nosign")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(NovaTheme.ink(0.85))
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(NovaTheme.surfaceHi))
                    }
                }
            }
            .padding(14)
            .novaGlass(radius: 20)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct QuickToastView: View {
    @ObservedObject private var login = QuickLogin.shared

    var body: some View {
        if let text = login.toast {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(NovaTheme.accent2)
                Text(text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(NovaTheme.ink(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(13)
            .novaGlass(radius: 16)
            .onTapGesture { login.toast = nil }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Gestión de contraseñas guardadas

struct SavedLoginsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items = Vault.all

    var body: some View {
        ZStack {
            NovaTheme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(NovaTheme.faint)
                        Text("Aún no hay contraseñas guardadas")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(NovaTheme.text)
                        Text("Cuando inicies sesión en una web, Nova te preguntará si quieres guardarla.")
                            .font(.system(size: 12))
                            .foregroundColor(NovaTheme.dim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { l in
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(NovaTheme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(NovaTheme.accent.opacity(0.15)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.host)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(NovaTheme.text)
                                    Text(l.username)
                                        .font(.system(size: 12))
                                        .foregroundColor(NovaTheme.dim)
                                }
                            }
                            .listRowBackground(NovaTheme.surface)
                            .listRowSeparatorTint(NovaTheme.stroke)
                        }
                        .onDelete { offsets in
                            for i in offsets { Vault.delete(items[i]) }
                            items = Vault.all
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    Text("Desliza hacia la izquierda para eliminar. Las contraseñas solo se leen con \(PrivacyStore.biometryName).")
                        .font(.system(size: 11.5))
                        .foregroundColor(NovaTheme.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                }
            }
        }
        .novaAppearance()
    }

    private var header: some View {
        HStack {
            Text("Contraseñas guardadas")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(NovaTheme.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NovaTheme.dim)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(NovaTheme.surfaceHi))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}
