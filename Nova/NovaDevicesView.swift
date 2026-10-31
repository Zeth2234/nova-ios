import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════════════════════════════
//  Dispositivos (v88): emparejar con Nova para Windows, Puente móvil, Transferencias,
//  pestañas del PC que se ejecutan aquí y gestor de Archivos de Nova.
// ════════════════════════════════════════════════════════════════════════════════════

private struct DCard<Content: View>: View {
    let title: String
    let symbol: String
    var hint: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundColor(NovaTheme.accent)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(NovaTheme.text)
            }
            if let hint = hint {
                Text(hint).font(.system(size: 12.5)).foregroundColor(NovaTheme.dim).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
    }
}

private struct DRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String = ""
    @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(NovaTheme.ink(0.75))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NovaTheme.ink(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundColor(NovaTheme.text).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(NovaTheme.dim).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.vertical, 4)
    }
}

private struct DEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5)).foregroundColor(NovaTheme.dim)
            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12).stroke(NovaTheme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

private func hostOf(_ s: String) -> String {
    (URL(string: s)?.host ?? s).replacingOccurrences(of: "www.", with: "")
}

private struct ToastOverlay: View {
    @ObservedObject var link = NovaLink.shared
    var body: some View {
        if let t = link.toast {
            Text(t)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(NovaTheme.text)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(NovaTheme.surfaceHi))
                .overlay(Capsule().stroke(NovaTheme.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .padding(.bottom, 24)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct NovaLinkToast: View {
    var body: some View { ToastOverlay() }
}

struct NovaDevicesView: View {
    @ObservedObject private var link = NovaLink.shared
    @ObservedObject private var account = NovaAccount.shared
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    if account.phase == .signedIn {
                        bridgeCard
                        filesCard
                        remoteCard
                        devicesCard
                    }
                    Text("Todo viaja directo por tu wifi entre tus dispositivos. Supabase solo guarda que existen y su dirección en tu red; tus pestañas y archivos no pasan por la nube.")
                        .font(.system(size: 11.5)).foregroundColor(NovaTheme.faint)
                        .multilineTextAlignment(.center).padding(.horizontal, 10).padding(.top, 4)
                }
                .padding(16)
            }
            .background(NovaTheme.bg.ignoresSafeArea())
            .navigationTitle("Dispositivos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .refreshable { await link.reloadDevices(); link.connectIfNeeded(force: true) }
        }
        .overlay(alignment: .bottom) { ToastOverlay() }
        .onAppear { link.connectIfNeeded(force: true); Task { await link.reloadDevices() } }
    }

    // MARK: Estado

    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NovaTheme.accentGradient)
                Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 20, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                if account.phase != .signedIn {
                    Text("Inicia sesión").font(.system(size: 16, weight: .semibold)).foregroundColor(NovaTheme.text)
                    Text("Usa la misma cuenta de Nova que en tu PC para emparejarlos.").font(.system(size: 12.5)).foregroundColor(NovaTheme.dim)
                } else if let pc = link.connected {
                    HStack(spacing: 6) {
                        Circle().fill(NovaTheme.good).frame(width: 8, height: 8)
                        Text("Conectado").font(.system(size: 12, weight: .semibold)).foregroundColor(NovaTheme.good)
                    }
                    Text(pc.name).font(.system(size: 16, weight: .semibold)).foregroundColor(NovaTheme.text).lineLimit(1)
                    Text("Archivos hasta \(link.limitText)\(link.isPremium ? " · Premium" : " · más con Premium")").font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                } else {
                    Text(link.connecting ? "Buscando tu PC…" : "Sin conectar").font(.system(size: 16, weight: .semibold)).foregroundColor(NovaTheme.text)
                    Text("Abre Nova en el PC con tu cuenta y en la misma wifi. Si iOS lo pide, permite «Red local».")
                        .font(.system(size: 12.5)).foregroundColor(NovaTheme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if account.phase == .signedIn && link.connected == nil {
                if link.connecting { ProgressView().tint(NovaTheme.accent) }
                else {
                    Button("Reintentar") { link.connectIfNeeded(force: true) }
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NovaTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTheme.stroke, lineWidth: 1))
    }

    // MARK: Puente móvil

    private var bridgeCard: some View {
        DCard(title: "Puente móvil", symbol: "rectangle.on.rectangle", hint: "Las pestañas de tu PC en tiempo real. Tócalas para abrirlas aquí.") {
            Button {
                link.sendTabToPC(model.activeTab.currentURL)
            } label: {
                Label("Enviar esta pestaña al PC", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NovaTheme.accentGradient))
            }
            .disabled(link.connected == nil || model.isHome)
            .opacity(link.connected == nil || model.isHome ? 0.5 : 1)
            if link.connected == nil {
                DEmpty(text: "Conecta con tu PC para ver sus pestañas.")
            } else if link.pcTabs.isEmpty {
                DEmpty(text: "El PC no tiene páginas abiertas.")
            } else {
                ForEach(link.pcTabs) { t in
                    Button { link.openHere(t.url); dismiss() } label: {
                        DRow(symbol: "globe", title: t.title.isEmpty ? hostOf(t.url) : t.title, subtitle: hostOf(t.url)) {
                            Image(systemName: "arrow.down.forward.app").foregroundColor(NovaTheme.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Transferencias

    private var filesCard: some View {
        DCard(title: "Transferencias", symbol: "arrow.left.arrow.right", hint: "Copia o mueve archivos entre el iPhone y el PC. Máximo \(link.limitText) por archivo.") {
            SendToPCButtons()
            NavigationLink { NovaFilesView(rel: "", title: "Archivos de Nova") } label: {
                DRow(symbol: "iphone", title: "Archivos de Nova (este iPhone)", subtitle: "Gestor de almacenamiento · enviar al PC") {
                    Image(systemName: "chevron.right").foregroundColor(NovaTheme.faint)
                }
            }
            .buttonStyle(.plain)
            NavigationLink { PCFilesView(path: "", title: "Mi PC", onPick: nil) } label: {
                DRow(symbol: "desktopcomputer", title: "Archivos del PC", subtitle: link.connected == nil ? "Conecta con tu PC" : "Carpetas que compartiste en Nova para Windows") {
                    Image(systemName: "chevron.right").foregroundColor(NovaTheme.faint)
                }
            }
            .buttonStyle(.plain)
            .disabled(link.connected == nil)
            ForEach(Array(link.transfers.values)) { x in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(x.incoming ? "↓" : "↑") \(x.name) · \(LocalFiles.size(x.got)) de \(LocalFiles.size(x.size))")
                        .font(.system(size: 12)).foregroundColor(NovaTheme.dim).lineLimit(1)
                    ProgressView(value: x.fraction).tint(NovaTheme.accent)
                }
            }
        }
    }

    // MARK: Pestañas del PC ejecutándose aquí

    private var remoteCard: some View {
        DCard(title: "Pestañas del PC en este iPhone", symbol: "cpu", hint: "En el PC: clic derecho en una pestaña → «Ejecutar en el iPhone». Se ejecuta aquí a tamaño de escritorio y la ves en el PC. Mantén Nova abierto.") {
            if link.remoteTabs.isEmpty {
                DEmpty(text: "Ninguna pestaña del PC se está ejecutando aquí.")
            } else {
                ForEach(link.remoteTabs) { h in RemoteTabRow(host: h) }
                Text("Memoria de Nova ahora: \(RemoteTabHost.appMemoryMB()) MB")
                    .font(.system(size: 11.5)).foregroundColor(NovaTheme.faint)
            }
        }
    }

    // MARK: Dispositivos

    private var devicesCard: some View {
        DCard(title: "Tus dispositivos", symbol: "person.badge.key", hint: "Se emparejan solos los dispositivos con tu misma cuenta.") {
            if link.devices.isEmpty {
                DEmpty(text: "Aún no hay otros dispositivos. Abre Nova en tu PC e inicia sesión con esta cuenta.")
            } else {
                ForEach(link.devices) { d in
                    DRow(symbol: d.platform == "ios" ? "iphone" : "desktopcomputer", title: d.name,
                         subtitle: link.connected?.id == d.id ? "Conectado ahora" : (d.updatedAt.map { "Visto " + RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "")) {
                        Menu {
                            if d.platform == "windows" && link.connected?.id != d.id {
                                Button { link.connectIfNeeded(force: true) } label: { Label("Conectar", systemImage: "link") }
                            }
                            if link.connected?.id == d.id {
                                Button { link.disconnect() } label: { Label("Desconectar", systemImage: "link.badge.plus") }
                            }
                            Button(role: .destructive) { Task { await link.forget(d) } } label: { Label("Olvidar", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundColor(NovaTheme.dim)
                        }
                    }
                }
            }
        }
    }
}

private struct RemoteTabRow: View {
    @ObservedObject var host: RemoteTabHost
    var body: some View {
        DRow(symbol: "display", title: host.title.isEmpty ? hostOf(host.urlText) : host.title, subtitle: "\(hostOf(host.urlText)) · \(host.fps) fps") {
            Button(role: .destructive) { NovaLink.shared.stopRemoteTab(host) } label: {
                Text("Detener").font(.system(size: 13, weight: .semibold)).foregroundColor(NovaTheme.danger)
            }
        }
    }
}

// MARK: - Archivos de Nova (gestor de almacenamiento del iPhone)

struct NovaFilesView: View {
    let rel: String
    let title: String
    @ObservedObject private var link = NovaLink.shared
    @State private var items: [LinkFileItem] = []
    @State private var used: Int64 = 0
    @State private var free: Int64 = 0
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var confirmDelete: LinkFileItem?

    var body: some View {
        List {
            Section {
                SendToPCButtons()
                HStack(spacing: 10) {
                    Button { importing = true } label: {
                        Label("Añadir de Archivos", systemImage: "folder.badge.plus").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    PhotosPicker(selection: $photos, maxSelectionCount: 20, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Label("Añadir de Fotos", systemImage: "photo.badge.plus").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }
            } footer: {
                Text("«Enviar» manda el archivo directo al PC. «Añadir» lo guarda en Nova para enviarlo cuando quieras.")
            }
            if rel.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Nova usa \(LocalFiles.size(used))").font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text("Libres \(LocalFiles.size(free))").font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                        }
                        ProgressView(value: used + free > 0 ? Double(used) / Double(used + free) : 0).tint(NovaTheme.accent)
                        Text("También están en la app Archivos → En mi iPhone → Nova.").font(.system(size: 11.5)).foregroundColor(NovaTheme.faint)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                if items.isEmpty {
                    Text("Aquí no hay archivos. Añádelos arriba o envíalos desde el PC.")
                        .font(.system(size: 13)).foregroundColor(NovaTheme.dim)
                }
                ForEach(items) { it in
                    if it.dir {
                        NavigationLink { NovaFilesView(rel: it.path, title: it.name) } label: {
                            Label(it.name, systemImage: "folder.fill")
                        }
                    } else {
                        fileRow(it)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $importing) {
            DocumentPicker { urls in importFiles(urls) }.ignoresSafeArea()
        }
        .onChange(of: photos) { sel in
            guard !sel.isEmpty else { return }
            Task { await importPhotos(sel); photos = [] }
        }
        .confirmationDialog("¿Eliminar «\(confirmDelete?.name ?? "")»?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let it = confirmDelete, let u = LocalFiles.resolve(it.path) { try? FileManager.default.removeItem(at: u) }
                confirmDelete = nil
                reload()
            }
        }
        .onAppear(perform: reload)
        .onChange(of: link.transfers.count) { _ in reload() }
    }

    /// v89 · Toda la fila abre las acciones (antes solo el botón «…», y salían desactivadas sin explicar por qué).
    @ViewBuilder private func fileRow(_ it: LinkFileItem) -> some View {
        let url = LocalFiles.resolve(it.path)
        Menu {
            Section(link.connected == nil ? "Conecta con tu PC para enviar" : "Enviar a \(link.connected?.name ?? "tu PC")") {
                Button { send(it, move: false) } label: { Label("Enviar al PC (copiar)", systemImage: "arrow.up.doc") }
                Button { send(it, move: true) } label: { Label("Mover al PC", systemImage: "arrow.right.doc.on.clipboard") }
            }
            if let url = url {
                ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
            }
            Button(role: .destructive) { confirmDelete = it } label: { Label("Eliminar", systemImage: "trash") }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: it.name)).foregroundColor(NovaTheme.accent).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.name).lineLimit(1).foregroundColor(NovaTheme.text)
                    Text(LocalFiles.size(it.size)).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                }
                Spacer()
                Image(systemName: "paperplane").font(.system(size: 15)).foregroundColor(NovaTheme.accent)
            }
            .contentShape(Rectangle())
        }
    }

    private func send(_ it: LinkFileItem, move: Bool) {
        guard link.connected != nil else {
            link.flash("Abre Nova en el PC (misma cuenta y wifi) y espera a que salga «Conectado».")
            link.connectIfNeeded(force: true)
            return
        }
        link.flash(move ? "Moviendo «\(it.name)» al PC…" : "Enviando «\(it.name)» al PC…")
        Task { await link.sendToPC(it.path, move: move); reload() }
    }

    private func icon(for name: String) -> String {
        let t = UTType(filenameExtension: (name as NSString).pathExtension)
        if t?.conforms(to: .image) == true { return "photo" }
        if t?.conforms(to: .movie) == true { return "film" }
        if t?.conforms(to: .audio) == true { return "music.note" }
        if t?.conforms(to: .pdf) == true { return "doc.richtext" }
        if t?.conforms(to: .archive) == true { return "doc.zipper" }
        return "doc"
    }

    private func reload() {
        items = LocalFiles.list(rel)
        if rel.isEmpty { used = LocalFiles.usedBytes(); free = LocalFiles.freeBytes() }
    }

    private func importFiles(_ urls: [URL]) {
        guard let dir = LocalFiles.resolve(rel) else { return }
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.copyItem(at: u, to: LocalFiles.unique(in: dir, name: u.lastPathComponent))
        }
        reload()
        link.flash("Añadido a Archivos de Nova")
    }

    private func importPhotos(_ sel: [PhotosPickerItem]) async {
        guard let dir = LocalFiles.resolve(rel) else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var n = 0
        for item in sel {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            n += 1
            let name = "Foto \(fmt.string(from: Date()))\(n > 1 ? " \(n)" : "").\(ext)"
            try? data.write(to: LocalFiles.unique(in: dir, name: name))
        }
        reload()
        if n > 0 { link.flash(n == 1 ? "Foto añadida" : "\(n) fotos añadidas") }
    }
}

// MARK: - Archivos del PC (carpetas compartidas en Nova para Windows)

struct PCFilesView: View {
    let path: String
    let title: String
    /// Si no es nil, se está eligiendo un archivo para una web del iPhone.
    let onPick: ((LinkFileItem) -> Void)?
    @ObservedObject private var link = NovaLink.shared
    @State private var items: [LinkFileItem] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let e = error {
                Text(e).font(.system(size: 13)).foregroundColor(NovaTheme.dim)
            } else if items.isEmpty {
                Text(path.isEmpty ? "No compartes ninguna carpeta. En el PC: clic derecho en una pestaña → Dispositivos Nova → «Compartir carpeta…»." : "Carpeta vacía.")
                    .font(.system(size: 13)).foregroundColor(NovaTheme.dim)
            }
            ForEach(items) { it in
                if it.dir {
                    NavigationLink { PCFilesView(path: it.path, title: it.name, onPick: onPick) } label: {
                        Label(it.name, systemImage: "folder.fill")
                    }
                } else if let onPick = onPick {
                    Button { onPick(it) } label: {
                        HStack {
                            Label(it.name, systemImage: "doc").lineLimit(1)
                            Spacer()
                            Text(LocalFiles.size(it.size)).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "doc").foregroundColor(NovaTheme.accent).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.name).lineLimit(1)
                            Text(LocalFiles.size(it.size)).font(.system(size: 12)).foregroundColor(NovaTheme.dim)
                        }
                        Spacer()
                        Menu {
                            Button { Task { await link.downloadFromPC(it, move: false) } } label: { Label("Descargar al iPhone (copiar)", systemImage: "arrow.down.doc") }
                            Button { Task { await link.downloadFromPC(it, move: true); await load() } } label: { Label("Mover al iPhone", systemImage: "arrow.down.right.and.arrow.up.left") }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 19)).foregroundColor(NovaTheme.dim)
                        }
                    }
                }
            }
            if !link.transfers.isEmpty {
                Section("Transferencias") {
                    ForEach(Array(link.transfers.values)) { x in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(x.name).font(.system(size: 12)).lineLimit(1)
                            ProgressView(value: x.fraction).tint(NovaTheme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = items.isEmpty
        let r = await link.listPC(path)
        items = r.items
        error = r.error
        loading = false
    }
}

/// Hoja que aparece cuando una web del iPhone pide un archivo y eliges «Mi PC».
struct PCPickSheet: View {
    let request: PCPickRequest
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var link = NovaLink.shared
    var body: some View {
        NavigationStack {
            Group {
                if link.connected == nil {
                    Text("Tu PC no está conectado. Abre Nova en el PC (misma wifi).").foregroundColor(NovaTheme.dim).padding()
                } else {
                    PCFilesView(path: "", title: "Elegir del PC", onPick: { item in
                        let wv = request.webView
                        dismiss()
                        Task { await link.injectFromPC(item, into: wv) }
                    })
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}


// MARK: - v90 · Enviar directo al PC (Archivos y Fotos) y selector de documentos fiable

/// Selector de la app Archivos de UIKit (asCopy: iOS copia el archivo para Nova; sin permisos raros).
/// Sustituye a .fileImporter, que dentro de esta hoja no devolvía nada al pulsar «Abrir».
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}

struct SendToPCButtons: View {
    @ObservedObject private var link = NovaLink.shared
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    var body: some View {
        HStack(spacing: 10) {
            Button { picking = true } label: {
                Label("Enviar archivos al PC", systemImage: "doc.badge.arrow.up")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent).tint(NovaTheme.accent)
            PhotosPicker(selection: $photos, maxSelectionCount: 20, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                Label("Enviar fotos", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent).tint(NovaTheme.accent2)
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { urls in Task { await link.sendExternal(urls) } }.ignoresSafeArea()
        }
        .onChange(of: photos) { sel in
            guard !sel.isEmpty else { return }
            let items = sel
            photos = []
            Task { await link.sendPhotos(items) }
        }
    }
}

// MARK: - v90 · Pantalla «Se está compartiendo»

/// Mientras el PC usa el iPhone, Nova solo muestra esto: no puedes tocar nada más (para no ralentizar la
/// pestaña), solo dejar de compartir o desconectar. «Pantalla negra» apaga casi del todo la pantalla.
struct NovaSharingCover: View {
    @ObservedObject private var link = NovaLink.shared
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if link.dimmed {
                VStack(spacing: 8) {
                    Text("Compartiendo con \(link.connected?.name ?? "tu PC")")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.35))
                    Text("Toca para encender la pantalla").font(.system(size: 11)).foregroundColor(.white.opacity(0.22))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { link.setDimmed(false) }
            } else {
                VStack(spacing: 22) {
                    Spacer()
                    ZStack {
                        Circle().fill(NovaTheme.accent.opacity(0.18)).frame(width: 110, height: 110)
                        Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 44, weight: .semibold)).foregroundColor(.white)
                    }
                    VStack(spacing: 6) {
                        Text("Se está compartiendo").font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                        Text("\(link.connected?.name ?? "Tu PC") está usando este iPhone para ejecutar \(link.remoteTabs.count == 1 ? "una pestaña" : "\(link.remoteTabs.count) pestañas").")
                            .font(.system(size: 14)).foregroundColor(.white.opacity(0.65)).multilineTextAlignment(.center)
                    }
                    VStack(spacing: 8) {
                        ForEach(link.remoteTabs) { h in SharingRow(host: h) }
                    }
                    .padding(.horizontal, 20)
                    Text("La pantalla no se apagará sola. Si bloqueas el iPhone, la imagen se pausa y vuelve al desbloquear.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.45)).multilineTextAlignment(.center).padding(.horizontal, 30)
                    Spacer()
                    VStack(spacing: 10) {
                        Button { link.setDimmed(true) } label: {
                            Label("Pantalla negra (ahorra batería)", systemImage: "moon.fill")
                                .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundColor(.white).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
                        }
                        Button { link.stopSharing() } label: {
                            Text("Dejar de compartir")
                                .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundColor(.white).background(RoundedRectangle(cornerRadius: 14).fill(NovaTheme.danger))
                        }
                        Button { link.stopSharing(); link.disconnect() } label: {
                            Text("Desconectar del PC").font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .statusBarHidden(link.dimmed)
    }
}

private struct SharingRow: View {
    @ObservedObject var host: RemoteTabHost
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.green).frame(width: 8, height: 8)
            Text(host.title.isEmpty ? (URL(string: host.urlText)?.host ?? host.urlText) : host.title)
                .font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
            Spacer()
            Text("\(host.fps) fps").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }
}
