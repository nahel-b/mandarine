import SwiftUI

enum WheelGeometry {
    static let size: CGFloat = 480          // côté du carré qui contient la roue (assez grand pour le 2ᵉ niveau)
    /// L'anneau grandit un peu quand il y a beaucoup de segments (plus de 8), pour garder les libellés lisibles.
    static func outer(_ n: Int) -> CGFloat { 116 + CGFloat(min(max(n, 8), 12) - 8) * 5 }
    static func inner(_ n: Int) -> CGFloat { 46 + CGFloat(min(max(n, 8), 12) - 8) * 1.5 }
    static let captionHeight: CGFloat = 0

    // 2ᵉ niveau : sous-pétales plus éloignés du centre que l'anneau de base
    static func childInner(_ n: Int) -> CGFloat { outer(n) + 7 }      // marge entre la roue (disque de verre compris) et les sous-pétales
    static let childThickness: CGFloat = 62     // épaisseur radiale : les sous-pétales vont plus loin vers l'extérieur
    static func childOuter(_ n: Int) -> CGFloat { childInner(n) + childThickness }
    static let petalCR: CGFloat = 11             // rayon des coins des pétales (partagé avec WheelView)
    static let petalGap: CGFloat = 9             // écart entre deux pétales voisins
    static let blobMargin: CGFloat = 6           // marge uniforme du fond autour des sous-pétales
    static let childStep: Double = 31            // ouverture angulaire d'un sous-pétale (degrés)

    /// Angles (degrés) des sous-pétales, centrés sur celui du pétale parent.
    static func childCenters(parent: Double, count m: Int) -> [Double] {
        (0..<m).map { parent + (Double($0) - Double(m - 1) / 2) * childStep }
    }

    /// Pétale parent et sous-pétale sous un point (repère : centre de la roue, y vers le bas).
    static func hit(at p: CGPoint, count n: Int, hoverParent: Int?, childCount: Int) -> (parent: Int?, child: Int?) {
        let r = hypot(p.x, p.y)
        if let hp = hoverParent, childCount > 0, r >= childInner(n) - 10, r <= childOuter(n) + 16 {
            let a = atan2(p.y, p.x) * 180 / .pi
            let parentCenter = -90.0 + 360.0 / Double(n) * Double(hp)
            for (ci, c) in childCenters(parent: parentCenter, count: childCount).enumerated() {
                var d = (a - c).truncatingRemainder(dividingBy: 360)
                if d > 180 { d -= 360 }; if d < -180 { d += 360 }
                if abs(d) <= childStep / 2 + 3 { return (hp, ci) }
            }
        }
        return (index(at: p, count: n), nil)
    }

