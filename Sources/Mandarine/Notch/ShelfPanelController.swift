import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// Le choix du look de l'étagère (Réglages → Apparence).
enum ShelfStyle: String, CaseIterable, Identifiable {
    case petals, channels
    var id: String { rawValue }
    var title: String { self == .petals ? L("Petals") : L("Channels") }
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
    /// Un élément de l'étagère est en train d'être glissé dehors : l'étagère reste ouverte.
    var draggingOut = false
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
        let z = style.openSize
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
        let closed = closedRect, opened = openRect
        let inClosed = m.x >= closed.minX - 2 && m.x <= closed.maxX + 2 && m.y >= closed.minY && m.y <= closed.maxY + 4          // le bord haut de l'écran compte
        let inOpen = m.x >= opened.minX && m.x <= opened.maxX && m.y >= opened.minY && m.y <= opened.maxY + 4
        if !open {
            dwell = inClosed ? dwell + 1 : 0
            if dwell >= 2 || (inClosed && dropTarget) { setOpen(true) }
        } else if inOpen || dropTarget || draggingOut || holdOpen {
            closeAt = nil
        } else if let t = closeAt {
            if Date() >= t { setOpen(false) }
        } else {
            closeAt = Date().addingTimeInterval(0.35)                   // délai de grâce : on peut repasser par le bord sans tout refermer
        }
    }

    func setOpen(_ on: Bool) {
        guard open != on else { return }
        closeAt = nil; dwell = 0
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
    override var canBecomeKey: Bool { false }
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
            if controller.hasNotch { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black).frame(width: 130, height: 24).offset(y: -2) }
            if !controller.open || targeted { Capsule().fill(Theme.orange).frame(width: 50, height: 2).opacity(targeted ? 1 : 0.55).offset(y: 24) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL, .url, .plainText, .image, .item], isTargeted: $targeted) { providers in
            store.add(providers: providers)
            ShelfSound.drop()
            return true
        }
        .onChange(of: targeted) { controller.dropTarget = $0 }
    }
}
