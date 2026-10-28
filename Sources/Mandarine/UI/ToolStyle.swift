import SwiftUI

/// Aspect des fenêtres d'outils (le contenu reste clair dans tous les styles ; seul le cadre change).
enum ToolStyle: String, CaseIterable, Identifiable {
    case capsule, classic, tangerine, graphite, minimal, wii
    case rail, islands, folder, brutal, retro
    case sticky, notepad, stamp, bubble, polaroid, ticket
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Les styles proposés dans les Réglages (les autres sont gardés dans le code mais cachés).
    static let available: [ToolStyle] = [.capsule, .classic, .islands]
    var cornerRadius: CGFloat {
        switch self { case .classic, .tangerine: return Theme.cornerRadius; case .graphite: return 18; case .minimal: return 14; case .wii: return 34; default: return 0 }
    }
    /// Style effectif : variable d'environnement (tests) sinon réglage.
    static var current: ToolStyle {
        if let e = ProcessInfo.processInfo.environment["MANDARINE_TOOLSTYLE"], let s = ToolStyle(rawValue: e) { return s }
        return AppSettings.shared.toolStyle
    }
}

private struct ToolStyleKey: EnvironmentKey { static let defaultValue = ToolStyle.classic }
extension EnvironmentValues {
    var toolStyle: ToolStyle { get { self[ToolStyleKey.self] } set { self[ToolStyleKey.self] = newValue } }
}

enum ToolPalette {
    static let wiiBlue = Color(red: 0.31, green: 0.62, blue: 0.86)
    static let wiiBody = Color(red: 0.94, green: 0.96, blue: 0.985)
    static let graphite = Color(white: 0.15)
    static let tangerineLight = Color(red: 1.0, green: 0.56, blue: 0.27)
}

/// Pliage de dossier : un onglet en haut à gauche, puis le corps.
struct FolderShape: Shape {
    var tabWidth: CGFloat = 210, tabHeight: CGFloat = 38, radius: CGFloat = 20
    func path(in r: CGRect) -> Path {
        var p = Path()
        let t = tabHeight, w = r.width, h = r.height, k = radius
        p.move(to: CGPoint(x: 0, y: h - k))
        p.addLine(to: CGPoint(x: 0, y: k))
        p.addQuadCurve(to: CGPoint(x: k, y: 0), control: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: tabWidth - 14, y: 0))
        p.addCurve(to: CGPoint(x: tabWidth + 12, y: t), control1: CGPoint(x: tabWidth + 2, y: 0), control2: CGPoint(x: tabWidth - 2, y: t))
        p.addLine(to: CGPoint(x: w - k, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: t + k), control: CGPoint(x: w, y: t))
        p.addLine(to: CGPoint(x: w, y: h - k))
        p.addQuadCurve(to: CGPoint(x: w - k, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: k, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h - k), control: CGPoint(x: 0, y: h))
        p.closeSubpath()
        return p
    }
}

/// Coin replié en bas à droite.
struct FoldedCornerShape: Shape {
    var fold: CGFloat = 28
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: r.width, y: 0)); p.addLine(to: CGPoint(x: r.width, y: r.height - fold))
        p.addLine(to: CGPoint(x: r.width - fold, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        return p
    }
}

/// Bord de timbre-poste : demi-cercles découpés tout autour (à remplir en « pair-impair » puis rogner au rectangle).
struct ScallopShape: Shape {
    var radius: CGFloat = 5, step: CGFloat = 15
    func path(in r: CGRect) -> Path {
        var p = Path(r)
        let nx = max(Int(r.width / step), 2), ny = max(Int(r.height / step), 2)
        let sx = r.width / CGFloat(nx), sy = r.height / CGFloat(ny)
        for i in 0..<nx { let x = r.minX + (CGFloat(i) + 0.5) * sx
            for y in [r.minY, r.maxY] { p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) } }
        for j in 0..<ny { let y = r.minY + (CGFloat(j) + 0.5) * sy
            for x in [r.minX, r.maxX] { p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) } }
        return p
    }
}

/// Bulle de dialogue : rectangle arrondi + queue en bas à gauche.
struct BubbleShape: Shape {
    var tail: CGFloat = 18, radius: CGFloat = 26
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: CGRect(x: 0, y: 0, width: r.width, height: r.height - tail), cornerRadius: radius, style: .continuous)
        var t = Path()
        t.move(to: CGPoint(x: 46, y: r.height - tail - 2)); t.addLine(to: CGPoint(x: 34, y: r.height)); t.addLine(to: CGPoint(x: 74, y: r.height - tail - 2)); t.closeSubpath()
        p.addPath(t)
        return p
    }
}

/// Moitié de ticket : rectangle arrondi dont deux coins (haut ou bas) sont « mordus » par un demi-cercle (à remplir en pair-impair, rogné).
struct TicketHalf: Shape {
    var top: Bool
    var radius: CGFloat = 12
    func path(in r: CGRect) -> Path {
        var p = Path(r)
        let y = top ? r.maxY : r.minY
        for x in [r.minX, r.maxX] { p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) }
        return p
    }
}
