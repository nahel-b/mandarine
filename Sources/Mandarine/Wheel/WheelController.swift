import AppKit
import SwiftUI

/// Vue qui reçoit le dépôt sur la roue et calcule le segment survolé.
final class WheelDropView: NSView {
    weak var controller: WheelController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    private var wheelCenter: CGPoint {
        // le centre de la roue est à WheelGeometry.size/2 depuis le haut
        CGPoint(x: bounds.midX, y: bounds.height - WheelGeometry.size / 2)
    }

    private func updateHover(_ info: NSDraggingInfo) {
        let p = convert(info.draggingLocation, from: nil)
        let c = wheelCenter
        let rel = CGPoint(x: p.x - c.x, y: -(p.y - c.y))      // y vers le bas
        controller?.hover(at: rel)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return controller?.hoveredItemEnabled == true ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return controller?.hoveredItemEnabled == true ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.model.hover = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.hoveredItemEnabled == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        updateHover(sender)
        return controller?.drop() ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}

    override func mouseUp(with event: NSEvent) { controller?.dismiss() }
}

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Affiche la roue au curseur et exécute l'élément sur lequel on dépose.
final class WheelController {
    static let shared = WheelController()
    let model = WheelModel()
    private var panel: WheelPanel?
    private var wiiPanel: WheelPanel?
    private var wiiNavTimer: Timer?
    private var glass: NSVisualEffectView?
    private var infoTask: Task<Void, Never>?
    var dropSoundFired = Date.distantPast
    private(set) var urls: [URL] = []
    var isVisible: Bool { (panel?.isVisible ?? false) || (wiiPanel?.isVisible ?? false) }
    var onDismiss: (() -> Void)?

    /// Élément réellement ciblé : le sous-pétale s'il y en a un survolé, sinon le pétale (un groupe seul n'est pas déposable).
    private var targetItem: WheelItem? {
        guard let h = model.hover, model.items.indices.contains(h) else { return nil }
        let p = model.items[h]
        if let c = model.hoverChild, p.children.indices.contains(c) { return p.children[c] }
        return p.isGroup ? nil : p
    }

    var hoveredItemEnabled: Bool { targetItem?.enabled ?? false }