    /// Index du segment sous un point (repère : origine au centre de la roue, y vers le bas), nil si hors anneau.
    static func index(at p: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let r = hypot(p.x, p.y)
        guard r >= inner(count) - 10, r <= outer(count) + 50 else { return nil }
        var a = atan2(p.y, p.x) + .pi / 2          // 0 = haut, sens horaire
        let step = 2 * .pi / CGFloat(count)
        a = (a + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return min(count - 1, Int(a / step))
    }
}

struct Sector: Shape {
    var start: Angle, end: Angle, inner: CGFloat, outer: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Pétale : côtés **parallèles** à ceux du voisin (couloir de largeur constante), puis coins arrondis par `grow`.
/// `d` = décalage perpendiculaire de chaque côté radial vers l'intérieur du pétale.
struct Petal: Shape {
    var center: Double            // angle du centre (degrés, 0 = droite, sens horaire)
    var step: Double              // ouverture angulaire du secteur (degrés)
    var n: Int
    var inner: CGFloat, outer: CGFloat
    var d: CGFloat
    var grow: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var base = Path()
        if n == 1 {
            base.addArc(center: c, radius: outer, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
            base.addArc(center: c, radius: inner, startAngle: .degrees(270), endAngle: .degrees(-90), clockwise: true)
            base.closeSubpath()
            return base
        }
        let a0 = (center - step / 2) * .pi / 180, a1 = (center + step / 2) * .pi / 180
        // point d'intersection d'une droite décalée de d avec un cercle de rayon R
        func pt(_ alpha: Double, _ normalSign: Double, _ R: CGFloat) -> CGPoint {
            let u = CGPoint(x: cos(alpha), y: sin(alpha))
            let nrm = CGPoint(x: -sin(alpha) * normalSign, y: cos(alpha) * normalSign)
            let sLen = sqrt(max(0, R * R - d * d))
            return CGPoint(x: c.x + sLen * u.x + d * nrm.x, y: c.y + sLen * u.y + d * nrm.y)
        }
        let o0 = pt(a0, 1, outer), o1 = pt(a1, -1, outer), i0 = pt(a0, 1, inner), i1 = pt(a1, -1, inner)
        func ang(_ p: CGPoint) -> Angle { .radians(atan2(p.y - c.y, p.x - c.x)) }
        base.move(to: o0)
        base.addArc(center: c, radius: outer, startAngle: ang(o0), endAngle: ang(o1), clockwise: false)
        base.addLine(to: i1)
        base.addArc(center: c, radius: inner, startAngle: ang(i1), endAngle: ang(i0), clockwise: true)
        base.closeSubpath()
        guard grow > 0 else { return base }
        let stroked = base.strokedPath(StrokeStyle(lineWidth: grow * 2, lineJoin: .round))
        return Path(base.cgPath.union(stroked.cgPath, using: .winding))
    }
}

extension WheelGeometry {
    /// Fond de la roue : disque de base, plus (si un groupe est survolé) une excroissance arrondie qui enveloppe ses sous-pétales.
    /// `t` (0…1) pilote la croissance de l'excroissance.
    static func discPath(center c: CGPoint, n: Int, parent: Int?, childCount m: Int, t: CGFloat) -> CGPath {
        let R = outer(n) + 11
        let circle = CGPath(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2), transform: nil)
        guard let p = parent, m > 0, t > 0.002 else { return circle }
        let cr = petalCR
        let theta = -90.0 + 360.0 / Double(n) * Double(p)
        let cin = childInner(n), cout = childOuter(n)
        // Même géométrie que les sous-pétales (côtés parallèles, mêmes rayons), puis élargie d'une marge uniforme :
        // les bords du fond restent donc parallèles à ceux des sous-pétales et les coins sont concentriques.
        let baseInner = cin + cr + 2
        let baseOuter = baseInner + max(0.5, (cout - cr - 2 - baseInner) * t)
        let grow = cr + blobMargin
        var result = circle
        for angle in childCenters(parent: theta, count: m) {
            let petal = Petal(center: angle, step: childStep, n: 2, inner: baseInner, outer: baseOuter, d: petalGap / 2 + cr, grow: 0)
            let base = petal.path(in: CGRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2)).cgPath
            let grown = Path(base).strokedPath(StrokeStyle(lineWidth: grow * 2, lineJoin: .round)).cgPath
            result = result.union(base.union(grown, using: .winding), using: .winding)
        }
        return result
    }
}

struct WheelDisc: Shape {
    var n: Int, parent: Int?, count: Int, t: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(WheelGeometry.discPath(center: CGPoint(x: rect.midX, y: rect.midY), n: n, parent: parent, childCount: count, t: t))
    }
}

final class WheelModel: ObservableObject {
    @Published var items: [WheelItem] = []
    @Published var mode: WheelMode = .convert
    @Published var hover: Int? = nil
    @Published var hoverChild: Int? = nil
    @Published var blobParent: Int? = nil        // groupe dont le fond s'agrandit
    @Published var blobCount = 0
    @Published var blobT: Double = 0
    // style « Wii »
    @Published var wiiPage = 0
    @Published var wiiNav = false               // le pointeur est sur la flèche « page suivante »
    @Published var cursor: CGPoint? = nil       // position du pointeur main (repère de l'écran Wii)
    @Published var fileCount = 1
    @Published var sizeLabel = ""
    @Published var infoLines: [String] = []       // 2-3 lignes au centre : taille, durée, dimensions…
    @Published var appear = false          // pilote l'animation d'apparition (rebond)
}

