import SwiftUI
import AppKit

/// Disposition du menu « bulles » : une grosse bulle au centre (aperçu et données de la sélection), les outils en bulles de tailles variées
/// serrées tout autour, sur un seul anneau, qui flottent doucement.
enum BubbleLayout {
    static let panelSize: CGFloat = 760
    static let centerDiameter: CGFloat = 122
    struct Spot { var x: CGFloat; var y: CGFloat; var d: CGFloat }

    private static func overlaps(_ a: Spot, _ b: Spot, gap: CGFloat = 5) -> Bool { hypot(a.x - b.x, a.y - b.y) < (a.d + b.d) / 2 + gap }

    /// Positions (relatives au centre) des bulles principales : toutes sur un seul anneau collé à la bulle du centre, quel que soit leur nombre.
    /// Le rayon est cherché au plus juste pour que rien ne se chevauche ; si l'anneau devient trop grand pour le panneau, les bulles rétrécissent.
    static func spots(_ n: Int) -> [Spot] {
        guard n > 0 else { return [] }
        let sizes: [CGFloat] = [92, 100, 88, 96, 90, 98]
        let center = Spot(x: 0, y: 0, d: centerDiameter)
        let maxRadius: CGFloat = 235
        // Plus il y a de bulles, plus elles sont petites (elles restent toutes tout près du centre).
        var scale: CGFloat = n <= 6 ? 0.82 : 0.82 * CGFloat(pow(6.0 / Double(n), 0.6))
        while true {
            var r = centerDiameter / 2 + 30 * scale
            while r <= maxRadius {
                var s: [Spot] = []
                for i in 0..<n {
                    s.append(spot(i, of: n, radius: r, sizes: sizes, scale: scale))
                }
                var clash = false
                for i in s.indices {
                    if overlaps(s[i], center) { clash = true }
                    for j in s.indices where j > i { if overlaps(s[i], s[j]) { clash = true } }
                }
                if !clash { return s }
                r += 2
            }
            scale -= 0.04
            if scale < 0.3 { return ringAt(n, radius: maxRadius, sizes: sizes, scale: 0.3) }
        }
    }

    private static func spot(_ i: Int, of n: Int, radius r: CGFloat, sizes: [CGFloat], scale: CGFloat) -> Spot {
        let deg: Double = -90.0 + 360.0 / Double(n) * Double(i)
        let a = CGFloat(deg * Double.pi / 180)
        let d: CGFloat = sizes[(i * 5 + 1) % sizes.count] * scale
        return Spot(x: cos(a) * r, y: sin(a) * r, d: d)
    }

    private static func ringAt(_ n: Int, radius r: CGFloat, sizes: [CGFloat], scale: CGFloat) -> [Spot] {
        (0..<n).map { spot($0, of: n, radius: r, sizes: sizes, scale: scale) }
    }

    /// Sous-bulles d'un groupe : serrées contre la bulle parente (presque collées), en éventail vers l'extérieur.
    static func childSpots(parent: Spot, count: Int) -> [Spot] {
        let dc: CGFloat = max(44, min(66, parent.d * 0.8))
        let dist = parent.d / 2 + dc / 2 + 2
        let ang = atan2(parent.y, parent.x)
        let step = 2 * asin(min((dc + 5) / (2 * dist), 0.99))
        return (0..<count).map { k in
            let a = ang + (CGFloat(k) - CGFloat(count - 1) / 2) * step
            return Spot(x: parent.x + cos(a) * dist, y: parent.y + sin(a) * dist, d: dc)
        }
    }

