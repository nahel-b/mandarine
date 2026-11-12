import SwiftUI
import AppKit

// MARK: Écran Wii qui héberge les outils
//
// Style « Wii » : quand on dépose un fichier sur un outil, l'écran Wii reste là. La caméra zoome sur la case, l'écran s'assombrit, puis un panneau
// de « chaîne » (comme la chaîne Disque) grandit depuis la case jusqu'à remplir l'écran : l'outil est dedans, avec son titre dans l'onglet bleu en
// haut à droite et, en bas, « Wii Menu » (retour à la grille) et les boutons de l'outil. La séquence reprend celle de la vraie console.

/// État partagé entre le cadre Wii (ToolShell) et l'écran : onglet de titre, contenu et retour au menu.
final class WiiHost: ObservableObject {
    @Published var tab: CGFloat = 0           // onglet de titre : 0 caché au-dessus, 1 en place
    @Published var content: Double = 0        // opacité du contenu de l'outil
    var hasMenu = true                        // vrai : « Wii Menu » revient à la grille ; faux : le bouton ferme
    var back: () -> Void = {}
    var onMeasure: (CGSize) -> Void = { _ in }   // taille naturelle du contenu, relevée par le cadre
    private var contentSize = CGSize.zero, barWidth: CGFloat = 0
    func measuredContent(_ s: CGSize) { guard abs(s.width - contentSize.width) > 0.5 || abs(s.height - contentSize.height) > 0.5 else { return }; contentSize = s; report() }
    func measuredBar(_ w: CGFloat) { guard abs(w - barWidth) > 0.5 else { return }; barWidth = w; report() }
    /// Nouvel outil : on oublie les mesures précédentes, sinon un outil rouvert (même taille que le précédent) n'enverrait aucune mesure et le panneau
    /// resterait à sa taille par défaut, contenu coupé.
    func resetMeasure() { contentSize = .zero; barWidth = 0 }
    private func report() { onMeasure(CGSize(width: max(contentSize.width, barWidth), height: contentSize.height)) }
}

private struct WiiHostKey: EnvironmentKey { static let defaultValue: WiiHost? = nil }
private struct WiiInTVKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Le panneau est montré dans le téléviseur : les coins arrondis du tube rognent les angles, le titre se rentre.
    var wiiInTV: Bool { get { self[WiiInTVKey.self] } set { self[WiiInTVKey.self] = newValue } }
    var wiiHost: WiiHost? { get { self[WiiHostKey.self] } set { self[WiiHostKey.self] = newValue } }
}

// MARK: Formes et boutons

/// Onglet bleu du titre : collé en haut à droite, bord gauche en S.
struct WiiTabShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: r.width * 0.16, y: r.height), control1: CGPoint(x: r.width * 0.07, y: 0), control2: CGPoint(x: r.width * 0.08, y: r.height))
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.closeSubpath()
        return p
    }
}

/// Bouton « pilule » de la Wii : blanc glacé, liseré bleu clair, qui s'illumine au survol.
struct WiiPillLabel<Label: View>: View {
    let label: Label
    var pressed = false
    var enabled = true
    var prominent = false
    @State private var hover = false
    private let blue = Color(red: 0.36, green: 0.78, blue: 0.95)

    var body: some View {
        let lit = hover && enabled
        label
            .fixedSize()
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(enabled ? Color(white: prominent ? 0.1 : 0.22) : Color(white: 0.7))
            .lineLimit(1)
            .padding(.horizontal, 28).padding(.vertical, 10)
            .frame(minWidth: 118)
            .background(ZStack {
                Capsule().fill(enabled ? blue.opacity(lit ? 1 : 0.8) : Color(white: 0.82))
                Capsule().fill(LinearGradient(colors: enabled ? [.white, Color(white: pressed ? 0.78 : 0.9)] : [Color(white: 0.95), Color(white: 0.89)], startPoint: .top, endPoint: .bottom))
                    .padding(lit ? 4 : 3)
                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))).padding(lit ? 5 : 4)
            })
            .shadow(color: lit ? blue.opacity(0.6) : Color.black.opacity(0.12), radius: lit ? 9 : 3, y: lit ? 0 : 2)
            .scaleEffect(pressed ? 0.97 : (lit ? 1.07 : 1))
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: lit)
            .onHover { hover = $0; if $0 && enabled { Feedback.shared.wiiButtonHover() } }
    }
}

