import AppKit
import SwiftUI

/// Les sons de l'étagère : ceux de la Wii pour « Chaînes », ceux des roues pour « Pétales ».
enum ShelfSound {
    private static var wii: Bool { AppSettings.shared.shelfStyle == "channels" }
    static func open() { if wii { Feedback.shared.play(.open) } else { Feedback.shared.open() } }
    static func close() { if wii { Feedback.shared.play(.close) } }
    static func hover() { if wii { Feedback.shared.play(.hover) } else { Feedback.shared.tick() } }
    static func press() { if wii { Feedback.shared.play(.press) } else { Feedback.shared.tick() } }
    static func drop() { if wii { Feedback.shared.play(.drop) } else { Feedback.shared.drop() } }
    static func remove() { if wii { Feedback.shared.play(.release) } else { Feedback.shared.tick() } }
}

/// Ce qu'on fait d'un élément de l'étagère en dehors des vues.
enum ShelfActions {
    /// Montre le fichier dans le Finder, ouvre le lien dans le navigateur, ou copie le texte.
    static func reveal(_ it: ShelfItem) {
        switch it.payload {
        case .file(let u): NSWorkspace.shared.activateFileViewerSelecting([u])
        case .link(let u): NSWorkspace.shared.open(u)
        case .text(let t): copy(.text(t))
        case nil: break
        }
    }
    /// Double clic : ouvre le fichier (un dossier s'ouvre dans le Finder), le lien dans le navigateur ; un texte est copié.
    static func open(_ items: [ShelfItem]) {
        for i in items {
            switch i.payload {
            case .file(let u): NSWorkspace.shared.open(u)
            case .link(let u): NSWorkspace.shared.open(u)
            default: break
            }
        }
        if items.allSatisfy({ if case .text = $0.payload { return true } else { return false } }) { copy(items) }
    }
    /// Pour une sélection : tous les fichiers ensemble dans le Finder, tous les liens ouverts.
    static func reveal(_ items: [ShelfItem]) {
        let files = items.compactMap { i -> URL? in if case .file(let u) = i.payload { return u } else { return nil } }
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
        for i in items { if case .link(let u) = i.payload { NSWorkspace.shared.open(u) } }
        let texts = items.compactMap { i -> String? in if case .text(let t) = i.payload { return t } else { return nil } }
        if files.isEmpty, items.allSatisfy({ if case .text = $0.payload { return true } else { return false } }), !texts.isEmpty { copy(items) }
    }
    static func copy(_ items: [ShelfItem]) {
        let pb = NSPasteboard.general; pb.clearContents()
        var objects: [NSPasteboardWriting] = []
        var texts: [String] = []
        for i in items {
            switch i.payload {
            case .file(let u), .link(let u): objects.append(u as NSURL)
            case .text(let t): texts.append(t)
            case nil: break
            }
        }
        if !texts.isEmpty { objects.append(texts.joined(separator: "\n") as NSString) }
        pb.writeObjects(objects)
    }
    static func copy(_ p: ShelfPayload?) {
        let pb = NSPasteboard.general; pb.clearContents()
        switch p {
        case .file(let u): pb.writeObjects([u as NSURL])
        case .link(let u): pb.writeObjects([u as NSURL]); pb.setString(u.absoluteString, forType: .string)
        case .text(let t): pb.setString(t, forType: .string)
        case nil: break
        }
    }
}

/// La sélection comme dans le Finder : un clic choisit l'élément seul (un deuxième clic le lâche), ⌘-clic ajoute ou retire, ⇧-clic prend tout
/// ce qui se trouve entre le dernier élément cliqué et celui-ci (dans l'ordre d'affichage).
enum ShelfSelecting {
    static func click(_ id: UUID, _ flags: NSEvent.ModifierFlags, order: [UUID], selection: inout Set<UUID>, anchor: inout UUID?) {
        if flags.contains(.shift), let b = order.firstIndex(of: id) {
            let a = anchor.flatMap { order.firstIndex(of: $0) } ?? order.firstIndex(where: { selection.contains($0) }) ?? b
            selection = Set(order[min(a, b)...max(a, b)])
            if anchor == nil { anchor = order[a] }
            return
        }
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
            return
        }
        if selection == [id] { selection = []; anchor = nil } else { selection = [id]; anchor = id }
    }
}

