import Foundation
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum BGFill: Hashable { case transparent, color, blur }

/// Réglages de détourage. Les largeurs sont exprimées « pour une image de 1000 px de grand côté » et mises à l'échelle au rendu,
/// pour que l'aperçu et l'export donnent le même résultat quelle que soit la résolution.
struct BGOptions: Equatable {
    var fill: BGFill = .transparent
    var color = NSColor.white
    var blur: Double = 18
    var soften: Double = 0          // adoucissement des bords (flou du masque)
    var shift: Double = 0           // < 0 : réduit le sujet, > 0 : l'agrandit
    var outline = false
    var outlineWidth: Double = 8
    var outlineColor = NSColor.white
    var cropToSubject = false
    var instances: Set<Int>? = nil  // nil = tous les sujets
}

/// Détourage Vision + mise en forme Core Image. À partir de macOS 14.
@available(macOS 14.0, *)
final class BGSession {
    private let cg: CGImage
    private let handler: VNImageRequestHandler
    private let observation: VNInstanceMaskObservation
    private let ctx = CIContext()
    let instanceIDs: [Int]

    init(_ cg: CGImage) throws {
        self.cg = cg
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw MandarineError("Aucun sujet détecté.") }
        self.handler = handler
        self.observation = obs
        self.instanceIDs = obs.allInstances.sorted()
    }

    func render(_ o: BGOptions) throws -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let k = CGFloat(max(cg.width, cg.height)) / 1000
        let ids = o.instances.map { IndexSet($0) } ?? observation.allInstances
        let buffer = try observation.generateScaledMaskForImage(forInstances: ids.isEmpty ? observation.allInstances : ids, from: handler)
        var mask = CIImage(cvPixelBuffer: buffer)

        // ajustement des bords : réduire / agrandir, puis adoucir
        if o.shift != 0 {
            let r = abs(o.shift) * Double(k)
            let f: CIFilter = o.shift < 0 ? CIFilter.morphologyMinimum() : CIFilter.morphologyMaximum()
            f.setValue(mask, forKey: kCIInputImageKey); f.setValue(r, forKey: kCIInputRadiusKey)
            mask = (f.outputImage ?? mask).cropped(to: extent)
        }
        if o.soften > 0 {
            let f = CIFilter.gaussianBlur()
            f.inputImage = mask.clampedToExtent(); f.radius = Float(o.soften * Double(k))
            mask = (f.outputImage ?? mask).cropped(to: extent)
        }

        let original = CIImage(cgImage: cg)
        func alpha(_ m: CIImage) -> CIImage { let f = CIFilter.maskToAlpha(); f.inputImage = m; return f.outputImage ?? m }
        func cut(_ img: CIImage, _ m: CIImage) -> CIImage {
            let f = CIFilter.sourceInCompositing(); f.inputImage = img; f.backgroundImage = alpha(m); return f.outputImage ?? img
        }
        var result = cut(original, mask)

        if o.outline && o.outlineWidth > 0 {
            let grow = CIFilter.morphologyMaximum()
            grow.inputImage = mask; grow.radius = Float(o.outlineWidth * Double(k))
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = (grow.outputImage ?? mask).clampedToExtent(); blur.radius = Float(max(0.6, 0.8 * Double(k)))
            let wide = (blur.outputImage ?? mask).cropped(to: extent)
            let color = CIImage(color: CIColor(color: o.outlineColor) ?? .white).cropped(to: extent)
            result = result.composited(over: cut(color, wide))
        }

        switch o.fill {
        case .transparent: break
        case .color:
            result = result.composited(over: CIImage(color: CIColor(color: o.color) ?? .white).cropped(to: extent))
        case .blur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = original.clampedToExtent(); f.radius = Float(o.blur * Double(k))
            result = result.composited(over: (f.outputImage ?? original).cropped(to: extent))
        }

        var area = extent
        if o.cropToSubject, let box = subjectBounds(mask, extent: extent) {
            let margin = (o.outline ? o.outlineWidth * Double(k) : 0) + o.soften * Double(k) + 4 * Double(k)
            area = box.insetBy(dx: -margin, dy: -margin).intersection(extent)
        }
        guard let out = ctx.createCGImage(result, from: area) else { throw MandarineError("Rendu impossible.") }
        return out
    }

    /// Boîte englobante du sujet (repère CIImage), calculée sur une version réduite du masque.
    private func subjectBounds(_ mask: CIImage, extent: CGRect) -> CGRect? {
        let s = min(1, 256 / max(extent.width, extent.height))
        let small = mask.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let w = Int(extent.width * s), h = Int(extent.height * s)
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h)
        ctx.render(small, toBitmap: &pixels, rowBytes: w, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .R8, colorSpace: nil)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where pixels[y * w + x] > 40 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, maxY >= minY else { return nil }
        // bitmap : ligne 0 = haut ; CIImage : origine en bas
        return CGRect(x: CGFloat(minX) / s, y: CGFloat(h - 1 - maxY) / s, width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s)
    }
}