/// Look de vieux téléviseur à tube : lignes de balayage, bords assombris, reflet de la vitre et une bande claire qui descend lentement.
/// Purement visuel (ne reçoit aucun clic).
struct WiiCRT: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                Canvas { ctx, size in
                    for y in stride(from: CGFloat(0), to: size.height, by: 3) {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1.1)), with: .color(Color.black.opacity(0.06)))
                    }
                }
                RadialGradient(colors: [.clear, Color.black.opacity(0.04), Color.black.opacity(0.17)], center: .center,
                               startRadius: min(g.size.width, g.size.height) * 0.30, endRadius: max(g.size.width, g.size.height) * 0.70)
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.45))
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { ctx in
                    let cycle = 7.0
                    let f = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                    let h = max(g.size.height * 0.22, 60)
                    LinearGradient(colors: [.clear, Color.white.opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: h)
                        .position(x: g.size.width / 2, y: CGFloat(f) * (g.size.height + h) - h / 2)
                }
            }
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

/// Cadre d'un outil dans l'écran Wii : contenu au centre (blanc glacé), bande beige en bas avec « Wii Menu » et les boutons de l'outil,
/// onglet bleu du titre en haut à droite. Rendu à sa taille naturelle ; l'écran le met à l'échelle pendant la transition.
struct WiiToolFrame<Content: View, Footer: View>: View {
    @ObservedObject var host: WiiHost
    let title: String
    let content: Content
    let footer: Footer
    @Environment(\.wiiInTV) private var inTV

    var body: some View {
        VStack(spacing: 0) {
            content
                .toggleStyle(WiiToggleStyle())
                .fixedSize()                                  // taille idéale : la mesure ne dépend pas de la place offerte (sinon elle suit le panneau et oscille)
                .padding(.top, 58).padding(.horizontal, 30).padding(.bottom, 20)
                .opacity(host.content)
                .background(GeometryReader { g in
                    Color.clear.onAppear { host.measuredContent(g.size) }.onChange(of: g.size) { host.measuredContent($0) }
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bar
        }
        .frame(minWidth: 440)
        .background(panelBackground)
        .overlay(alignment: .topTrailing) { tab }
        .overlay(WiiCRT())
        .environment(\.colorScheme, .light)
    }

    private var panelBackground: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.white, Color(red: 0.93, green: 0.94, blue: 0.95)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color.white.opacity(0.95), .clear], startPoint: .top, endPoint: .bottom).frame(height: 150)
        }
    }

    private var bar: some View {
        HStack(spacing: 14) {
            Button { host.back() } label: { Text(host.hasMenu ? L("Wii Menu") : L("Close")) }
                .buttonStyle(PillButtonStyle()).environment(\.toolStyle, .wii)
            Spacer(minLength: 10).background(DragZone())
            footer.environment(\.toolStyle, .wii)
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(GeometryReader { g in
            Color.clear.onAppear { host.measuredBar(g.size.width + 56) }.onChange(of: g.size.width) { host.measuredBar($0 + 56) }
        })
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .frame(height: WiiShell.barHeight)
        .background(
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.89, green: 0.88, blue: 0.84), Color(red: 0.82, green: 0.81, blue: 0.77)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(white: 0.55).opacity(0.55)).frame(height: 1.2)
                Rectangle().fill(Color.white.opacity(0.7)).frame(height: 1).offset(y: 1.2)
            }
        )
    }

    private var tab: some View {
        let w = max(230, CGFloat(title.count) * 12 + 110) + (inTV ? 44 : 0)
        return WiiTabShape()
            .fill(LinearGradient(colors: [Color(red: 0.40, green: 0.82, blue: 0.97), Color(red: 0.16, green: 0.62, blue: 0.90)], startPoint: .top, endPoint: .bottom))
            .overlay(WiiTabShape().stroke(Color.white.opacity(0.55), lineWidth: 1.2))
            .overlay(alignment: .trailing) {
                Text(L(title)).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    .shadow(color: Color(red: 0.1, green: 0.4, blue: 0.7).opacity(0.6), radius: 1, y: 1).padding(.trailing, inTV ? 80 : 36)
            }
            .frame(width: w, height: 42)
            .background(DragZone())
            .offset(y: (1 - host.tab) * -52)
            .opacity(Double(min(1, host.tab * 2)))
    }
}

