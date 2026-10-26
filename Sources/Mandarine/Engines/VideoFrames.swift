import Foundation
import AVFoundation

enum VideoFrames {
    /// Image exacte à l'instant `t`, pleine résolution, orientation appliquée. nil si AVFoundation ne sait pas lire la vidéo.
    static func native(_ url: URL, at t: Double) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = .zero                                  // taille d'origine
        return try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }
}