    /// Distance d'un point au segment [a, b].
    private static func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        let t = l2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// Bulle touchée par `p` (relatif au centre) : sous-bulle du groupe survolé d'abord, puis bulle principale.
    /// Le groupe reste ouvert sur la bulle parente, sur ses sous-bulles et sur le « pont » qui les relie : on peut glisser du parent à l'enfant.
    static func hit(_ p: CGPoint, count n: Int, hoverParent: Int?, childCount: Int) -> (parent: Int?, child: Int?) {
        let s = spots(n)
        func dist(_ a: Spot) -> CGFloat { hypot(p.x - a.x, p.y - a.y) }
        if let h = hoverParent, s.indices.contains(h), childCount > 0 {
            let kids = childSpots(parent: s[h], count: childCount)
            if let k = kids.indices.min(by: { dist(kids[$0]) < dist(kids[$1]) }), dist(kids[k]) < kids[k].d / 2 + 12 { return (h, k) }
            let bridge = kids.contains { distToSegment(p, CGPoint(x: s[h].x, y: s[h].y), CGPoint(x: $0.x, y: $0.y)) < 30 }
            if dist(s[h]) < s[h].d / 2 + 16 || bridge { return (h, nil) }
        }
        if let i = s.indices.min(by: { dist(s[$0]) < dist(s[$1]) }), dist(s[i]) < s[i].d / 2 + 6 { return (i, nil) }
        return (nil, nil)
    }
}

/// Couleurs des bulles (une par outil, une par format) : de quoi ne plus avoir un menu tout noir.
enum BubblePalette {
    private static let all: [NSColor] = ["2B7FFF", "E5333A", "00B87A", "0A8FD6", "F2790F", "8C52FF", "E8488B", "14A39A", "E0A800", "4F5BD5"].map { NSColor(hex: $0)! }
    private static func pick(_ key: String) -> NSColor { all[abs(key.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }) % all.count] }
    private static func named(_ hex: String) -> NSColor { NSColor(hex: hex)! }

    static func color(for item: WheelItem) -> NSColor {
        let byId: [String: String] = ["compress": "2B7FFF", "metadata": "8C52FF", "select": "4F5BD5", "collage": "E8488B", "createCollage": "E8488B", "document": "E0A800", "bg": "14A39A",
                                      "transform": "00B87A", "vtransform": "00B87A", "edit": "E5333A", "zipFiles": "0A8FD6", "ocr": "E0A800", "vaudio": "8C52FF", "multi-pdf": "E5333A"]
        if let h = byId[item.id] { return named(h) }
        if item.symbol == nil { return ext(item.id == "multi-pdf" ? "pdf" : item.id) }          // formats : la couleur du format
        return pick(item.id)
    }

    /// Couleur d'une extension, comme les icônes de formats (PDF rouge, tableurs verts, images bleues…).
    static func ext(_ e: String) -> NSColor {
        let m: [String: String] = ["pdf": "E5333A", "png": "2B7FFF", "heic": "2B7FFF", "jpg": "F2790F", "jpeg": "F2790F", "webp": "14A39A", "avif": "8C52FF", "tiff": "0A8FD6", "tif": "0A8FD6", "bmp": "4F5BD5",
                                   "mp4": "8C52FF", "mov": "8C52FF", "mkv": "4F5BD5", "webm": "14A39A", "avi": "0A8FD6", "wmv": "2B7FFF", "gif": "E8488B", "mp3": "00B87A", "m4a": "00B87A", "wav": "14A39A",
                                   "flac": "0A8FD6", "ogg": "F2790F", "opus": "8C52FF", "aiff": "4F5BD5", "wma": "2B7FFF", "m4r": "E8488B", "docx": "0A8FD6", "pages": "F2790F", "txt": "E0A800", "md": "E0A800",
                                   "html": "F34E0B", "xlsx": "00B87A", "csv": "14A39A", "tsv": "14A39A", "ods": "00B87A", "pptx": "F2790F", "epub": "E5333A", "zip": "8C52FF", "tar": "8C52FF", "gzip": "8C52FF",
                                   "srt": "E0A800", "vtt": "E0A800", "qr": "4F5BD5", "dir": "0A8FD6"]
        if let h = m[e.lowercased()] { return named(h) }
        return pick(e.lowercased())
    }
}

/// Transition d'une sous-bulle : elle jaillit de sa bulle parente.
private struct PopFromParent: ViewModifier {
    let dx: CGFloat, dy: CGFloat, hidden: Bool
    func body(content: Content) -> some View {
        content.scaleEffect(hidden ? 0.25 : 1).offset(x: hidden ? dx : 0, y: hidden ? dy : 0).opacity(hidden ? 0 : 1)
    }
}

struct BubbleMenuView: View {
    @ObservedObject var model: WheelModel
    @ObservedObject var settings = AppSettings.shared

