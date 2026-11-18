import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// Le choix du look de l'étagère (Réglages → Apparence).
enum ShelfStyle: String, CaseIterable, Identifiable {
    case petals, channels
    var id: String { rawValue }
    var title: String { self == .petals ? L("Bubble") : "Wii" }
    /// Taille de la zone qui reste ouverte autour de l'étagère.
    var openSize: CGSize { self == .petals ? CGSize(width: 460, height: 236) : CGSize(width: 400, height: 252) }
}

/// Fenêtre de l'étagère : posée en haut de l'écran, centrée sur l'encoche. Fermée, elle ne fait que la taille de l'encoche ; elle s'ouvre quand le pointeur
/// y arrive (ou quand on y glisse quelque chose) et reste ouverte tant que le pointeur est dans la zone, même entre deux éléments.
@MainActor
final class ShelfPanelController: ObservableObject {
    static let shared = ShelfPanelController()

    @Published private(set) var open = false
    @Published var dropTarget = false
    /// La page Calendrier est affichée à la place de l'étagère (style Wii) : l'encoche s'élargit.
    @Published var calendarMode = false {
        didSet { if open && oldValue != calendarMode { place0(open: true) } }
    }
    /// Défilement des deux colonnes de la page Calendrier (décalage en points) ; la molette ou le trackpad le font bouger.
    @Published var eventsScroll: CGFloat = 0
    @Published var remindersScroll: CGFloat = 0
    func scrollCalendar(_ e: NSEvent) {
        let cal = CalendarStore.shared
        let dy = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 8)
        let center = openRect.midX
        if NSEvent.mouseLocation.x < center + 15 {          // colonne des rendez-vous (à gauche), sinon celle des rappels
            let maxOffset = max(0, CGFloat(cal.events.count) * 30 - 112 + 18)
            eventsScroll = min(max(0, eventsScroll - dy), maxOffset)
        } else {
            let maxOffset = max(0, CGFloat(cal.reminders.count) * 22 - 90 + 12)
            remindersScroll = min(max(0, remindersScroll - dy), maxOffset)
        }
    }
    func toggleCalendar() {
        eventsScroll = 0; remindersScroll = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { calendarMode.toggle() }
        ShelfSound.press()
    }
    /// Un élément de l'étagère est en train d'être glissé dehors : l'étagère reste ouverte.
    var draggingOut = false {
        didSet { if !draggingOut { overTarget = nil; overSlot = nil } }
    }
    /// Éléments en cours de glisser vers l'extérieur ; « consumed » : l'étagère les a déjà traités (œil, poubelle), le glisser n'a plus rien à enlever.
    var draggedIDs: [UUID] = []
    var consumedByShelf = false
    /// Bouton de l'étagère survolé pendant un glisser sorti d'elle (pour l'éclairer).
    @Published var overTarget: String?
    var buttonFrames: [String: CGRect] = [:]
    var slotFrames: [Int: CGRect] = [:]
    /// Place survolée pendant qu'on réordonne (rang dans la liste), pour l'éclairer.
    @Published var overSlot: Int?
    func slot(at p: CGPoint) -> Int? { slotFrames.first { $0.value.insetBy(dx: -4, dy: -4).contains(p) }?.key }
    func button(at p: CGPoint) -> String? { buttonFrames.first { $0.value.insetBy(dx: -6, dy: -6).contains(p) }?.key }
    private var holdUntil = Date.distantPast
    /// Page affichée quand il y a plus d'éléments que de places (8 par page).
    static let pageSize = 8
    @Published var page = 0
    private var scrollAcc: CGFloat = 0
    private var scrollLocked = false
    private var lastWheel = Date.distantPast
    var pageCount: Int { max(1, (ShelfStore.shared.items.count + Self.pageSize - 1) / Self.pageSize) }
    func go(to p: Int) {
        let target = min(max(0, p), pageCount - 1)
        guard target != page else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { page = target }
        ShelfSound.press()
    }
    func step(_ d: Int) { go(to: min(page, pageCount - 1) + d) }

    /// Défilement horizontal (trackpad ou molette) : une page par geste.
    func scroll(_ e: NSEvent) {
        guard pageCount > 1 else { return }
        let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        let d = abs(dx) >= abs(dy) ? dx : dy
        if !e.hasPreciseScrollingDeltas {          // molette de souris : un cran, une page (avec un petit délai)
            guard d != 0, Date().timeIntervalSince(lastWheel) > 0.25 else { return }
            lastWheel = Date(); step(d < 0 ? 1 : -1); return
        }
        if e.phase == .began || e.phase == .mayBegin { scrollAcc = 0; scrollLocked = false }
        if scrollLocked { if e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended { scrollLocked = false; scrollAcc = 0 }; return }
        scrollAcc += d
        if abs(scrollAcc) > 30 { step(scrollAcc < 0 ? 1 : -1); scrollLocked = true; scrollAcc = 0 }
        if e.phase == .ended || e.phase == .cancelled { scrollAcc = 0 }
    }
    private var idleTicks = 0
    private var hoverTicks = 0
    private var keyMonitor: Any?
    var holdOpen = false          // essais : ne pas refermer
    /// Le glisser en cours a été déposé sur la roue de Mandarine : l'élément reste sur l'étagère (le travail crée un nouveau fichier ; s'il remplace l'original, l'élément suit).
    nonisolated(unsafe) var wheelTookDrag = false

    private var panel: ShelfPanel?
    private var timer: Timer?
    private var closeAt: Date?
    private var dwell = 0
    private var cancellables: Set<AnyCancellable> = []
    private let settings = AppSettings.shared

    func start() {
        if keyMonitor == nil {          // ⌘A tant que l'étagère est ouverte et que le pointeur est dessus
            keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers?.lowercased() == "a" else { return }
                Task { @MainActor in
                    guard let self = self, self.open else { return }
                    let m = NSEvent.mouseLocation, r = self.openRect
                    if m.x >= r.minX && m.x <= r.maxX && m.y >= r.minY && m.y <= r.maxY + 4 { ShelfStore.shared.selectAll() }
                }
            }
        }
        Publishers.Merge(settings.$shelfEnabled.map { _ in () }, settings.$shelfStyle.map { _ in () })
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.apply() }.store(in: &cancellables)          // (après le changement : la valeur est à jour)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
        apply()
    }

    private var style: ShelfStyle { ShelfStyle(rawValue: settings.shelfStyle) ?? .petals }

    private func apply() {
        if settings.shelfEnabled { show() } else { hide() }
    }

    // MARK: Géométrie

    /// L'écran de l'encoche (sinon l'écran principal).
    /// Vrai sur un Mac à encoche : on ne dessine le rectangle noir de l'encoche que s'il y en a une (sinon il cacherait le milieu de la barre des menus).
    var hasNotch: Bool { screen.map { $0.safeAreaInsets.top > 0 } ?? false }

    private var screen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }

    /// La vraie encoche : largeur (l'écart entre les deux zones libres de la barre des menus) et hauteur (la marge haute de l'écran) ; sans encoche, une valeur par défaut.
    var notchSize: CGSize {
        guard let s = screen else { return CGSize(width: 130, height: 24) }
        return CGSize(width: notchWidth, height: s.safeAreaInsets.top > 0 ? s.safeAreaInsets.top : 24)
    }

    private var notchWidth: CGFloat {
        guard let s = screen, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea else { return 130 }
        return max(100, s.frame.width - l.width - r.width)
    }

    private var closedRect: NSRect {
        guard let s = screen else { return .zero }
        let w = notchWidth + 14
        return NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - 34, width: w, height: 34)
    }
    private var openRect: NSRect {
        guard let s = screen else { return .zero }
        var z = style.openSize
        if calendarMode && style == .channels { z.width += 90 }          // plus large pour la page Calendrier
        return NSRect(x: s.frame.midX - z.width / 2, y: s.frame.maxY - z.height, width: z.width, height: z.height)
    }

    private func place() { panel?.setFrame(open ? openRect : closedRect, display: true) }

    // MARK: Fenêtre

    private func show() {
        if panel == nil {
            let p = ShelfPanel(contentRect: closedRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .popUpMenu                                        // au-dessus de la barre des menus
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isMovable = false; p.hidesOnDeactivate = false; p.isReleasedWhenClosed = false
            let host = ShelfHostingView(rootView: ShelfRootView(controller: self))
            host.sizingOptions = []
            p.contentView = host
            panel = p
        }
        place()
        panel?.orderFrontRegardless()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        open = false
        panel?.orderOut(nil)
    }

    // MARK: Survol

    private func tick() {
        guard panel != nil else { return }
        let m = NSEvent.mouseLocation
        // filet de sécurité : plus aucun bouton enfoncé mais l'étagère se croit encore en plein glisser → on remet à zéro (sinon elle resterait ouverte)
        if (draggingOut || dropTarget) && NSEvent.pressedMouseButtons == 0 {
            idleTicks += 1
            if idleTicks >= 12 { endDragState() }
        } else { idleTicks = 0 }
        let closed = closedRect, opened = openRect
        let inClosed = m.x >= closed.minX - 2 && m.x <= closed.maxX + 2 && m.y >= closed.minY && m.y <= closed.maxY + 4          // le bord haut de l'écran compte
        let inOpen = m.x >= opened.minX && m.x <= opened.maxX && m.y >= opened.minY && m.y <= opened.maxY + 4
        if !open {
            dwell = inClosed ? dwell + 1 : 0
            if dwell >= 2 || (inClosed && dropTarget) { setOpen(true) }
        } else if inOpen || dropTarget || draggingOut || holdOpen || Date() < holdUntil {
            closeAt = nil
            // le pointeur reste sur l'étagère ouverte : elle prend le clavier (⌘V pour coller, Suppr, Espace…) ; elle le rend en se refermant
            if inOpen, !draggingOut, NSEvent.pressedMouseButtons == 0 { hoverTicks += 1; if hoverTicks == 8 { takeKeyboard() } } else { hoverTicks = 0 }
        } else if let t = closeAt {
            if Date() >= t { setOpen(false) }
        } else {
            closeAt = Date().addingTimeInterval(0.35)                   // délai de grâce : on peut repasser par le bord sans tout refermer
        }
    }

    /// Ouvre l'étagère d'elle-même (bouton « Afficher » d'une notification) et la garde ouverte quelques secondes.
    func present() {
        guard panel != nil else { return }
        holdUntil = Date().addingTimeInterval(6)
        setOpen(true)
    }

    // MARK: Clavier (Suppr, Échap, Espace, ⌘A) : l'étagère prend le clavier quand on clique dessus, et le rend en se refermant

    func takeKeyboard() {
        guard let p = panel, open else { return }
        p.keyable = true
        if !p.isKeyWindow { p.makeKey(); p.makeFirstResponder(p.contentView) }
    }
    func releaseKeyboard() {
        guard let p = panel, p.keyable else { return }
        p.keyable = false
        if p.isKeyWindow { p.orderOut(nil); p.orderFrontRegardless() }          // le clavier retourne à l'app d'avant
    }
    /// Rend vrai si la touche a servi à l'étagère.
    func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, e.charactersIgnoringModifiers?.lowercased() == "a" { ShelfStore.shared.selectAll(); return true }
        if mods == .command, e.charactersIgnoringModifiers?.lowercased() == "v" { if ShelfStore.shared.pasteFromClipboard() { ShelfSound.drop() }; return true }          // coller sur l'étagère
        guard mods.isEmpty else { return false }
        switch e.keyCode {
        case 51, 117: ShelfStore.shared.key("delete"); return true
        case 53: ShelfStore.shared.key("escape"); return true
        case 49: ShelfStore.shared.key("space"); return true
        default: return false
        }
    }

    // MARK: Glisser sorti de l'étagère, déposé sur ses boutons

    /// Œil : montrer dans le Finder. Poubelle : retirer de l'étagère.
    func dropOnButton(_ name: String) -> Bool {
        let ids = draggedIDs
        guard draggingOut, !ids.isEmpty else { return false }
        let store = ShelfStore.shared
        consumedByShelf = true
        switch name {
        case "locate": ShelfActions.reveal(ids.compactMap { id in store.items.first { $0.id == id } })
        case "copy": ShelfActions.copy(ids.compactMap { id in store.items.first { $0.id == id } })
        default: for id in ids { store.remove(id) }
        }
        overTarget = nil
        endDragState()
        return true
    }

    /// Le glisser est fini pour l'étagère. (Si l'élément glissé vient d'être retiré, sa vue n'est plus là pour le dire.)
    func endDragState() {
        draggingOut = false; dropTarget = false; overTarget = nil; overSlot = nil; idleTicks = 0
        DragMonitor.shared.endInternalDrag()
    }

    func setOpen(_ on: Bool) {
        guard open != on else { return }
        if !on { releaseKeyboard() }
        closeAt = nil; dwell = 0; hoverTicks = 0
        // étagère vide (et pas un glisser en cours) : la page Calendrier s'ouvre directement ; sinon on y va avec le petit bouton du calendrier
        if on { eventsScroll = 0; remindersScroll = 0 }
        if on { calendarMode = style == .channels && settings.shelfCalendar && !dropTarget && ShelfStore.shared.items.isEmpty }
        if on { place0(open: true) }
        if on { ShelfSound.open() } else { ShelfSound.close() }
        withAnimation(.easeOut(duration: 0.12)) { open = on }
        if !on { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in if self?.open == false { self?.place0(open: false) } } }
    }

    /// Essai : capture la vraie fenêtre (transparence comprise) posée sur un fond rose.
    func debugCapture(to url: URL) -> Bool {
        guard let w = panel, let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]),
              let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { return false }
        return (try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: url)) != nil
    }

    private func place0(open flag: Bool) { panel?.setFrame(flag ? openRect : closedRect, display: true) }
}