// MARK: Choix à la Wii (cases à cocher, choix multiples)

/// Une ligne de liste de la Wii : pilule blanche glacée à liseré bleu clair. Sous le pointeur, elle devient lavande et reçoit les quatre coins rouges ;
/// cochée / choisie, elle reste lavande (avec une pastille ✓ pour une case à cocher).
struct WiiChoiceRow<Label: View>: View {
    let selected: Bool
    var checkmark = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    private let cyan = Color(red: 0.32, green: 0.78, blue: 0.96)
    private let violet = Color(red: 0.34, green: 0.30, blue: 0.80)

    var body: some View {
        let lit = selected || hover
        HStack(spacing: 8) {
            if checkmark {
                ZStack {
                    Circle().fill(selected ? Color(red: 0.30, green: 0.62, blue: 0.95) : Color.white)
                    Circle().strokeBorder(selected ? Color.white : cyan, lineWidth: 2)
                    if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white) }
                }.frame(width: 20, height: 20)
            }
            label().font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(lit ? violet : Color(white: 0.22)).lineLimit(1)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.34, green: 0.74, blue: 0.96))
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(
                colors: lit ? [Color(red: 0.80, green: 0.78, blue: 1.0), Color(red: 0.66, green: 0.64, blue: 0.98)] : [.white, Color(white: 0.89)],
                startPoint: .top, endPoint: .bottom)).padding(2.5)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5))).padding(4)
        })
        .overlay { if hover && enabled { Corners().padding(-5).transition(.opacity) } }
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(hover && enabled ? 1.05 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.68), value: hover)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hover = $0; if $0 && enabled { Feedback.shared.wiiButtonHover() } }
        .onTapGesture { if enabled { action() } }
        .accessibilityAddTraits(.isButton)
    }

    /// Les quatre coins rouges du curseur de sélection.
    private struct Corners: View {
        var body: some View {
            Canvas { ctx, size in
                let l: CGFloat = 9, c = Color(red: 0.96, green: 0.26, blue: 0.14)
                var p = Path()
                for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (size.width, 0.0, -1.0, 1.0), (0.0, size.height, 1.0, -1.0), (size.width, size.height, -1.0, -1.0)] {
                    p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
                }
                ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .miter))
            }.allowsHitTesting(false)
        }
    }
}

/// Cases à cocher des outils, à la Wii.
struct WiiToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        WiiChoiceRow(selected: configuration.isOn, checkmark: true, action: { configuration.isOn.toggle() }) { configuration.label }
    }
}

/// Choix multiple (un seul choisi) à la Wii : une pilule par option.
struct WiiChoiceGroup<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        FlowLayout(spacing: 9) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                WiiChoiceRow(selected: selection == o.0, action: { selection = o.0 }) { Text(L(o.1)) }
            }
        }
    }
}

/// Le bouton « pilule » dans les barres Wii (PillButtonStyle, style .wii).
struct WiiPillButtonBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View { WiiPillLabel(label: label, pressed: pressed, enabled: enabled, prominent: prominent) }
}

// MARK: Pointeur

/// Position et état de la main (relevés 60 fois par seconde tant que l'écran Wii est ouvert).
final class WiiPointer: ObservableObject {
    @Published var point: CGPoint?       // dans le repère de l'écran (y vers le bas) ; nil : le pointeur est hors de l'écran Wii
    @Published var closed = false        // bouton enfoncé : poing fermé
}

struct WiiHandOverlay: View {
    @ObservedObject var pointer: WiiPointer
    var body: some View {
        if let p = pointer.point {
            WiiHand(closed: pointer.closed).scaleEffect(0.82).position(x: p.x + 12, y: p.y + 15).allowsHitTesting(false)
        }
    }
}

// MARK: Contrôleur