    private var accentTop: Color { Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .white, 0.12)) }
    private var accentBottom: Color { Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .black, 0.1)) }
    private var accentRim: Color { Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .white, 0.2)) }
    private let bounce = Animation.spring(response: 0.42, dampingFraction: 0.42)          // rebond : dépasse puis se pose

    var body: some View {
        let S = BubbleLayout.panelSize
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let spots = BubbleLayout.spots(model.items.count)
            ZStack {
                centerBubble(t)
                ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                    if spots.indices.contains(i) {
                        bubble(item, spots[i], index: i, t: t, active: model.hover == i && (item.enabled || item.isGroup), push: push(for: i, spots: spots), pointer: model.hover == i ? model.cursor : nil)
                    }
                }
                if let h = model.hover, model.items.indices.contains(h), model.items[h].isGroup, spots.indices.contains(h) {
                    let kids = BubbleLayout.childSpots(parent: spots[h], count: model.items[h].children.count)
                    ForEach(Array(model.items[h].children.enumerated()), id: \.element.id) { k, child in
                        bubble(child, kids[k], index: 40 + k, t: t, active: model.hoverChild == k && child.enabled, push: .zero, pointer: model.hoverChild == k ? model.cursor : nil)
                            .transition(.modifier(active: PopFromParent(dx: spots[h].x - kids[k].x, dy: spots[h].y - kids[k].y, hidden: true), identity: PopFromParent(dx: 0, dy: 0, hidden: false)))
                    }
                }
            }
            .frame(width: S, height: S)
        }
        .scaleEffect(model.appear ? 1 : 0.9)
        .opacity(model.appear ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: model.appear)
        .animation(bounce, value: model.hover)
        .animation(bounce, value: model.hoverChild)
        .environment(\.colorScheme, .dark)
    }

    /// Les bulles voisines de celle qui est survolée s'écartent un peu, comme de vraies bulles qu'on pousse.
    private func push(for i: Int, spots: [BubbleLayout.Spot]) -> CGSize {
        guard let h = model.hover, h != i, spots.indices.contains(h), spots.indices.contains(i) else { return .zero }
        let dx = spots[i].x - spots[h].x, dy = spots[i].y - spots[h].y, d = max(hypot(dx, dy), 1)
        let k = 16 * exp(-d / 120)
        return CGSize(width: dx / d * k, height: dy / d * k)
    }

    // MARK: Peaux des bulles

    private func tone(_ c: NSColor, light: CGFloat = 0, dark: CGFloat = 0) -> Color {
        Color(nsColor: c.mixed(with: .white, light).mixed(with: .black, dark))
    }

    /// Le fond d'une bulle selon l'aspect choisi (réglage interne). Survolée : toujours la teinte de l'accent.
    @ViewBuilder private func skin(_ look: BubbleLook, base c: NSColor, d: CGFloat, active: Bool) -> some View {
        if active {
            Circle().fill(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom))
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.26), .clear], startPoint: .top, endPoint: .center))
            Circle().stroke(accentRim, lineWidth: 1.6)
        } else {
            switch look {
            case .gel:        // gel coloré : dégradé, reflet brillant en haut, bord assombri
                Circle().fill(LinearGradient(colors: [tone(c, light: 0.28), tone(c), tone(c, dark: 0.22)], startPoint: .top, endPoint: .bottom))
                Circle().fill(RadialGradient(colors: [.clear, Color.black.opacity(0.22)], center: UnitPoint(x: 0.5, y: 0.4), startRadius: d * 0.28, endRadius: d * 0.55))
                Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.62, height: d * 0.32).offset(y: -d * 0.27).blur(radius: 0.8)
                Circle().stroke(Color.white.opacity(0.38), lineWidth: 1)
            case .glass:      // verre teinté : translucide, double liseré, lueur intérieure
                Circle().fill(LinearGradient(colors: [tone(c, light: 0.1).opacity(0.9), tone(c, dark: 0.18).opacity(0.94)], startPoint: .top, endPoint: .bottom))
                Circle().fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.03)], startPoint: .top, endPoint: .center))
                Circle().stroke(tone(c, light: 0.3).opacity(0.7), lineWidth: 7).blur(radius: 7).clipShape(Circle())
                Circle().stroke(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1.4)
            case .paper:      // carte claire : le bas porte la couleur de l'outil
                Circle().fill(LinearGradient(colors: [Color(white: 0.995), Color(red: 0.92, green: 0.93, blue: 0.96)], startPoint: .top, endPoint: .bottom))
                Rectangle().fill(LinearGradient(colors: [tone(c, light: 0.1), tone(c, dark: 0.12)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d, height: d * 0.22).offset(y: d * 0.39).clipShape(Circle())
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 1)
            case .night:      // nuit : fond sombre, liseré lumineux de la couleur de l'outil, lueur en bas
                Circle().fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                Circle().fill(RadialGradient(colors: [tone(c).opacity(0.42), .clear], center: UnitPoint(x: 0.5, y: 1.05), startRadius: 2, endRadius: d * 0.7))
                Circle().stroke(AngularGradient(colors: [tone(c, light: 0.2), tone(c).opacity(0.15), tone(c).opacity(0.7), tone(c, light: 0.2)], center: .center), lineWidth: 2.6)
            }
        }
    }

    private func glyphColor(_ look: BubbleLook, base c: NSColor, active: Bool, enabled: Bool) -> Color {
        let on: Color = (look == .paper && !active) ? tone(c, dark: 0.1) : Color.white
        return on.opacity(enabled ? 0.97 : 0.4)
    }

    /// Une bulle d'outil : peau colorée, symbole (ou texte pour les formats), nom à l'extérieur, flottement léger.
    /// Survolée : elle rebondit en grossissant, prend la teinte de l'accent et se laisse attirer un peu vers le pointeur.
    private func bubble(_ item: WheelItem, _ s: BubbleLayout.Spot, index i: Int, t: Double, active: Bool, push: CGSize, pointer: CGPoint?) -> some View {
        let look = settings.effectiveBubbleLook
        let c = BubblePalette.color(for: item)
        let phase = Double(i) * 1.7
        let fx = sin(t * 0.9 + phase) * 4.5, fy = cos(t * 0.72 + phase * 1.3) * 4.5
        let d = s.d, grow: CGFloat = active ? 1.2 : 1
        let labelText = item.label.capitalized
        let labelVisible = item.symbol != nil && !(active && item.isGroup) && (i < 40 || active)  // groupe ouvert : place à ses sous-bulles, dont seule celle survolée affiche son nom
        var magnet = CGSize.zero
        if active, let p = pointer { magnet = CGSize(width: max(-9, min(9, (p.x - s.x) * 0.16)), height: max(-9, min(9, (p.y - s.y) * 0.16))) }
        let glow: Color = active ? accentBottom.opacity(0.6) : tone(c).opacity(look == .paper ? 0.0 : (look == .glass ? 0.3 : 0.45))
        return ZStack {
            ZStack {
                skin(look, base: c, d: d, active: active)
                Group {
                    if let sym = item.symbol {
                        Image(systemName: sym).font(.system(size: d * 0.36, weight: .semibold))
                    } else {
                        Text(item.label).font(.system(size: d * 0.2, weight: .heavy, design: .rounded)).lineLimit(2).minimumScaleFactor(0.5).multilineTextAlignment(.center).padding(.horizontal, 7)
                    }
                }
                .foregroundStyle(glyphColor(look, base: c, active: active, enabled: item.enabled))
                .shadow(color: look == .paper && !active ? .clear : Color.black.opacity(0.3), radius: 1.5, y: 1)
                if item.isGroup { Circle().fill((look == .paper && !active ? tone(c) : Color.white).opacity(0.9)).frame(width: 6, height: 6).offset(y: d * 0.34) }       // contient d'autres bulles
            }
            .frame(width: d, height: d)
            .shadow(color: glow, radius: active ? 16 : 11, y: active ? 5 : 8)
            .shadow(color: Color.black.opacity(0.28), radius: 4, y: 3)
            .opacity(item.enabled ? 1 : 0.5)
            .scaleEffect(grow)
            if labelVisible {          // nom dans une petite capsule posée à cheval sur le bas de la bulle
                Text(labelText)
                    .font(.system(size: active ? 11.5 : 10.5, weight: .semibold)).foregroundStyle(active ? Color.white : Theme.text.opacity(0.9))
                    .fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 3.5)
                    .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color(white: 0.97))))
                    .overlay(Capsule().strokeBorder(active ? accentRim : Color.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                    .opacity(item.enabled ? 1 : 0.5)
                    .offset(y: d * grow / 2)
            }
        }
        .offset(x: push.width, y: push.height)
        .offset(x: magnet.width, y: magnet.height)
        .offset(x: s.x + fx, y: s.y + fy)
    }

    // MARK: Centre : une pile de cadres en vrac + les données

    private func centerBubble(_ t: Double) -> some View {
        let D = BubbleLayout.centerDiameter
        let pulse = 1 + sin(t * 1.1) * 0.01
        let lines = Array(model.infoLines.prefix(2))
        return ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.98, green: 0.985, blue: 1.0), Color(red: 0.87, green: 0.9, blue: 0.95)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.6)
            pile.offset(y: -D * 0.1).scaleEffect(0.92)
            VStack(spacing: 1) {
                Spacer()
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line).font(.system(size: i == 0 ? 11 : 8.5, weight: i == 0 ? .bold : .medium)).foregroundStyle(Theme.text.opacity(i == 0 ? 0.95 : 0.65))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 11)
            if model.fileCount > 4 {
                Text("+\(model.fileCount - 4)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2.5).background(Capsule().fill(Theme.orange)).offset(x: D * 0.36, y: -D * 0.34)
            }
        }
        .frame(width: D, height: D)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .scaleEffect(pulse)
    }

    /// Les aperçus empilés « en vrac » : cadres aux coins ronds, légèrement tournés et décalés ; le premier fichier est dessus.
    private var pile: some View {
        let items = Array(model.previews.prefix(4))
        let rot: [Double] = [-4, 8, -10, 13], dx: [CGFloat] = [0, 11, -12, 6], dy: [CGFloat] = [-1, -5, 2, 5]
        return ZStack {
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.08)).frame(width: 46, height: 56)
            }
            ForEach(Array(items.enumerated()).reversed(), id: \.element.id) { i, it in
                frame(it, single: items.count == 1)
                    .rotationEffect(.degrees(rot[i])).offset(x: dx[i] * (items.count == 1 ? 0 : 1), y: dy[i])
            }
        }
    }

    @ViewBuilder private func frame(_ it: WheelPreviewItem, single: Bool) -> some View {
        let box: CGSize = single ? CGSize(width: 66, height: 62) : CGSize(width: 54, height: 52)
        if let img = it.image, img.size.width > 0 {
            let a = img.size.width / img.size.height
            let w = a >= box.width / box.height ? box.width : box.height * a, h = a >= box.width / box.height ? box.width / a : box.height
            Image(nsImage: img).resizable().scaledToFill().frame(width: w, height: h).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white, lineWidth: 2.4))
                .overlay { if it.isVideo { Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white).shadow(radius: 2) } }
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        } else {
            extCard(it.ext, w: single ? 50 : 42, h: single ? 58 : 50)
        }
    }

    /// Carte « format » : carré arrondi coloré au coin replié, l'extension en gros (comme les icônes de formats de fichiers).
    private func extCard(_ ext: String, w: CGFloat, h: CGFloat) -> some View {
        let c = BubblePalette.ext(ext)
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(colors: [tone(c, light: 0.12), tone(c, dark: 0.1)], startPoint: .top, endPoint: .bottom))
            Path { p in p.move(to: CGPoint(x: w - 13, y: 0)); p.addLine(to: CGPoint(x: w, y: 13)); p.addLine(to: CGPoint(x: w - 13, y: 13)); p.closeSubpath() }
                .fill(Color.white.opacity(0.3)).frame(width: w, height: h, alignment: .topLeading)
            Text(ext).font(.system(size: ext.count > 3 ? 10 : 12, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.leading, 5).padding(.bottom, 5)
        }
        .frame(width: w, height: h).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1.6))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: Réception du glisser-déposer
final class BubbleDropView: NSView {
    weak var controller: WheelController?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .URL, .string]) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        let p = convert(info.draggingLocation, from: nil)
        controller?.bubbleHover(at: CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY))
        return controller?.hoveredItemEnabled == true ? .copy : []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { controller?.bubbleExited() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { controller?.hoveredItemEnabled == true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { _ = update(sender); return controller?.drop() ?? false }
    override func mouseUp(with event: NSEvent) { controller?.dismiss() }
}
