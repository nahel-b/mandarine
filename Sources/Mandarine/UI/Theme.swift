import SwiftUI
import AppKit

enum Theme {
    static let orange = Color(red: 0xF3 / 255, green: 0x5B / 255, blue: 0x28 / 255)
    static let nsOrange = NSColor(red: 0xF3 / 255, green: 0x5B / 255, blue: 0x28 / 255, alpha: 1)
    static let text = Color(red: 40 / 255, green: 43 / 255, blue: 41 / 255)
    static let muted = Color(red: 0x82 / 255, green: 0x87 / 255, blue: 0x82 / 255)
    static let line = Color(red: 0xE9 / 255, green: 0xEC / 255, blue: 0xE8 / 255)
    static let pageBG = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF4 / 255)
    static let pill = Color.black.opacity(0.07)
    static let pillSelected = Color.black.opacity(0.16)
    static let previewBG = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x15 / 255)
    static let cornerRadius: CGFloat = 26

    /// Icône de la barre de menus : `MenuBarIcon.svg|png|pdf` (dans Resources ou ~/Library/Application Support/Mandarine/) si présent,
    /// sinon un agrume dessiné en code. Le fichier peut être « noir sur fond blanc » OU « noir sur transparent ».
    static func statusImage() -> NSImage { statusImages().first?.1 ?? drawnStatusImage() }

    /// Toutes les icônes candidates (`MenuBarIcon.png`, `MenuBarIcon2.png`…) triées par nom : on peut en afficher plusieurs en même temps pour comparer.
    static func statusImages() -> [(String, NSImage)] {
        var found: [(String, NSImage)] = []
        var seen = Set<String>()
        for dir in [Bundle.main.resourceURL, FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Mandarine")].compactMap({ $0 }) {
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("MenuBarIcon") && ["svg", "png", "pdf"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for u in files where !seen.contains(u.deletingPathExtension().lastPathComponent) {
                if let img = templateImage(from: u) { seen.insert(u.deletingPathExtension().lastPathComponent); found.append((u.deletingPathExtension().lastPathComponent, img)) }
            }
        }
        return found
    }

    private static func legacyStatusImage() -> NSImage {
        for dir in [Bundle.main.resourceURL, FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Mandarine")].compactMap({ $0 }) {
            for n in ["MenuBarIcon.svg", "MenuBarIcon.png", "MenuBarIcon.pdf"] {
                let u = dir.appendingPathComponent(n)
                if FileManager.default.fileExists(atPath: u.path), let img = templateImage(from: u) { return img }
            }
        }
        return drawnStatusImage()
    }

    /// Convertit un dessin en « template » : forme noire + transparence. Le système la teinte (clair / sombre) et l'éclaircit au clic.
    /// - Si le fichier a de la transparence, on garde son canal alpha.
    /// - S'il est opaque (noir sur blanc), le blanc devient transparent et le noir opaque (alpha = 1 − luminance).
    static func templateImage(from url: URL, points: CGFloat = 18) -> NSImage? {
        guard let src = NSImage(contentsOf: url) else { return nil }
        let px = Int(points * 4)                                     // rendu à 4× pour rester net sur les écrans Retina
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ratio = src.size.width / max(src.size.height, 1)
        let w = ratio >= 1 ? CGFloat(px) : CGFloat(px) * ratio, h = ratio >= 1 ? CGFloat(px) / ratio : CGFloat(px)   // ajusté sans déformer
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
        src.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: px * px * 4)
        var hasTransparency = false
        for i in 0..<(px * px) where p[i * 4 + 3] < 250 { hasTransparency = true; break }
        func lum(_ i: Int) -> Double { (0.2126 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.0722 * Double(p[i * 4 + 2])) / 255 }
        // Fond d'une image opaque = luminance moyenne des 4 coins (blanc, gris, noir… peu importe).
        let bgLum = [0, px - 1, (px - 1) * px, px * px - 1].map(lum).reduce(0, +) / 4
        let span = max(bgLum, 1 - bgLum, 0.001)
        for i in 0..<(px * px) {
            var alpha = Double(p[i * 4 + 3]) / 255
            if !hasTransparency {                                         // opaque : plus un pixel s'écarte du fond, plus il est opaque
                alpha = min(1, abs(lum(i) - bgLum) / span)
                if alpha < 0.04 { alpha = 0 }                             // supprime le bruit de compression proche du fond
            }
            p[i * 4] = 0; p[i * 4 + 1] = 0; p[i * 4 + 2] = 0; p[i * 4 + 3] = UInt8(max(0, min(1, alpha)) * 255)   // noir, alpha prémultiplié
        }
        guard let cg = ctx.makeImage() else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: points, height: points))
        img.isTemplate = true
        return img
    }

    /// Icône dessinée en code (secours).
    static func drawnStatusImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            outer.lineWidth = 1.4
            outer.stroke()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                let p = NSBezierPath()
                p.move(to: NSPoint(x: c.x + cos(a) * 2, y: c.y + sin(a) * 2))
                p.line(to: NSPoint(x: c.x + cos(a) * 6.2, y: c.y + sin(a) * 6.2))
                p.lineWidth = 1.3
                p.lineCapStyle = .round
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Bouton gris clair à coins arrondis, comme dans les fenêtres d'outils.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(prominent ? Theme.orange : Color.black.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .opacity(enabled ? 1 : 0.4)
    }
}

/// Segmented control « pill » (Balanced | Strong).
struct PillPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Text(o.1)
                    .font(.system(size: 13))
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(selection == o.0 ? Color.black.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = o.0 }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.06)))
    }
}

extension View {
    func sectionLabel() -> some View {
        self.font(.system(size: 11)).foregroundStyle(Theme.muted)
    }
}