final class WiiHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Fenêtre unique de l'écran Wii une fois qu'on a déposé sur un outil : la grille (cliquable), le zoom sur la case et l'outil.
final class WiiShell: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WiiShell()
    static let barHeight: CGFloat = 78
    static let zoomAmount: CGFloat = 0.9
    private static let margin: CGFloat = 60

    @Published var tool: AnyView? { didSet { resizeWindow() } }
    @Published var toolID = UUID()
    @Published var naturalSize = CGSize(width: 480, height: 330) { didSet { if oldValue != naturalSize { resizeWindow() } } }
    @Published var panel: CGFloat = 0                // 0 : le panneau est la case agrandie ; 1 : il remplit l'écran
    @Published var panelShown: CGFloat = 0           // le panneau (blanc) remplace la case : 0 invisible, 1 visible
    @Published var interactive = false                // l'outil est prêt à recevoir les clics
    @Published var exiting = false
    @Published var hasMenu = false { didSet { host.hasMenu = hasMenu } }
    @Published var tile = CGRect.zero                // case d'origine, dans le repère 700 × 452 de l'écran Wii
    let host = WiiHost()
    let pointer = WiiPointer()
    private var window: ToolWindow?
    private var pointerTimer: Timer?
    private var cursorHidden = false
    private var watchingReplace = false
    private var wasDown = false
    private var lastSoundPoint = CGPoint.zero
    private var center = NSPoint.zero
    private var token = 0

    private override init() {
        super.init()
        host.onMeasure = { [weak self] size in
            guard size.width > 0 else { return }
            DispatchQueue.main.async { self?.naturalSize = CGSize(width: max(size.width, 440), height: size.height + Self.barHeight) }
        }
    }

    private var menuModel: WheelModel { WheelController.shared.model }
    var isOpen: Bool { window != nil }
    var debugContentView: NSView? { window?.contentView }

    // MARK: Géométrie (en points d'affichage)

    private var menuSize: CGSize { WiiLayout.displaySize }
    /// Taille du panneau d'un outil, une fois ouvert.
    var fullSize: CGSize { tvFull ?? plainFullSize }
    /// Dans le téléviseur, le panneau est mis en page à sa taille naturelle (aux proportions de la vitre) puis réduit pour tenir dans la vitre :
    /// le téléviseur garde toujours la taille du menu.
    private var tvFull: CGSize? {
        guard let s = tvScreen else { return nil }
        var f = naturalSize
        let r = WiiTV.hole.width / WiiTV.hole.height
        if f.width / f.height > r { f.height = f.width / r } else { f.width = f.height * r }
        return f.width < s.width ? s : f
    }
    private var plainFullSize: CGSize {
        let m = menuSize
        return hasMenu ? CGSize(width: max(naturalSize.width, m.width - 16), height: max(naturalSize.height, m.height - 16)) : naturalSize
    }
    /// Taille de l'écran (cadre noir compris) : celle du menu, ou plus grande si l'outil l'est.
    var screenSize: CGSize { tvScreen ?? plainScreenSize }
    private var plainScreenSize: CGSize {
        guard tool != nil else { return menuSize }
        let f = plainFullSize
        return hasMenu ? CGSize(width: max(menuSize.width, f.width + 16), height: max(menuSize.height, f.height + 16)) : CGSize(width: f.width + 16, height: f.height + 16)
    }
    /// Dans le téléviseur, l'écran prend exactement les proportions de la vitre et le panneau le remplit entièrement (ni cadre noir, ni bandes).
    private var tvScreen: CGSize? { tvPlan?.screen }
    var tvGeo: WiiTV.Geometry? { tvPlan?.geo }
    private var tvPlan: (screen: CGSize, geo: WiiTV.Geometry)? {
        guard WiiTV.enabled else { return nil }
        var base = menuSize          // la taille du téléviseur ne change jamais : celle du menu
        let r = WiiTV.hole.width / WiiTV.hole.height
        if base.width / base.height > r { base.height = base.width / r } else { base.width = base.height * r }
        let screen = window?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        return WheelController.tvGeometry(for: base, on: screen).map { (base, $0) }
    }
    /// La fenêtre : l'écran plus une marge d'ombre, ou le téléviseur entier (centré sur l'écran).
    var stage: CGSize { tvGeo?.stage ?? CGSize(width: screenSize.width + Self.margin, height: screenSize.height + Self.margin) }
    /// La fenêtre ne fait que grandir tant qu'un outil est ouvert : le panneau (SwiftUI) s'adapte en douceur à l'intérieur, sans que la fenêtre
    /// bouge à chaque changement de contenu (une case qui révèle un réglage, par exemple).
    private var windowStage = CGSize.zero

    // MARK: Ouverture

    /// Dépôt d'un fichier sur un outil du menu Wii : le menu devient cette fenêtre, puis zoome sur la case.
    func openFromMenu(tool id: ToolID, urls: [URL], tile: CGRect, center: NSPoint) {
        let m = menuModel
        hasMenu = true
        self.tile = tile
        m.wiiAnchor = UnitPoint(x: tile.midX / WiiLayout.size.width, y: tile.midY / WiiLayout.size.height)
        m.wiiZoom = 0; m.wiiDim = 0; m.wiiInteractive = false; m.cursor = nil
        ensureWindow(center: center)
        ReplaceTip.maybeShow(for: id)
        enter(ToolRegistry.view(for: id, urls: urls, close: { [weak self] in self?.finish() }))
        // l'app passe au premier plan tout de suite : la main reste le pointeur dès que le fichier est lâché
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    /// Un outil ouvert par un autre chemin (bouton « Edit… » d'un outil, liste de lecture…) : il prend la place de l'outil courant, ou ouvre l'écran seul.
    func present(_ make: (@escaping () -> Void) -> AnyView) {
        let view = make { [weak self] in self?.finish() }
        if window == nil {
            hasMenu = false
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            let c = screen.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
            tile = CGRect(x: WiiLayout.size.width / 2 - 71, y: WiiLayout.size.height / 2 - 48, width: 142, height: 96)
            ensureWindow(center: c)
            Feedback.shared.toolOpen()
        } else { Feedback.shared.toolOpen() }
        enter(view)
    }

    private var sessionBase: Bool?          // mode de remplacement par défaut de l'outil ouvert (déposé avec la touche d'inversion : l'inverse du réglage)
    private func wrapped(_ v: AnyView) -> AnyView { AnyView(v.environment(\.wiiHost, host).environment(\.replaceBase, sessionBase).environment(\.colorScheme, .light)) }

    private func enter(_ view: AnyView) {
        host.back = { [weak self] in self?.backToMenu() }
        if tool != nil { switchTool(wrapped(view)); return }
        sessionBase = ReplaceMode.shared.baseForNewWindow()
        token += 1
        exiting = false; interactive = false
        host.content = 0; host.tab = 0; panel = 0; panelShown = 0
        naturalSize = CGSize(width: 480, height: 330)
        toolID = UUID()
        host.resetMeasure()
        tool = wrapped(view)
        let t = token
        let menu = menuModel
        // Séquence de la console : la caméra plonge sur la case et les autres cases s'éteignent → la case devient un panneau blanc →
        // l'écran passe au noir pendant que le panneau grandit (même proportions, du coin de la case jusqu'à l'écran) → l'onglet du titre
        // glisse depuis le haut → le contenu apparaît.
        if hasMenu {
            withAnimation(.easeInOut(duration: 0.34)) { menu.wiiZoom = 1 }
            withAnimation(.easeIn(duration: 0.34).delay(0.04)) { menu.wiiDim = 1 }
        }
        later(hasMenu ? 0.26 : 0.0, t) { withAnimation(.easeOut(duration: 0.10)) { self.panelShown = 1 } }
        later(hasMenu ? 0.32 : 0.04, t) { withAnimation(.timingCurve(0.22, 0.0, 0.16, 1.0, duration: 0.62)) { self.panel = 1 } }
        later(hasMenu ? 0.86 : 0.58, t) { withAnimation(.timingCurve(0.2, 0.85, 0.3, 1.0, duration: 0.34)) { self.host.tab = 1 } }
        later(hasMenu ? 0.92 : 0.64, t) { withAnimation(.easeOut(duration: 0.30)) { self.host.content = 1 } }
        later(hasMenu ? 1.25 : 0.98, t) { self.becomeInteractive() }
    }

    /// Un autre outil remplace le courant, sans repasser par le menu : le contenu s'efface puis revient, le panneau s'adapte à sa taille.
    private func switchTool(_ view: AnyView) {
        token += 1; let t = token
        exiting = false; interactive = false
        withAnimation(.easeIn(duration: 0.12)) { host.content = 0; host.tab = 0 }
        later(0.14, t) {
            self.toolID = UUID()
            self.host.resetMeasure()
            self.tool = view
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { self.host.tab = 1 }
            withAnimation(.easeOut(duration: 0.28).delay(0.08)) { self.host.content = 1 }
        }
        later(0.5, t) { self.becomeInteractive() }
    }

    private func becomeInteractive() {
        interactive = true
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Retour, choix, sortie

    /// « Wii Menu » : le contenu s'efface, le panneau rétrécit jusqu'à la case, la caméra recule et la grille redevient cliquable.
    func backToMenu() {
        guard hasMenu, tool != nil else { finish(); return }
        token += 1; let t = token
        interactive = false
        Feedback.shared.wiiClose()
        let menu = menuModel
        withAnimation(.easeIn(duration: 0.15)) { host.content = 0; host.tab = 0 }
        later(0.12, t) { withAnimation(.timingCurve(0.5, 0.0, 0.8, 0.6, duration: 0.5)) { self.panel = 0 } }
        later(0.56, t) { withAnimation(.easeOut(duration: 0.10)) { self.panelShown = 0 } }
        later(0.56, t) {
            withAnimation(.easeOut(duration: 0.30)) { menu.wiiDim = 0 }
            withAnimation(.easeInOut(duration: 0.36)) { menu.wiiZoom = 0 }
        }
        later(0.96, t) {
            self.tool = nil
            menu.hover = nil; menu.hoverChild = nil; menu.cursor = nil
            menu.wiiInteractive = true
            self.becomeInteractive()
        }
    }

    /// Clic sur une case de la grille (après un « Wii Menu »).
    func chooseHovered() {
        let wc = WheelController.shared
        guard let item = wc.targetItem, item.enabled else { return }
        ReplaceMode.shared.capture()
        let files = wc.urls
        if case .tool(let id) = item.payload, !ToolRegistry.isDirect(id) {
            let m = menuModel
            let rect = wc.hoveredTileRect()
            tile = rect
            m.wiiAnchor = UnitPoint(x: rect.midX / WiiLayout.size.width, y: rect.midY / WiiLayout.size.height)
            m.wiiInteractive = false
            Feedback.shared.toolOpen()
            ReplaceTip.maybeShow(for: id)
            enter(ToolRegistry.view(for: id, urls: files, close: { [weak self] in self?.finish() }))
        } else {
            Feedback.shared.drop()
            Dispatcher.run(item, on: files)
            finish()
        }
    }

    /// L'outil a démarré son travail (ou on quitte) : l'écran se retire.
    func finish() {
        token += 1; let t = token
        interactive = false
        Feedback.shared.wiiClose()
        menuModel.wiiInteractive = false
        withAnimation(.easeIn(duration: 0.15)) { host.content = 0; host.tab = 0 }
        later(0.06, t) { withAnimation(.easeIn(duration: 0.22)) { self.exiting = true } }
        later(0.34, t) { self.closeNow() }
    }

    /// Ferme tout de suite (nouveau glisser, Échap…).
    func closeNow() {
        token += 1
        if let w = window { w.close() } else { reset() }
    }

    // MARK: Fenêtre

    private func later(_ delay: Double, _ t: Int, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in if self?.token == t { block() } }
    }

    private func ensureWindow(center c: NSPoint) {
        if window != nil { return }
        center = c
        let hosting = WiiHostingView(rootView: WiiShellView(model: menuModel, shell: self))
        hosting.sizingOptions = []
        let s = stage
        let w = ToolWindow(contentRect: NSRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height),
                           styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = hosting
        w.delegate = self
        w.isReleasedWhenClosed = false
        window = w
        w.orderFrontRegardless()
        startPointer()
        if !watchingReplace { watchingReplace = true; ReplaceMode.shared.begin() }
    }

    // MARK: Main, curseur système et sons d'appui

    private func startPointer() {
        pointerTimer?.invalidate()
        wasDown = (NSEvent.pressedMouseButtons & 1) != 0
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.pollPointer() }
        RunLoop.main.add(t, forMode: .common)
        pointerTimer = t
    }

    private func stopPointer() {
        pointerTimer?.invalidate(); pointerTimer = nil
        setSystemCursorHidden(false)
        pointer.point = nil; pointer.closed = false
    }

    private func setSystemCursorHidden(_ hide: Bool) {
        guard hide != cursorHidden else { return }
        cursorHidden = hide
        if hide { NSCursor.hide() } else { NSCursor.unhide() }
    }

    /// La main remplace le curseur tant qu'il est sur l'écran Wii. Poing fermé quand le bouton est enfoncé ; un son à l'appui, au relâchement, et
    /// de petits tics quand on déplace un curseur ou une poignée en gardant le bouton enfoncé.
    private func pollPointer() {
        guard let w = window else { stopPointer(); return }
        let loc = NSEvent.mouseLocation
        var screenRect = w.frame.insetBy(dx: Self.margin / 2, dy: Self.margin / 2)
        if let g = tvGeo {          // dans le téléviseur : la main n'existe que sur la vitre
            screenRect = NSRect(x: w.frame.midX - g.holeOnScreen.width / 2, y: w.frame.midY - g.holeOnScreen.height / 2, width: g.holeOnScreen.width, height: g.holeOnScreen.height)
        }
        // Une autre fenêtre de l'app au-dessus de l'écran Wii (sélecteur de fichier, notification…) : le vrai curseur reprend la main, sinon on ne le voit pas.
        let covered = NSApp.windows.contains { $0 !== w && $0.isVisible && $0.level.rawValue >= w.level.rawValue && $0.frame.contains(loc) }
        let inside = NSApp.isActive && screenRect.contains(loc) && !exiting && !covered
        setSystemCursorHidden(inside)
        let down = (NSEvent.pressedMouseButtons & 1) != 0
        let p = CGPoint(x: loc.x - w.frame.minX, y: w.frame.maxY - loc.y)
        pointer.point = inside ? p : nil
        if pointer.closed != (down && inside) { pointer.closed = down && inside }
        if inside && down && !wasDown { Feedback.shared.wiiPress(); lastSoundPoint = p }
        else if down && wasDown && inside, hypot(p.x - lastSoundPoint.x, p.y - lastSoundPoint.y) > 14 { Feedback.shared.wiiSlide(); lastSoundPoint = p }
        wasDown = down
    }

    /// La fenêtre garde son centre : seule sa taille suit celle de l'écran (menu, ou outil plus grand).
    private func resizeWindow() {
        guard let w = window else { return }
        var s = stage
        if tool == nil { windowStage = s } else { windowStage = CGSize(width: max(windowStage.width, s.width), height: max(windowStage.height, s.height)); s = windowStage }
        var f = NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height)
        if let vis = (w.screen ?? NSScreen.main)?.visibleFrame {
            let m = tvGeo == nil ? Self.margin / 2 : 0          // le téléviseur reste entièrement visible
            f.origin.x = min(max(f.origin.x, vis.minX - m), max(vis.maxX - f.width + m, vis.minX - m))
            f.origin.y = min(max(f.origin.y, vis.minY - m), max(vis.maxY - f.height + m, vis.minY - m))
        }
        if abs(w.frame.width - f.width) > 0.5 || abs(w.frame.height - f.height) > 0.5 || abs(w.frame.minX - f.minX) > 0.5 || abs(w.frame.minY - f.minY) > 0.5 {
            w.setFrame(f, display: true, animate: false)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        reset()
    }

    private func reset() {
        stopPointer()
        if watchingReplace { watchingReplace = false; ReplaceMode.shared.end() }
        windowStage = .zero
        token += 1
        tool = nil; panel = 0; panelShown = 0; interactive = false; exiting = false; hasMenu = false
        host.content = 0; host.tab = 0
        let m = menuModel
        m.wiiZoom = 0; m.wiiDim = 0; m.wiiInteractive = false; m.cursor = nil; m.hover = nil; m.hoverChild = nil
    }

    // MARK: Essai visuel (snapshots) : pose l'écran dans un état donné, sans animation
    func debugPose(tool view: AnyView, panel p: CGFloat, zoom z: CGFloat, tab: CGFloat, content: Double, tile rect: CGRect, hasMenu menu: Bool) {
        hasMenu = menu
        tile = rect
        let m = menuModel
        m.wiiAnchor = UnitPoint(x: rect.midX / WiiLayout.size.width, y: rect.midY / WiiLayout.size.height)
        m.wiiZoom = z; m.wiiDim = z
        host.content = content; host.tab = tab
        panel = p; panelShown = p > 0 || z >= 1 ? 1 : 0
        tool = wrapped(view)
    }
}

