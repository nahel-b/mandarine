import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum ScanFilter: String, CaseIterable, Identifiable {
    case original = "Original", color = "Color", gray = "Grayscale", blackWhite = "B&W"
    var id: String { rawValue }
}

/// Scan de document : détecte la feuille sur une photo, la redresse (correction de perspective) et nettoie l'éclairage.
enum DocumentScanner {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Quatre coins (haut-gauche, haut-droit, bas-droit, bas-gauche), normalisés 0…1, origine en HAUT à gauche.
    static func detectCorners(_ image: CGImage) -> [CGPoint] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        func quad(_ o: VNRectangleObservation) -> [CGPoint] {
            [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
        }
        let seg = VNDetectDocumentSegmentationRequest()
        if (try? handler.perform([seg])) != nil, let o = seg.results?.first, o.confidence > 0.5 { return quad(o) }
        let rect = VNDetectRectanglesRequest()
        rect.minimumAspectRatio = 0.3; rect.maximumObservations = 1; rect.minimumSize = 0.25; rect.quadratureTolerance = 30
        if (try? handler.perform([rect])) != nil, let o = rect.results?.first { return quad(o) }
        return [CGPoint(x: 0.04, y: 0.04), CGPoint(x: 0.96, y: 0.04), CGPoint(x: 0.96, y: 0.96), CGPoint(x: 0.04, y: 0.96)]
    }

    /// Redresse la zone délimitée par `corners` puis applique le filtre. `maxSide` limite la taille du résultat.
    static func render(_ image: CGImage, corners: [CGPoint], filter: ScanFilter, maxSide: Int? = nil) -> CGImage? {
        guard corners.count == 4 else { return nil }
        let W = Double(image.width), H = Double(image.height)
        func ci(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * W, y: (1 - p.y) * H) }          // repère Core Image : origine en bas
        let (tl, tr, br, bl) = (ci(corners[0]), ci(corners[1]), ci(corners[2]), ci(corners[3]))
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = CIImage(cgImage: image)
        f.topLeft = tl; f.topRight = tr; f.bottomRight = br; f.bottomLeft = bl
        guard var out = f.outputImage else { return nil }
        // La correction de perspective garde la boîte englobante du quadrilatère : on remet le vrai rapport largeur / hauteur de la feuille
        let leftH = hypot(tl.x - bl.x, tl.y - bl.y), rightH = hypot(tr.x - br.x, tr.y - br.y)
        let h = max(leftH, rightH), w = h * snapToPaper(aspectRatio(corners, imageSize: CGSize(width: W, height: H)))
        out = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
                 .transformed(by: CGAffineTransform(scaleX: w / out.extent.width, y: h / out.extent.height))
        if let m = maxSide {
            let s = CGFloat(m) / max(out.extent.width, out.extent.height)
            if s < 1 { out = out.transformed(by: CGAffineTransform(scaleX: s, y: s)) }
        }
        out = apply(filter, to: out)
        return context.createCGImage(out, from: out.extent)
    }

    /// Rapport largeur / hauteur réel de la feuille d'après son image en perspective (méthode de Zhang & He pour les tableaux blancs :
    /// la longueur focale se déduit des quatre coins, le point principal étant au centre de l'image).
    static func aspectRatio(_ q: [CGPoint], imageSize: CGSize) -> Double {
        let u0 = imageSize.width / 2, v0 = imageSize.height / 2
        func v(_ p: CGPoint) -> SIMD3<Double> { SIMD3(Double(p.x * imageSize.width - u0), Double(p.y * imageSize.height - v0), 1) }
        let m1 = v(q[0]), m2 = v(q[1]), m3 = v(q[3]), m4 = v(q[2])        // haut-gauche, haut-droit, bas-gauche, bas-droit
        func edges() -> Double {
            let w = (m2 - m1).x * (m2 - m1).x + (m2 - m1).y * (m2 - m1).y, h = (m3 - m1).x * (m3 - m1).x + (m3 - m1).y * (m3 - m1).y
            return h > 0 ? (w / h).squareRoot() : 1
        }
        func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> { SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
        let d2 = dot(cross(m2, m4), m3), d3 = dot(cross(m3, m4), m2)
        guard abs(d2) > 1e-9, abs(d3) > 1e-9 else { return edges() }
        let k2 = dot(cross(m1, m4), m3) / d2, k3 = dot(cross(m1, m4), m2) / d3
        let n2 = k2 * m2 - m1, n3 = k3 * m3 - m1
        guard abs(n2.z * n3.z) > 1e-9 else { return edges() }
        let f2 = -(n2.x * n3.x + n2.y * n3.y) / (n2.z * n3.z)
        guard f2 > 1, f2.isFinite else { return edges() }
        let a = (n2.x * n2.x + n2.y * n2.y) / f2 + n2.z * n2.z, b = (n3.x * n3.x + n3.y * n3.y) / f2 + n3.z * n3.z
        let r = (a / b).squareRoot()
        return r.isFinite ? min(max(r, 0.2), 5) : edges()
    }

    /// Les feuilles sont presque toujours au format A4 ou Lettre : si l'estimation en est proche (12 %), on prend le format exact.
    static func snapToPaper(_ r: Double) -> Double {
        let formats = [1 / 2.0.squareRoot(), 8.5 / 11, 2.0.squareRoot(), 11 / 8.5]
        let best = formats.min { abs($0 / r - 1) < abs($1 / r - 1) }!
        return abs(best / r - 1) < 0.12 ? best : r
    }

    /// « Divise » l'image par sa version floue : le fond (papier) devient uniformément blanc, l'encre reste.
    private static func flatten(_ img: CIImage) -> CIImage {
        let extent = img.extent
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = img.clampedToExtent()
        blur.radius = Float(max(extent.width, extent.height) / 25)
        guard let bg = blur.outputImage?.cropped(to: extent) else { return img }
        let div = CIFilter.divideBlendMode()
        div.inputImage = bg          // CIDivideBlendMode calcule « fond ÷ source » : on inverse pour obtenir « image ÷ flou »
        div.backgroundImage = img
        return div.outputImage?.cropped(to: extent) ?? img
    }

    private static func apply(_ filter: ScanFilter, to img: CIImage) -> CIImage {
        func controls(_ i: CIImage, contrast: Float, brightness: Float = 0, saturation: Float = 1) -> CIImage {
            let c = CIFilter.colorControls(); c.inputImage = i; c.contrast = contrast; c.brightness = brightness; c.saturation = saturation
            return c.outputImage ?? i
        }
        func sharpen(_ i: CIImage) -> CIImage {
            let u = CIFilter.unsharpMask(); u.inputImage = i; u.radius = 2; u.intensity = 0.6
            return u.outputImage ?? i
        }
        func mono(_ i: CIImage) -> CIImage { controls(i, contrast: 1, saturation: 0) }
        switch filter {
        case .original: return img
        case .color: return sharpen(controls(flatten(img), contrast: 1.15, saturation: 1.1))
        case .gray: return sharpen(controls(flatten(mono(img)), contrast: 1.25))
        case .blackWhite: return controls(flatten(mono(img)), contrast: 2.6, brightness: -0.12)
        }
    }
}