final class ShelfPanel: NSPanel {
    var keyable = false          // vrai seulement après un clic dans l'étagère
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

/// Le contenu de la fenêtre : l'étagère dans le look choisi, branchée sur les vrais éléments, et la zone de dépôt (fichiers, liens, texte, images).
struct ShelfRootView: View {
    @ObservedObject var controller: ShelfPanelController
    @ObservedObject private var store = ShelfStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var targeted = false

    private var style: ShelfStyle { ShelfStyle(rawValue: settings.shelfStyle) ?? .petals }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if style == .petals {
                    ShelfPetalsPanel(store: store, open: controller.open).id("petals")
                } else {
                    ShelfChannelsPanel(store: store, open: controller.open).id("channels")
                }
            }
            if controller.hasNotch { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black).frame(width: controller.notchSize.width + 2, height: controller.notchSize.height + 2).offset(y: -2) }          // recouvre la vraie encoche, à sa vraie taille
            if !controller.open || targeted { Capsule().fill(Theme.orange).frame(width: 50, height: 2).opacity(targeted ? 1 : 0.55).offset(y: 24) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()          // la fenêtre recouvre l'encoche : sans cela, les zones de défilement se décalent de sa hauteur
        .contentShape(Rectangle())
        .coordinateSpace(name: "shelfRoot")
        .onPreferenceChange(ShelfButtonFrames.self) { controller.buttonFrames = $0 }
        .onPreferenceChange(ShelfSlotFrames.self) { controller.slotFrames = $0 }
        .onDrop(of: [UTType.fileURL, .url, .plainText, .image, .item], delegate: ShelfDropper(controller: controller, store: store, targeted: $targeted))
        .onChange(of: targeted) { controller.dropTarget = $0; if $0 { controller.calendarMode = false } }          // un glisser qui arrive : l'étagère
        .onChange(of: store.items.first?.id) { _ in if store.items.count > 0 { controller.calendarMode = false } }
    }
}

