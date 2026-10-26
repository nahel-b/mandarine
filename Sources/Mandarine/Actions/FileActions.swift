import AppKit
import SwiftUI

enum FileActions {
    static func perform(_ a: FileAction, on urls: [URL]) {
        switch a {
        case .airDrop:
            NSApp.activate(ignoringOtherApps: true)
            if let s = NSSharingService(named: .sendViaAirDrop), s.canPerform(withItems: urls) { s.perform(withItems: urls) }
            else { Toast.shared.fail("AirDrop unavailable", subtitle: "Turn on Wi‑Fi and Bluetooth to use AirDrop.") }
        case .float:
            FloatShelf.shared.add(urls)
        case .searchWeb:
            let q = urls.map { SnippetStore.text(of: $0) }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            var c = URLComponents(string: "https://www.google.com/search"); c?.queryItems = [URLQueryItem(name: "q", value: String(q.prefix(300)))]
            if let u = c?.url { NSWorkspace.shared.open(u) }
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            if urls.count == 1, SnippetStore.isSnippet(urls[0]) {          // texte glissé : on copie le texte, pas un fichier
                pb.setString(SnippetStore.text(of: urls[0]), forType: .string)
                Toast.shared.done("Text copied", subtitle: "\(SnippetStore.wordCount(SnippetStore.text(of: urls[0]))) words")
                return
            }
            pb.writeObjects(urls as [NSURL])
            if urls.allSatisfy({ !$0.isFileURL }) {
                Toast.shared.done(urls.count == 1 ? "Link copied" : "\(urls.count) links copied", subtitle: urls[0].absoluteString)
            } else {
                Toast.shared.done(urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) files", subtitle: "Ready to paste in Finder")
            }
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            let isLink = urls.allSatisfy { !$0.isFileURL }
            pb.setString(urls.map { isLink ? $0.absoluteString : $0.path }.joined(separator: "\n"), forType: .string)
            Toast.shared.done(isLink ? (urls.count == 1 ? "Link copied" : "\(urls.count) links copied") : (urls.count == 1 ? "Path copied" : "\(urls.count) paths copied"),
                              subtitle: isLink ? urls[0].absoluteString : urls[0].path)
        case .move:
            move(urls)
        case .terminal:
            openTerminal(urls)
        case .switchView:
            let s = AppSettings.shared
            s.appearance = s.appearance == .wii ? .wheel : .wii
            Toast.shared.done(s.appearance == .wii ? "Wii view" : "Wheel view", subtitle: "Menu style changed — you can switch back from the ⌃ menu or Settings")
        }
    }

    private static func move(_ urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = urls.count == 1 ? "Move “\(urls[0].lastPathComponent)” to:" : "Move \(urls.count) items to:"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        var moved: [URL] = []
        for u in urls {
            let dest = OutputNaming.unique(folder: dir, base: u.deletingPathExtension().lastPathComponent, ext: u.pathExtension)
            do { try FileManager.default.moveItem(at: u, to: dest); moved.append(dest) }
            catch { Toast.shared.fail("Couldn't move \(u.lastPathComponent)", subtitle: error.localizedDescription); return }
        }
        if let f = moved.first { Toast.shared.done("Moved \(moved.count == 1 ? f.lastPathComponent : "\(moved.count) items")", subtitle: dir.path, reveal: moved) }
    }

    private static func openTerminal(_ urls: [URL]) {
        var dirs: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            let d = isDir.boolValue ? u : u.deletingLastPathComponent()
            if !dirs.contains(d) { dirs.append(d) }
        }
        let bundle = AppSettings.shared.terminalApp == .iterm ? "com.googlecode.iterm2" : "com.apple.Terminal"
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            Toast.shared.fail("\(AppSettings.shared.terminalApp.title) not found", subtitle: "Choose another terminal in Settings.")
            return
        }
        NSWorkspace.shared.open(dirs, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: Float — étagère flottante
final class FloatShelfModel: ObservableObject {
    @Published var files: [URL] = []
    @Published var edge: Edge = .free
    enum Edge: String { case free, left, right }
}

private struct FloatShelfView: View {
    @ObservedObject var model: FloatShelfModel
    var onClose: () -> Void
    var onEdge: (FloatShelfModel.Edge) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Float").font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                Button { onEdge(.left) } label: { Image(systemName: "sidebar.left") }.buttonStyle(.plain)
                Button { onEdge(.right) } label: { Image(systemName: "sidebar.right") }.buttonStyle(.plain)
                Button { model.files.removeAll() } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
            }
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 2).background(WindowDragArea())
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.files, id: \.self) { u in
                        HStack(spacing: 8) {
                            if u.isFileURL {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().frame(width: 28, height: 28)
                            } else {
                                Image(systemName: "link").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.orange).frame(width: 28, height: 28)
                            }
                            Text(u.isFileURL ? u.lastPathComponent : (u.host ?? "") + u.path).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.files.removeAll { $0 == u } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
                        .onDrag { NSItemProvider(object: u as NSURL) }
                    }
                }
            }
            if model.files.isEmpty { Text("Drop files here").font(.system(size: 12)).foregroundStyle(Theme.muted).frame(maxHeight: .infinity) }
        }
        .padding(12)
        .frame(width: 240, height: 300)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.12)))
        .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                    if let u = obj as? URL { DispatchQueue.main.async { if !model.files.contains(u) { model.files.append(u) } } }
                }
            }
            return true
        }
        .padding(10)
    }
}

final class FloatShelf {
    static let shared = FloatShelf()
    private let model = FloatShelfModel()
    private var panel: NSPanel?

    func add(_ urls: [URL]) {
        for u in urls where !model.files.contains(u) { model.files.append(u) }
        show()
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 270, height: 330),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = FirstMouseHostingView(rootView: FloatShelfView(model: model, onClose: { [weak self] in self?.panel?.orderOut(nil) },
                                                                    onEdge: { [weak self] e in self?.pin(e) }))
            panel = p
            pin(.right)
        }
        panel?.orderFrontRegardless()
    }

    private func pin(_ edge: FloatShelfModel.Edge) {
        guard let p = panel, let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let y = f.midY - p.frame.height / 2
        p.setFrameOrigin(NSPoint(x: edge == .left ? f.minX : f.maxX - p.frame.width, y: y))
    }
}

/// Équivalent de `code .` : ouvre le dossier dans Visual Studio Code (ou Insiders / VSCodium / Cursor à défaut).
enum VSCode {
    private static let bundleIDs = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.todesktop.230313mzl4w4u92"]
    static var url: URL? {
        for id in bundleIDs { if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return u } }
        return nil
    }
    static func open(_ folders: [URL]) {
        guard let app = url else {
            Toast.shared.fail("VS Code not found", subtitle: "Install Visual Studio Code to use this action.")
            return
        }
        NSWorkspace.shared.open(folders, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, err in
            if let err = err { DispatchQueue.main.async { Toast.shared.fail("Couldn't open VS Code", subtitle: err.localizedDescription) } }
        }
    }
}
