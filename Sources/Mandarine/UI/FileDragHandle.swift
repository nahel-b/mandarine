import AppKit
import SwiftUI

/// Zone transparente posée sur une notification : on attrape les fichiers créés et on les dépose où l'on veut
/// (Mail, un navigateur, un dossier du Finder… ou la roue de Mandarine, qui s'ouvre comme pour n'importe quel glisser).
struct FileDragHandle: NSViewRepresentable {
    let urls: [URL]
    let text: String          // sans fichier à emporter, la ligne emporte son texte
    let onBegin: () -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ v: FileDragView, context: Context) {
        v.urls = urls; v.text = text; v.onBegin = onBegin; v.onEnd = onEnd
        v.toolTip = urls.isEmpty ? L("Drag this message anywhere") : (urls.count == 1 ? L("Drag this file anywhere") : L("Drag these \(urls.count) files anywhere"))
    }
}

/// NSHostingView répond lui-même aux clics sur tout ce que SwiftUI dessine : la poignée posée en surimpression ne les recevait jamais.
/// Ici, un clic dans la zone d'une poignée lui est donné d'abord (les boutons Show, Cancel, ✕ sont hors de cette zone).
final class ToastHostingView: NSHostingView<ToastStack> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if let handle = Self.handles(in: self).first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: self).contains(p) }) { return handle }
        return super.hitTest(point)
    }
    /// Balayage de deux doigts vers la droite : fait partir la notification sous le pointeur (voir ToastCenter.feedSwipe). La molette d'une souris ne fait rien.
    override func scrollWheel(with e: NSEvent) {
        guard e.phase != [] || e.momentumPhase != [] else { super.scrollWheel(with: e); return }
        if e.momentumPhase != [] { return }                       // l'inertie qui suit le geste : sans effet
        let p = convert(e.locationInWindow, from: nil)
        let point = CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y)
        let finger: CGFloat = e.isDirectionInvertedFromDevice ? 1 : -1      // sens du doigt, quel que soit le réglage « défilement naturel »
        rootView.center.feedSwipe(phase: e.phase, dx: e.scrollingDeltaX * finger, dy: e.scrollingDeltaY * finger, at: point)
    }

    func debugHandles() -> [NSRect] { Self.handles(in: self).map { $0.convert($0.bounds, to: self) } }

    private static func handles(in view: NSView) -> [FileDragView] {
        view.subviews.flatMap { ($0 as? FileDragView).map { [$0] } ?? handles(in: $0) }
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var text = ""
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    private var downAt: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, !urls.isEmpty || !text.isEmpty else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }          // un simple clic ne lance rien
        downAt = nil
        let at = convert(start, from: nil)
        var items: [NSDraggingItem] = []
        if urls.isEmpty {
            let item = NSDraggingItem(pasteboardWriter: text as NSString)
            let icon = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
            icon.size = NSSize(width: 40, height: 40)
            item.setDraggingFrame(NSRect(x: at.x - 20, y: at.y - 20, width: 40, height: 40), contents: icon)
            items.append(item)
        }
        for (i, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 48, height: 48)
            // seules les trois premières icônes sont dessinées (les fichiers suivants sont tout de même transportés)
            item.setDraggingFrame(NSRect(x: at.x - 24, y: at.y - 24, width: 48, height: 48), contents: i < 3 ? icon : nil)
            items.append(item)
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) { downAt = nil }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }          // ⇧ ⌘ ⌥ ⌃ servent à ouvrir la roue, pas à changer l'opération
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { onBegin() }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { onEnd() }
}
