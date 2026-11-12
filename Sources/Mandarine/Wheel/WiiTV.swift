import SwiftUI
import AppKit

/// Style Wii : l'écran (menu ou outil) est montré dans un vieux téléviseur transparent (`Resources/WiiTV.png`).
/// L'image a un trou transparent à la place de l'écran ; `WiiTVScreen.png` est le masque exact de ce trou (agrandi de 3 px sous le cadre noir,
/// pour qu'il n'y ait aucun jour). Le contenu est rogné par ce masque, donc il épouse les coins arrondis du tube.
enum WiiTV {
    static let imageSize = CGSize(width: 1536, height: 1024)
    /// L'écran, en pixels de l'image (mesuré sur le canal alpha : la plus grande zone transparente du centre).
    static let hole = CGRect(x: 303, y: 111, width: 929, height: 681)
    /// Zone couverte par `WiiTVScreen.png` (le trou + 6 px de marge), en pixels de l'image.
    static let maskRect = CGRect(x: 297, y: 105, width: 941, height: 693)

    static var enabled: Bool { AppSettings.shared.wiiTV && body != nil && screenMask != nil }

    static let body: NSImage? = image("WiiTV")
    static let screenMask: NSImage? = image("WiiTVScreen")
    private static func image(_ name: String) -> NSImage? {
        let u = Bundle.main.url(forResource: name, withExtension: "png") ?? URL(fileURLWithPath: "Resources/\(name).png")
        return FileManager.default.fileExists(atPath: u.path) ? NSImage(contentsOf: u) : nil
    }

    /// Placement du téléviseur autour d'un écran de taille `screen` (en points) : le trou contient l'écran, centré (bandes noires de part et
    /// d'autre si les proportions diffèrent, comme sur un vrai tube). La fenêtre est centrée sur le trou, donc sur l'écran.
    struct Geometry: Equatable {
        let screen: CGSize
        /// Réduction uniforme (≤ 1) quand le téléviseur ne tiendrait pas dans la zone visible : tout rétrécit ensemble, rien n'est retiré.
        var fit: CGFloat = 1
        /// Points par pixel de l'image.
        var g: CGFloat { max(screen.width / WiiTV.hole.width, screen.height / WiiTV.hole.height) }
        /// La fenêtre : le téléviseur entier, réduit de `fit`.
        var stage: CGSize { CGSize(width: layoutStage.width * fit, height: layoutStage.height * fit) }
        /// Le trou à l'écran (réduit de `fit`).
        var holeOnScreen: CGSize { CGSize(width: holeSize.width * fit, height: holeSize.height * fit) }
        /// Fenêtre à taille réelle (avant réduction) : symétrique autour du centre du trou, assez grande pour tout le téléviseur.
        var layoutStage: CGSize {
            let c = CGPoint(x: WiiTV.hole.midX, y: WiiTV.hole.midY), s = WiiTV.imageSize
            return CGSize(width: 2 * max(c.x, s.width - c.x) * g, height: 2 * max(c.y, s.height - c.y) * g)
        }
        /// Le trou (l'écran vu à travers la vitre), centré dans la fenêtre.
        var holeSize: CGSize { CGSize(width: WiiTV.hole.width * g, height: WiiTV.hole.height * g) }
        /// Centre de l'image du téléviseur dans la fenêtre.
        var imageCenter: CGPoint {
            CGPoint(x: layoutStage.width / 2 + (WiiTV.imageSize.width / 2 - WiiTV.hole.midX) * g, y: layoutStage.height / 2 + (WiiTV.imageSize.height / 2 - WiiTV.hole.midY) * g)
        }
        var maskCenter: CGPoint { CGPoint(x: layoutStage.width / 2 + (WiiTV.maskRect.midX - WiiTV.hole.midX) * g, y: layoutStage.height / 2 + (WiiTV.maskRect.midY - WiiTV.hole.midY) * g) }
        var maskSize: CGSize { CGSize(width: WiiTV.maskRect.width * g, height: WiiTV.maskRect.height * g) }
    }
}

/// Le téléviseur autour d'un contenu : fond noir du tube, contenu rogné par le masque de l'écran, puis l'image du téléviseur par-dessus.
/// Le contenu garde son propre centre : il doit être centré dans `geo.stage`.
struct WiiTVSet<Content: View>: View {
    let geo: WiiTV.Geometry
    let content: Content
    init(_ geo: WiiTV.Geometry, @ViewBuilder content: () -> Content) { self.geo = geo; self.content = content() }

    private var mask: some View {
        ZStack {
            if let m = WiiTV.screenMask {
                Image(nsImage: m).resizable().interpolation(.high).frame(width: geo.maskSize.width, height: geo.maskSize.height).position(geo.maskCenter)
            }
        }.frame(width: geo.layoutStage.width, height: geo.layoutStage.height)
    }

    var body: some View {
        let L = geo.layoutStage
        ZStack {
            Color.black.frame(width: L.width, height: L.height).mask(mask).allowsHitTesting(false)
            content.frame(width: L.width, height: L.height).mask(mask)
            if let b = WiiTV.body {
                Image(nsImage: b).resizable().interpolation(.high)
                    .frame(width: WiiTV.imageSize.width * geo.g, height: WiiTV.imageSize.height * geo.g)
                    .position(geo.imageCenter).allowsHitTesting(false)
            }
        }
        .frame(width: L.width, height: L.height)
        .scaleEffect(geo.fit)
        .frame(width: geo.stage.width, height: geo.stage.height)
    }
}
