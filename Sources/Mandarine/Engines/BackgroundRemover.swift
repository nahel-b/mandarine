import Foundation
import Vision
import CoreImage

/// Suppression de l'arrière-plan avec l'API Vision d'Apple (VNGenerateForegroundInstanceMaskRequest), 100 % locale.
/// Disponible à partir de macOS 14 ; sur macOS 13 le segment reste grisé.
enum BackgroundRemover {
    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Détoure le sujet : image RGBA, fond transparent.
    static func cutout(_ cg: CGImage) throws -> CGImage {
        guard #available(macOS 14.0, *) else { throw MandarineError("Remove Background nécessite macOS 14 ou plus récent.") }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {
            throw MandarineError("Aucun sujet détecté.")
        }
        let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { throw MandarineError("Rendu impossible.") }
        return out
    }

    static func run(_ url: URL) throws -> URL {
        let (cg, _) = try ImageEngine.load(url)
        let out = try cutout(cg)
        let dest = OutputNaming.sibling(of: url, suffix: " no background", ext: "png")   // PNG : garde la transparence
        try ImageEngine.write(out, to: dest, ext: "png")
        return dest
    }
}