/// Zone transparente posée sur un élément : un clic le sélectionne, glisser l'emporte (vers un dossier, une app, un navigateur… ou la roue de
/// Mandarine, qui s'ouvre comme pour n'importe quel glisser), le survol met à jour la pastille d'information.
struct ShelfDragSource: NSViewRepresentable {
    let item: ShelfItem
    var group: [ShelfItem] = []                 // avec une sélection de plusieurs éléments : tout ce qui part ensemble
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> ShelfDragView { ShelfDragView() }
    func updateNSView(_ v: ShelfDragView, context: Context) { v.item = item; v.group = group.isEmpty ? [item] : group; v.onClick = onClick; v.onHover = onHover }
}

final class ShelfDragView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var group: [ShelfItem] = []
    private var payload: ShelfPayload? { item?.payload }
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }
    private var downAt: NSPoint?
    private var mayMove = false          // ⌥ tenue au départ du glisser : le Finder peut déplacer (même disque) ; sinon c'est toujours une copie
    private var refs: [(old: URL, ref: URL)] = []          // adresses « par référence » : elles suivent un fichier déplacé

    /// Clic droit : localiser, copier, enlever.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item = item, let payload = payload else { return nil }
        let all = group.isEmpty ? [item] : group
        let menu = NSMenu()
        if all.contains(where: { if case .file = $0.payload { return true } else { return false } }) { menu.addItem(Self.entry(L("Locate"), "magnifyingglass") { ShelfActions.reveal(all) }) }
        else if case .link = payload { menu.addItem(Self.entry(L("Open"), "safari") { ShelfActions.reveal(all) }) }
        menu.addItem(Self.entry(L("Copy"), "doc.on.doc") { ShelfActions.copy(all) })
        let allPinned = all.allSatisfy(\.pinned)
        menu.addItem(Self.entry(allPinned ? L("Unpin") : L("Pin"), allPinned ? "pin.slash" : "pin") { Task { @MainActor in ShelfStore.shared.setPinned(Set(all.map(\.id)), !allPinned) } })
        menu.addItem(.separator())
        menu.addItem(Self.entry(all.count > 1 ? L("Take \(all.count) items off the shelf") : L("Take off the shelf"), "trash") {
            Task { @MainActor in ShelfSound.remove(); ShelfStore.shared.remove(Set(all.map(\.id))) }
        })
        return menu
    }

    private final class Action: NSObject { let run: () -> Void; init(_ r: @escaping () -> Void) { run = r }; @objc func fire() { run() } }
    private static func entry(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(run)
        let m = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        m.target = a; m.representedObject = a          // l'objet doit vivre autant que l'entrée
        m.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return m
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onHover(true); Task { @MainActor in ShelfSound.hover() } }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow; Task { @MainActor in ShelfPanelController.shared.takeKeyboard() } }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let payload = payload else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }          // un simple clic ne lance rien
        downAt = nil
        let at = convert(start, from: nil)
        let all = group.isEmpty ? [item!] : group
        var dragged: [NSDraggingItem] = []
        for (n, it) in all.enumerated() {
            guard let pl = it.payload else { continue }
            let di: NSDraggingItem
            let icon: NSImage
            switch pl {
            case .file(let u): di = NSDraggingItem(pasteboardWriter: u as NSURL); icon = NSWorkspace.shared.icon(forFile: u.path)
            case .link(let u):          // un vrai lien : adresse + texte, jamais un fichier .webloc
                let pb = NSPasteboardItem()
                pb.setString(u.absoluteString, forType: .URL)
                pb.setString(u.absoluteString, forType: NSPasteboard.PasteboardType("public.url"))
                pb.setString(u.absoluteString, forType: .string)
                di = NSDraggingItem(pasteboardWriter: pb); icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
            case .text(let t): di = NSDraggingItem(pasteboardWriter: t as NSString); icon = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage()
            }
            icon.size = NSSize(width: 48, height: 48)
            di.setDraggingFrame(NSRect(x: at.x - 24, y: at.y - 24, width: 48, height: 48), contents: n < 3 ? icon : nil)      // seules trois icônes sont dessinées
            dragged.append(di)
        }
        guard !dragged.isEmpty else { return }
        mayMove = event.modifierFlags.contains(.option)
        let session = beginDraggingSession(with: dragged, event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = downAt != nil
        downAt = nil
        if wasClick {
            if event.clickCount >= 2 { let all = group.isEmpty ? (item.map { [$0] } ?? []) : group; ShelfActions.open(all); Task { @MainActor in ShelfSound.press() } }          // double clic : ouvrir
            else { onClick(event.modifierFlags); Task { @MainActor in ShelfSound.press() } }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { mayMove && context != .withinApplication ? [.copy, .move] : .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }          // ⇧ ⌘ ⌥ ⌃ servent à ouvrir la roue, pas à changer l'opération
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        let all = group.isEmpty ? (item.map { [$0] } ?? []) : group
        let dragIDs = all.map(\.id)
        refs = all.compactMap { i -> (URL, URL)? in
            guard case .file(let u)? = i.payload, let r = (u as NSURL).fileReferenceURL() else { return nil }
            return (u, r)
        }
        Task { @MainActor in
            let c = ShelfPanelController.shared
            c.draggedIDs = dragIDs; c.consumedByShelf = false; c.draggingOut = true; c.wheelTookDrag = false; ShelfSound.press()
        }
        let urls = all.compactMap { i -> URL? in switch i.payload { case .file(let u), .link(let u): return u; default: return nil } }
        if urls.isEmpty, all.count == 1, case .text(let t)? = all.first?.payload { DragMonitor.shared.beginInternalDrag([], text: t) }
        else { DragMonitor.shared.beginInternalDrag(urls, text: "") }
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragMonitor.shared.endInternalDrag()
        let moved = operation.contains(.move) ? refs : []
        let ids = Set((group.isEmpty ? (item.map { [$0] } ?? []) : group).filter { !$0.pinned }.map(\.id)), taken = operation != []          // les épinglés restent          // quelqu'un a accepté l'élément (dossier, app, roue…)
        Task { @MainActor in
            if !moved.isEmpty {          // le Finder a déplacé le fichier : l'élément le suit à sa nouvelle place
                try? await Task.sleep(nanoseconds: 500_000_000)
                let moves = moved.compactMap { m -> (from: URL, to: URL)? in
                    guard let new = (m.ref as NSURL).filePathURL, new.path != m.old.path else { return nil }
                    return (m.old, new)
                }
                if !moves.isEmpty { ShelfStore.shared.follow(moves) }
            }
            let c = ShelfPanelController.shared
            c.draggingOut = false
            guard taken, !ids.isEmpty, !c.consumedByShelf, AppSettings.shared.shelfRemoveOnDrag else { c.draggedIDs = []; return }
            try? await Task.sleep(nanoseconds: 600_000_000)          // la roue reçoit parfois le dépôt un instant après la fin du glisser
            guard !ShelfPanelController.shared.wheelTookDrag else { return }          // déposé sur la roue : l'élément reste
            ShelfSound.drop()
            ShelfStore.shared.remove(ids, deleteStaged: false)          // la copie recopiée reste : l'app qui a reçu l'élément peut encore la lire
        }
    }
}