// MARK: Vue

struct WiiShellView: View {
    @ObservedObject var model: WheelModel
    @ObservedObject var shell: WiiShell

    var body: some View {
        let tv = shell.tvGeo
        let full = shell.fullSize, screen = shell.screenSize, stage = tv?.layoutStage ?? shell.stage          // repère de mise en page (avant réduction éventuelle du téléviseur)
        // Dans le téléviseur, le menu s'agrandit pour remplir toute la vitre quand l'outil ouvert la rend plus grande que lui
        let mf: CGFloat = tv != nil && shell.hasMenu ? screen.width / WiiLayout.displaySize.width : 1
        let menu = CGSize(width: WiiLayout.displaySize.width * mf, height: WiiLayout.displaySize.height * mf)
        let p = shell.panel
        let s = WiiLayout.scale * mf, k = 1 + WiiShell.zoomAmount * (shell.hasMenu ? 1 : 0)
        // Départ : la case telle qu'elle est après le zoom de la caméra. Le panneau garde les proportions de l'écran final et grandit
        // d'un seul mouvement (mise à l'échelle uniforme), sans que rien ne se déforme ni ne parte dans une autre direction.
        let ox = (stage.width - menu.width) / 2, oy = (stage.height - menu.height) / 2
        let t = shell.tile
        let sw = max(t.width * s * k, 40), sh = sw * full.height / full.width
        let start = CGRect(x: ox + t.midX * s - sw / 2, y: oy + t.midY * s - sh / 2, width: sw, height: sh)
        let endSize = tv != nil ? screen : full          // dans le téléviseur, le panneau finit à la taille de la vitre (il est réduit s'il est plus grand)
        let end = CGRect(x: (stage.width - endSize.width) / 2, y: (stage.height - endSize.height) / 2, width: endSize.width, height: endSize.height)
        let rect = CGRect(x: start.minX + (end.minX - start.minX) * p, y: start.minY + (end.minY - start.minY) * p,
                          width: start.width + (end.width - start.width) * p, height: start.height + (end.height - start.height) * p)
        let scale = rect.width / full.width
        let radius = (17 / max(scale, 0.05)) * (1 - p) + (tv == nil ? 30 : 0) * p            // coins de la case au départ, de l'écran à l'arrivée
        let back = CGSize(width: menu.width + (screen.width - menu.width) * p, height: menu.height + (screen.height - menu.height) * p)

        let core = ZStack {
            // Voile presque invisible sous tout l'écran : macOS laisse passer les clics sur les pixels totalement transparents d'une fenêtre,
            // et c'est alors la fenêtre derrière (le Finder…) qui les recevait.
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.02)).frame(width: screen.width, height: screen.height)
            if shell.hasMenu {
                WiiMenuView(model: model, onChoose: { shell.chooseHovered() }, onClose: { shell.finish() }, inTV: tv != nil).scaleEffect(mf)
            }
            if let tool = shell.tool {
                RoundedRectangle(cornerRadius: 17 + 17 * p, style: .continuous).fill(Color.black)
                    .frame(width: back.width, height: back.height)
                    .shadow(color: .black.opacity(0.35 * Double(shell.hasMenu ? model.wiiDim : min(1, p * 3))), radius: 24, y: 10)
                    .opacity(tv != nil ? 0 : (shell.hasMenu ? Double(model.wiiDim) : Double(min(1, p * 4))))
                tool
                    .environment(\.wiiInTV, tv != nil)
                    .id(shell.toolID)
                    .frame(width: full.width, height: full.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .scaleEffect(scale)
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(Double(shell.panelShown))
                    .allowsHitTesting(shell.interactive)
            }
            if tv == nil { WiiHandOverlay(pointer: shell.pointer) }
        }
        .frame(width: stage.width, height: stage.height)

        Group {
            if let tv = tv { WiiTVSet(tv) { core } } else { core }
        }
        .animation(shell.interactive ? .easeInOut(duration: 0.18) : nil, value: shell.naturalSize)     // la taille ne bouge pas pendant l'entrée
        .scaleEffect(shell.exiting ? 0.94 : 1)
        .opacity(shell.exiting ? 0 : 1)
        .animation(.easeIn(duration: 0.22), value: shell.exiting)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { if tv != nil { WiiHandOverlay(pointer: shell.pointer) } }          // la main est dans le repère de la fenêtre, hors de la réduction
    }
}