struct WheelView: View {
    @ObservedObject var model: WheelModel
    @ObservedObject var settings = AppSettings.shared
    var sizeLabel: String { model.sizeLabel }

    private let cr: CGFloat = WheelGeometry.petalCR          // rayon des coins des pétales
    private let gapPts: CGFloat = WheelGeometry.petalGap       // espace entre pétales
    private var orangeTop: Color {
        AppSettings.shared.isDefaultAccent ? Color(red: 1.0, green: 0.46, blue: 0.22) : Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .white, 0.12))
    }
    private var orangeBottom: Color {
        AppSettings.shared.isDefaultAccent ? Color(red: 0.93, green: 0.33, blue: 0.12) : Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .black, 0.1))
    }

    /// Liseré d'un pétale survolé : la couleur de tinte, en plus claire.
    private var accentRim: Color { Color(nsColor: AppSettings.shared.accentNSColor.mixed(with: .white, 0.2)) }

    var body: some View {
        let n = max(model.items.count, 1)
        let R = WheelGeometry.outer(n) + 11
        ZStack {
            // le flou vient du NSVisualEffectView placé sous la vue ; ici la teinte, le reflet et le liseré, sur la MÊME forme que le verre
            let disc = WheelDisc(n: n, parent: model.blobParent, count: model.blobCount, t: CGFloat(model.blobT))
            disc.fill(Color.black.opacity(0.22))
                .overlay(disc.fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.0), Color.white.opacity(0.04)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing)))
                .frame(width: R * 2, height: R * 2)
                .shadow(color: .black.opacity(0.28), radius: 24, y: 8)
            disc.stroke(LinearGradient(colors: [Color.white.opacity(0.34), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                .frame(width: R * 2, height: R * 2)
            Circle().strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: R * 2 - 12, height: R * 2 - 12)
            ForEach(Array(model.items.enumerated()), id: \.element.id) { i, item in
                petal(i, item)
            }
            if let h = model.hover, model.items.indices.contains(h), model.items[h].isGroup {
                childPetals(parentIndex: h, parent: model.items[h]).transition(.scale(scale: 0.93).combined(with: .opacity))     // 0,8 avant : moins de décalage vers l'extérieur
            }
            center
        }
        .environment(\.colorScheme, .dark)
        // apparition discrète : petit grossissement (92 % → 100 %), quasi sans rebond
        .scaleEffect(model.appear ? 1 : 0.92)
        .opacity(model.appear ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.appear)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: model.hover)
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
    }

    private func petalShape(_ i: Int, _ n: Int, grow: CGFloat) -> Petal {
        let step = 360.0 / Double(n)
        return Petal(center: -90.0 + step * Double(i), step: step, n: n,
                     inner: WheelGeometry.inner(n) + cr + 2, outer: WheelGeometry.outer(n) - cr - 2,
                     d: gapPts / 2 + cr, grow: grow)
    }

    private func petal(_ i: Int, _ item: WheelItem) -> some View {
        let n = max(model.items.count, 1)
        let step = 360.0 / Double(n)
        let center = -90.0 + step * Double(i)
        let active = model.hover == i && (item.enabled || item.isGroup)
        let mid = (WheelGeometry.inner(n) + WheelGeometry.outer(n)) / 2
        let rad = center * .pi / 180
        let enabled = item.enabled
        let body = petalShape(i, n, grow: cr)
        let grad = LinearGradient(colors: active ? [orangeTop, orangeBottom]
                                                  : [Color.white.opacity(enabled ? 0.17 : 0.07), Color.white.opacity(enabled ? 0.07 : 0.03)],
                                  startPoint: .top, endPoint: .bottom)
        return ZStack {
            body.fill(grad)
            body.stroke(active ? accentRim : Color.white.opacity(enabled ? 0.22 : 0.09), lineWidth: active ? 1.6 : 1)
            VStack(spacing: 5) {
                if let s = item.symbol {
                    Image(systemName: s).font(.system(size: n > 7 ? 11 : 13, weight: .semibold))
                }
                Text(item.symbol == nil ? item.label : item.label.replacingOccurrences(of: " ", with: "\n"))
                    .font(.system(size: item.symbol == nil ? 11 : 7.5, weight: .bold)).tracking(item.symbol == nil ? 0.3 : 0.5)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white.opacity(enabled ? 1 : 0.32))
            .frame(width: 60)
            .offset(x: cos(rad) * (mid + 1), y: sin(rad) * (mid + 1))
        }
        .shadow(color: active ? orangeBottom.opacity(0.5) : .clear, radius: 10)
        .scaleEffect(active ? 1.02 : 1, anchor: Self.anchor(angle: center, radius: mid))
        .animation(.easeOut(duration: 0.10), value: model.hover)

    }

    /// Point d'ancrage (en fraction de la zone de la roue) situé au centre d'un pétale : l'agrandissement au survol ne le fait plus glisser.
    private static func anchor(angle deg: Double, radius: CGFloat) -> UnitPoint {
        let rad = deg * .pi / 180, size = WheelGeometry.size
        return UnitPoint(x: 0.5 + cos(rad) * radius / size, y: 0.5 + sin(rad) * radius / size)
    }

    private func childPetals(parentIndex h: Int, parent: WheelItem) -> some View {
        let n = max(model.items.count, 1)
        let parentCenter = -90.0 + 360.0 / Double(n) * Double(h)
        let centers = WheelGeometry.childCenters(parent: parentCenter, count: parent.children.count)
        let cin = WheelGeometry.childInner(n), cout = WheelGeometry.childOuter(n)
        return ZStack {
            ForEach(Array(parent.children.enumerated()), id: \.element.id) { ci, child in
                let active = model.hoverChild == ci && child.enabled
                let shape = Petal(center: centers[ci], step: WheelGeometry.childStep, n: 2, inner: cin + cr + 2, outer: cout - cr - 2,
                                  d: gapPts / 2 + cr, grow: cr)
                let rad = centers[ci] * .pi / 180
                let mid = (cin + cout) / 2
                ZStack {
                    // teinte claire comme les pétales de base : ils reposent maintenant sur le fond agrandi
                    shape.fill(LinearGradient(colors: active ? [orangeTop, orangeBottom] : [Color.white.opacity(0.22), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                    shape.stroke(active ? accentRim : Color.white.opacity(0.24), lineWidth: active ? 1.6 : 1)
                    VStack(spacing: 4) {
                        if let s = child.symbol { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
                        Text(child.label.replacingOccurrences(of: " ", with: "\n")).font(.system(size: 7.5, weight: .bold)).tracking(0.5).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.white.opacity(child.enabled ? 1 : 0.35))
                    .frame(width: 60)
                    .offset(x: cos(rad) * mid, y: sin(rad) * mid)
                }
                .shadow(color: active ? orangeBottom.opacity(0.5) : Color.black.opacity(0.35), radius: active ? 10 : 8)
                .scaleEffect(active ? 1.02 : 1, anchor: Self.anchor(angle: centers[ci], radius: mid))
            }
        }
        .animation(.easeOut(duration: 0.10), value: model.hoverChild)
    }

    private var center: some View {
        let inn = WheelGeometry.inner(max(model.items.count, 1))
        let w = inn * 2 - 14, h = inn * 1.04
        let lines = Array(model.infoLines.prefix(3))
        return ZStack {
            Capsule().fill(Color.black.opacity(0.30))
            Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            VStack(spacing: 1.5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.system(size: i == 0 ? 10.5 : 8, weight: i == 0 ? .bold : .medium))
                        .foregroundStyle(Color.white.opacity(i == 0 ? 1 : 0.7))
                        .lineLimit(1).minimumScaleFactor(0.55)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: w, height: h)
    }
}