/// NSHostingView répond lui-même aux clics sur ce que SwiftUI dessine : les zones de glisser posées en surimpression ne les recevraient jamais.
/// Ici, un clic dans la zone d'un élément lui est donné d'abord.
final class ShelfHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { ShelfPanelController.shared.takeKeyboard() }; super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) { if !MainActor.assumeIsolated({ ShelfPanelController.shared.handleKey(event) }) { super.keyDown(with: event) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { MainActor.assumeIsolated { ShelfPanelController.shared.handleKey(event) } || super.performKeyEquivalent(with: event) }
    override func scrollWheel(with event: NSEvent) {
        if MainActor.assumeIsolated({ ShelfPanelController.shared.calendarMode }) { MainActor.assumeIsolated { ShelfPanelController.shared.scrollCalendar(event) }; return }          // page Calendrier : ce sont ses colonnes qui défilent
        MainActor.assumeIsolated { ShelfPanelController.shared.scroll(event) }          // pages de l'étagère
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if let h = Self.sources(in: self).first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.convert($0.bounds, to: self).contains(p) }) { return h }
        return super.hitTest(point)
    }
    private static func sources(in view: NSView) -> [ShelfDragView] {
        view.subviews.flatMap { ($0 as? ShelfDragView).map { [$0] } ?? sources(in: $0) }
    }
}