    func show(mode: WheelMode, urls: [URL], at mouse: NSPoint = NSEvent.mouseLocation) {
        self.urls = urls
        let items = Catalog.items(mode: mode, urls: urls)
        guard !items.isEmpty else { dismiss(); return }
        model.mode = mode
        model.items = items
        model.hover = nil
        model.hoverChild = nil
        resetBlob()
        model.fileCount = urls.count
        let total = urls.reduce(Int64(0)) { $0 + $1.fileSize }
        model.infoLines = WheelInfo.quick(urls)
        infoTask?.cancel()
        infoTask = Task { [weak self] in
            let lines = await WheelInfo.detailed(urls)
            if Task.isCancelled { return }
            await MainActor.run { if self?.urls == urls, !lines.isEmpty { self?.model.infoLines = lines } }
        }
        model.sizeLabel = !urls.allSatisfy(\.isFileURL) ? (urls.count > 1 ? "\(urls.count) links" : "Link") : (urls.count > 1 ? "\(urls.count) files" : total.humanSize)

        // Roue déjà ouverte (on change de touche) : on garde sa position, seul le contenu change.
        let wii = AppSettings.shared.appearance == .wii
        if isVisible {
            if wii { model.wiiPage = 0; model.cursor = nil } else { layoutGlass() }
            Feedback.shared.tick()
            return
        }
        if wii { showWii(at: mouse); return }

        let w = WheelGeometry.size, h = WheelGeometry.size + WheelGeometry.captionHeight
        var origin = NSPoint(x: mouse.x - w / 2, y: mouse.y - (h - WheelGeometry.size / 2))
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - w)
            origin.y = min(max(origin.y, f.minY), f.maxY - h)
        }
        if panel == nil {
            let p = WheelPanel(contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.isMovable = false
            let drop = WheelDropView(frame: NSRect(origin: .zero, size: NSSize(width: w, height: h)))
            drop.controller = self
            drop.autoresizingMask = [.width, .height]
            // Vrai verre : flou de ce qui se trouve derrière la roue, masqué en disque.
            let glass = NSVisualEffectView(frame: .zero)
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            glass.appearance = NSAppearance(named: .vibrantDark)
            glass.alphaValue = 0.96
            glass.wantsLayer = true
            drop.addSubview(glass)
            self.glass = glass
            let host = NSHostingView(rootView: WheelView(model: model))
            host.frame = drop.bounds
            host.autoresizingMask = [.width, .height]
            drop.addSubview(host)
            p.contentView = drop
            panel = p
        }
        panel?.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
        layoutGlass()
        model.appear = false
        panel?.orderFrontRegardless()
        Feedback.shared.open()
        // Apparition discrète : le verre (AppKit) et la roue (SwiftUI) grossissent de 92 % à 100 %.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.model.appear = true
            self.popGlass()
        }
    }

    /// Le verre couvre toute la zone et est découpé par la forme du fond (disque + excroissance éventuelle).
    private func layoutGlass() {
        guard let glass = glass else { return }
        let s = WheelGeometry.size
        glass.frame = NSRect(x: 0, y: 0, width: s, height: s)
        applyGlassMask()
    }

    private func applyGlassMask() {
        guard let glass = glass else { return }
        let s = WheelGeometry.size
        let path = WheelGeometry.discPath(center: CGPoint(x: s / 2, y: s / 2), n: max(model.items.count, 1),
                                          parent: model.blobParent, childCount: model.blobCount, t: CGFloat(model.blobT))
        // image en coordonnées « y vers le bas » : même repère que SwiftUI
        glass.maskImage = NSImage(size: NSSize(width: s, height: s), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.addPath(path); c.setFillColor(NSColor.black.cgColor); c.fillPath()
            return true
        }
    }

    // MARK: Croissance du fond autour des sous-pétales
    private var blobTimer: Timer?
    private var blobTarget: CGFloat = 0

    private func updateBlob() {
        var want: (Int, Int)?
        if let h = model.hover, model.items.indices.contains(h), model.items[h].isGroup { want = (h, model.items[h].children.count) }
        if let w = want {
            if model.blobParent != w.0 { model.blobT = 0 }           // autre groupe : on repart de zéro
            model.blobParent = w.0; model.blobCount = w.1; blobTarget = 1
        } else { blobTarget = 0 }
        guard blobTimer == nil, abs(CGFloat(model.blobT) - blobTarget) > 0.001 || model.blobParent != nil else { return }
        blobTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.blobTick() }
        RunLoop.main.add(blobTimer!, forMode: .common)
    }

    private func blobTick() {
        let t = CGFloat(model.blobT)
        var next = t + (blobTarget - t) * 0.30 + (blobTarget > t ? 0.012 : -0.012)       // ressort léger, vite
        if abs(next - blobTarget) < 0.01 || (blobTarget > t) != (next > t) && abs(next - blobTarget) < 0.04 { next = blobTarget }
        model.blobT = Double(next)
        if next == blobTarget && blobTarget == 0 { model.blobParent = nil; model.blobCount = 0 }
        applyGlassMask()
        if next == blobTarget { blobTimer?.invalidate(); blobTimer = nil }
    }

    private func resetBlob() {
        blobTimer?.invalidate(); blobTimer = nil
        blobTarget = 0; model.blobT = 0; model.blobParent = nil; model.blobCount = 0
    }

    /// Rebond du verre : ressort amorti (mêmes paramètres que l'animation SwiftUI), mis à l'échelle autour du CENTRE du disque,
    /// quel que soit le point d'ancrage de la couche (on ne le modifie pas : AppKit le gère pour positionner la vue).
    private func popGlass() {
        guard let g = glass, let l = g.layer else { return }
        let size = g.bounds.size
        let anchor = CGPoint(x: l.anchorPoint.x * size.width, y: l.anchorPoint.y * size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let k = 503.0, damping = 38.0                                    // raideur / amortissement
        let w0 = k.squareRoot(), z = damping / (2 * w0), wd = w0 * (1 - z * z).squareRoot()
        func spring(_ t: Double) -> Double { 1 - exp(-z * w0 * t) * (cos(wd * t) + z * w0 / wd * sin(wd * t)) }
        let duration = 0.5, steps = 40
        var values: [NSValue] = []
        for i in 0...steps {
            let t = duration * Double(i) / Double(steps)
            let s = CGFloat(0.92 + 0.08 * spring(t))
            var m = CATransform3DIdentity
            m.m11 = s; m.m22 = s
            m.m41 = (1 - s) * (c.x - anchor.x); m.m42 = (1 - s) * (c.y - anchor.y)
            values.append(NSValue(caTransform3D: m))
        }
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = values
        anim.duration = duration
        anim.calculationMode = .linear
        l.add(anim, forKey: "pop")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.10
        l.add(fade, forKey: "fade")
    }

    // MARK: Style Wii
    private func showWii(at mouse: NSPoint) {
        let size = WiiLayout.displaySize
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - size.width - 8)
            origin.y = min(max(origin.y, f.minY + 8), f.maxY - size.height - 8)
        }
        if wiiPanel == nil {
            let p = WheelPanel(contentRect: NSRect(origin: origin, size: NSSize(width: size.width + 60, height: size.height + 60)),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .popUpMenu
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.isMovable = false
            // la zone de dépôt couvre exactement l'écran Wii ; une marge transparente laisse place à l'ombre
            let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: size.width + 60, height: size.height + 60)))
            let drop = WiiDropView(frame: NSRect(x: 30, y: 30, width: size.width, height: size.height))
            drop.controller = self
            let host = NSHostingView(rootView: WiiMenuView(model: model))
            host.frame = NSRect(x: 30, y: 30, width: size.width, height: size.height)
            container.addSubview(host)
            container.addSubview(drop)                      // au-dessus : reçoit le glisser-déposer
            p.contentView = container
            wiiPanel = p
        }
        wiiPanel?.setFrame(NSRect(x: origin.x - 30, y: origin.y - 30, width: size.width + 60, height: size.height + 60), display: true)
        model.wiiPage = 0; model.cursor = nil; model.wiiNav = false; model.appear = false
        wiiPanel?.orderFrontRegardless()
        Feedback.shared.open()
        DispatchQueue.main.async { [weak self] in self?.model.appear = true }
    }

    /// `p` : position dans l'écran Wii (origine en haut à gauche).
    func wiiHover(at p: CGPoint) {
        model.cursor = p
        let count = model.items.count
        let per = WiiLayout.perPage(count)
        var parent: Int? = nil, child: Int? = nil, nav = false

        // 1) bulle des sous-éléments du groupe survolé (marge de tolérance pour traverser l'espace entre case et bulle)
        if let h = model.hover, model.items.indices.contains(h), model.items[h].isGroup {
            let slot = h - model.wiiPage * per
            if (0..<12).contains(slot) {
                let rects = WiiLayout.childRects(parentSlot: slot, count: model.items[h].children.count)
                if let ci = rects.firstIndex(where: { $0.insetBy(dx: -6, dy: -6).contains(p) }) { parent = h; child = ci }
                else if WiiLayout.trayBounds(rects).union(WiiLayout.slotRect(slot)).contains(p), !isOnOtherTile(p, except: slot) { parent = h }
            }
        }
        // 2) cases de la grille
        if parent == nil {
            for slot in 0..<12 where WiiLayout.slotRect(slot).insetBy(dx: -5, dy: -5).contains(p) {
                if let i = WiiLayout.itemIndex(slot: slot, page: model.wiiPage, count: count) { parent = i }
                else if slot == WiiLayout.navSlot(count: count) { nav = true }
                break
            }
        }
        let changed = parent != model.hover || (child != nil && child != model.hoverChild)
        model.hover = parent; model.hoverChild = child
        if nav != model.wiiNav {
            model.wiiNav = nav
            wiiNavTimer?.invalidate(); wiiNavTimer = nil
            if nav {   // survol prolongé de la flèche : page suivante
                wiiNavTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
                    guard let self = self, self.model.wiiNav else { return }
                    self.model.wiiPage = (self.model.wiiPage + 1) % WiiLayout.pageCount(self.model.items.count)
                    self.model.hover = nil; Feedback.shared.tick()
                }
            }
        }
        if changed && parent != nil { Feedback.shared.tick() }
    }

    private func isOnOtherTile(_ p: CGPoint, except slot: Int) -> Bool {
        (0..<12).contains { $0 != slot && WiiLayout.slotRect($0).contains(p) }
    }

    func wiiExited() { model.hover = nil; model.hoverChild = nil; model.cursor = nil; model.wiiNav = false }

    func hover(at rel: CGPoint) {
        let n = model.items.count
        let parentItem = model.hover.flatMap { model.items.indices.contains($0) ? model.items[$0] : nil }
        let r = WheelGeometry.hit(at: rel, count: n, hoverParent: model.hover, childCount: parentItem?.children.count ?? 0)
        if r.parent != model.hover || r.child != model.hoverChild {
            let changed = (r.parent != model.hover) || (r.child != nil && r.child != model.hoverChild)
            model.hover = r.parent
            model.hoverChild = r.child
            updateBlob()
            if changed && r.parent != nil { Feedback.shared.tick() }
        }
    }

    /// Retourne true si le dépôt a été accepté.
    func drop() -> Bool {
        guard let item = targetItem, item.enabled else { dismiss(); return false }
        let files = urls
        // le son part au relâchement (DragMonitor) ; ici seulement s'il n'a pas déjà été joué
        if Date().timeIntervalSince(dropSoundFired) > 1.5 { Feedback.shared.drop() }
        dismiss()
        DispatchQueue.main.async { Dispatcher.run(item, on: files) }
        return true
    }

    /// Masque la roue sans mettre fin au suivi du glisser (le drag continue).
    func hide() {
        panel?.orderOut(nil)
        wiiPanel?.orderOut(nil); wiiNavTimer?.invalidate(); wiiNavTimer = nil; model.cursor = nil; model.wiiNav = false
        model.appear = false
        model.hover = nil
        model.hoverChild = nil
        resetBlob()
    }

    func dismiss() {
        panel?.orderOut(nil)
        wiiPanel?.orderOut(nil); wiiNavTimer?.invalidate(); wiiNavTimer = nil; model.cursor = nil; model.wiiNav = false
        model.appear = false
        model.hover = nil
        model.hoverChild = nil
        resetBlob()
        onDismiss?()
    }
}
