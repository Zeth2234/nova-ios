import SwiftUI
import UIKit

// MARK: - Campo de texto nativo (selecciona todo al enfocar, como Safari/Chrome)

struct AddressField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.keyboardType = .webSearch
        tf.returnKeyType = .go
        tf.keyboardAppearance = .default
        tf.textColor = NovaTheme.uiText
        tf.tintColor = UIColor.nova(light: UIColor(hex: 0x6A55E6), dark: UIColor(hex: 0x8D7CFF))
        tf.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NovaTheme.uiInk(0.38)])
        tf.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        if tf.text != text { tf.text = text }
        if isFocused, !tf.isFirstResponder {
            DispatchQueue.main.async { tf.becomeFirstResponder() }
        } else if !isFocused, tf.isFirstResponder {
            DispatchQueue.main.async { tf.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressField
        init(_ parent: AddressField) { self.parent = parent }

        @objc func changed(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
                tf.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }
    }
}

// MARK: - Sugerencias bajo la barra mientras se edita

struct AddressSuggestions: View {
    @ObservedObject var model: BrowserModel
    @Binding var isEditing: Bool

    private var query: String { model.omniText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var unchanged: Bool { query == (model.currentURL?.absoluteString ?? "") }
    private var looksLikeURL: Bool { query.contains(".") && !query.contains(" ") }
    private var engine: SearchEngine { SearchEngine.current }

    var body: some View {
        ZStack(alignment: .top) {
            Color.nova(light: Color.black.opacity(0.28), dark: Color.black.opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                if query.isEmpty || unchanged {
                    pageActions
                } else {
                    typedActions
                }
            }
            .novaCard(radius: 20)
            .shadow(color: NovaTheme.shadow(0.4), radius: 20, y: 10)
            .padding(.horizontal, 12)
            .padding(.top, 2)
        }
    }

    // MARK: Acciones

    @ViewBuilder private var typedActions: some View {
        if looksLikeURL {
            row(icon: tile("arrow.up.right", NovaTheme.accent),
                title: "Ir a \(query)",
                subtitle: "Abrir esta dirección") {
                go(query)
            }
            divider
        }
        row(icon: EngineBadge(engine: engine, size: 34),
            title: "Buscar «\(query)»",
            subtitle: "con \(engine.name)") {
            search()
        }
    }

    @ViewBuilder private var pageActions: some View {
        if let url = model.currentURL {
            row(icon: tile("link", NovaTheme.accent2),
                title: "Copiar enlace",
                subtitle: url.host ?? url.absoluteString) {
                UIPasteboard.general.string = url.absoluteString
                Haptics.success()
                close()
            }
            divider
            ShareLink(item: url) {
                rowLabel(icon: tile("square.and.arrow.up", NovaTheme.good),
                         title: "Compartir página",
                         subtitle: "Enviar este enlace")
            }
            .buttonStyle(PressableStyle())
            divider
        }
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
            Text("Escribe para buscar con \(engine.name) o ir a una web")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(NovaTheme.faint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    // MARK: Piezas

    private var divider: some View {
        Rectangle().fill(NovaTheme.stroke).frame(height: 1).padding(.leading, 62)
    }

    private func tile(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.15)))
    }

    private func rowLabel<Icon: View>(icon: Icon, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(NovaTheme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(NovaTheme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NovaTheme.faint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func row<Icon: View>(icon: Icon, title: String, subtitle: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Acciones

    private func close() {
        isEditing = false
        model.omniText = model.currentURL?.absoluteString ?? ""
    }

    private func go(_ text: String) {
        isEditing = false
        model.load(text)
    }

    private func search() {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        isEditing = false
        model.load(engine.searchPrefix + encoded)
    }
}