/// Reçoit tout ce qu'on dépose sur l'étagère. Ce qui vient d'elle-même ne s'ajoute pas : sur l'œil ou la corbeille il fait leur fonction, ailleurs rien.
struct ShelfDropper: DropDelegate {
    let controller: ShelfPanelController
    let store: ShelfStore
    @Binding var targeted: Bool

    func dropEntered(info: DropInfo) { targeted = true }
    func dropExited(info: DropInfo) { targeted = false; controller.overTarget = nil; controller.overSlot = nil }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        controller.overTarget = controller.draggingOut ? controller.button(at: info.location) : nil
        controller.overSlot = controller.draggingOut && controller.overTarget == nil ? controller.slot(at: info.location) : nil
        return DropProposal(operation: .copy)
    }
    func performDrop(info: DropInfo) -> Bool {
        if controller.draggingOut {
            if let name = controller.button(at: info.location) { if controller.dropOnButton(name) { ShelfSound.remove() } }
            else {
                controller.consumedByShelf = true          // retour sur l'étagère : l'élément ne part pas
                if let i = controller.slot(at: info.location), !controller.draggedIDs.isEmpty {          // lâché sur une place : il s'y range
                    let ids = controller.draggedIDs
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { store.move(ids, to: i < 0 ? store.items.count : i) }          // les éléments glissent vers leur place
                    ShelfSound.drop()
                }
            }
            controller.overTarget = nil
            targeted = false
            controller.endDragState()
            return true
        }
        targeted = false
        store.add(providers: info.itemProviders(for: [.fileURL, .url, .plainText, .image, .item]))
        ShelfSound.drop()
        return true
    }
}
