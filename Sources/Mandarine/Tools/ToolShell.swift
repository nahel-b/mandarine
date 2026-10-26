import UniformTypeIdentifiers
import AppKit
import SwiftUI

/// Cadre commun des fenêtres d'outils : ✕ rond à gauche, titre centré, contenu, pied avec action.
struct ToolShell<Content: View, Footer: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text.opacity(0.75))
                            .frame(width: 28, height: 28).background(Circle().fill(Color.black.opacity(0.07)))
                            .frame(width: 40, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 8).frame(height: 48).background(WindowDragArea()).zIndex(1)
            Divider().opacity(0.6)
            content().padding(16)
            Divider().opacity(0.6)
            HStack(spacing: 8) { footer() }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .background(Color.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}

/// Sélecteurs de fichiers non modaux : s'affichent au-dessus des fenêtres flottantes et rendent ensuite la main à la fenêtre d'outil.
enum Pickers {
    static func files(_ types: [UTType], _ completion: @escaping ([URL]) -> Void) {
        let back = NSApp.keyWindow
        let p = NSOpenPanel()
        p.allowedContentTypes = types
        p.allowsMultipleSelection = true
        p.level = .modalPanel
        p.begin { r in
            NSApp.activate(ignoringOtherApps: true)
            back?.makeKeyAndOrderFront(nil)
            completion(r == .OK ? p.urls : [])
        }
    }

    static func image(_ completion: @escaping (URL?) -> Void) {
        let back = NSApp.keyWindow
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.level = .modalPanel
        p.begin { r in
            NSApp.activate(ignoringOtherApps: true)
            back?.makeKeyAndOrderFront(nil)
            completion(r == .OK ? p.url : nil)
        }
    }
}

/// Le premier clic sur une fenêtre d'outil est transmis aux boutons (sinon il ne fait qu'activer la fenêtre).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Un glissement dans le contenu (poignées, recadrage, curseurs…) ne doit jamais déplacer la fenêtre.
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Zone qui déplace la fenêtre quand on la fait glisser (barre de titre uniquement).
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView { override var mouseDownCanMoveWindow: Bool { true } }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class ToolWindow: NSWindow {
    /// Échap ferme la fenêtre — mais seulement pour un vrai appui sur Échap (pas pour une autre commande d'annulation venue d'ailleurs).
    override func cancelOperation(_ sender: Any?) {
        guard let e = NSApp.currentEvent, e.type == .keyDown, e.keyCode == 53 else { return }
        close()
    }

    /// Déplacement de la fenêtre : un clic dans la barre de titre (hors bouton ✕) lance le déplacement natif.
    /// Fait ici plutôt que dans une vue SwiftUI, dont la prise en compte des clics n'est pas fiable pour cela.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let content = contentView {
            let p = event.locationInWindow, b = content.bounds
            if p.y > b.height - 48, p.x > 56, p.x < b.width - 8 { dragWindow(from: event); return }
        }
        super.sendEvent(event)
    }

    private func dragWindow(from down: NSEvent) {
        let start = convertPoint(toScreen: down.locationInWindow), origin = frame.origin
        while let e = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let now = convertPoint(toScreen: e.locationInWindow)
            // locationInWindow est relatif à la position actuelle de la fenêtre : on repart de l'origine d'avant le glissement
            let dx = now.x - start.x - (frame.origin.x - origin.x), dy = now.y - start.y - (frame.origin.y - origin.y)
            setFrameOrigin(NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy))
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {   // ⌘W aussi
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ToolWindowController: NSObject, NSWindowDelegate {
    private static var open: [ToolWindowController] = []
    static var hasOpenWindows: Bool { !open.isEmpty }
    private(set) var window: ToolWindow!

    private static var lastOpened: (key: String, date: Date)?

    static func present(_ id: ToolID, urls: [URL]) {
        // Un même dépôt ne doit pas ouvrir deux fenêtres identiques l'une sur l'autre
        let key = id.rawValue + "|" + urls.map(\.absoluteString).joined(separator: "|")
        if let last = lastOpened, last.key == key, Date().timeIntervalSince(last.date) < 1.5 { return }
        lastOpened = (key, Date())
        present { close in ToolRegistry.view(for: id, urls: urls, close: close) }
    }

    /// Fenêtre d'outil avec un contenu fourni par l'appelant (utilisé quand l'outil a besoin de données déjà lues).
    static func present(_ make: (@escaping () -> Void) -> AnyView) {
        let c = ToolWindowController()
        let close: () -> Void = { [weak c] in c?.close() }
        let root = make(close)
        let host = FirstMouseHostingView(rootView: root.environment(\.colorScheme, .light))
        let size = host.fittingSize
        let w = ToolWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: max(size.width, 380), height: max(size.height, 200))),
                           styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = host
        w.delegate = c
        w.isReleasedWhenClosed = false
        c.window = w
        w.center()
        open.append(c)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
    func windowWillClose(_ notification: Notification) {
        window.contentView = nil
        ToolWindowController.open.removeAll { $0 === self }
    }
}

/// Quels outils ont une implémentation (les autres sont grisés dans la roue).
enum ToolAvailability {
    static func isImplemented(_ id: ToolID) -> Bool {
        switch id {
        case .removeBackground:
            return BackgroundRemover.isAvailable
        case .resizeImage, .rotateImage, .extractImages, .quickLook, .davinciTree, .videoSnapshots:
            return true
        case .openInCode:
            return VSCode.url != nil
        case .downloadMP3, .downloadMP4, .downloadWAV, .speakText:
            return true
        case .translateText:
            return SnippetEngine.canTranslate
        case .summarizeText:
            return SnippetEngine.canSummarize
        case .extractAudio, .encodeVideo:
            return FFmpeg.isAvailable
        case .compress, .metadata, .editImage, .annotateImage, .frameImage, .cropImage, .redactImage, .createCollage,
             .mergePDF, .organizePDF, .splitPDF, .extractArchive, .ocr, .tagSelect, .faceSelect, .scanDocument:
            return true
        case .trimVideo, .cropVideo, .changeVideoSpeed, .joinVideos, .splitVideo, .redactVideo, .muteVideo,
             .normalizeAudio, .audioToVideo, .trimAudio, .audioChannels, .redactAudio:
            return FFmpeg.isAvailable
        }
    }
}
