import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import VideoToolbox

/// Agrandissement d'images : IA d'Apple (VideoToolbox, macOS 26+) ou Lanczos (Core Image) en secours.
enum Upscaler {
    // MARK: IA d'Apple
    /// Facteurs que le système accepte pour l'upscale par IA (vide si indisponible).
    static var aiFactors: [Int] {
        if #available(macOS 26.0, *), VTSuperResolutionScalerConfiguration.isSupported {
            return VTSuperResolutionScalerConfiguration.supportedScaleFactors.map { $0 }.sorted()
        }
        return []
    }
    static var aiAvailable: Bool { !aiFactors.isEmpty }
    /// Taille d'entrée maximale du modèle pour une image (macOS) : 1920 × 1920 px.
    static let aiMaxInput = 1920

    static func canUseAI(_ size: CGSize, factor: Int) -> Bool {
        aiFactors.contains(factor) && Int(size.width) <= aiMaxInput && Int(size.height) <= aiMaxInput
    }

    @available(macOS 26.0, *)
    static func ai(_ image: CGImage, factor: Int) async throws -> CGImage {
        let w = image.width, h = image.height
        guard let config = VTSuperResolutionScalerConfiguration(frameWidth: w, frameHeight: h, scaleFactor: factor, inputType: .image,
                                                                usePrecomputedFlow: false, qualityPrioritization: .normal,
                                                                revision: VTSuperResolutionScalerConfiguration.defaultRevision) else {
            throw MandarineError("L'upscale par IA ne prend pas en charge cette taille d'image.")
        }
        // Le modèle peut devoir être téléchargé la première fois.
        if config.configurationModelStatus != .ready {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                config.downloadConfigurationModel { err in if let err = err { c.resume(throwing: err) } else { c.resume() } }
            }
            var waited = 0
            while config.configurationModelStatus != .ready && waited < 600 { try await Task.sleep(nanoseconds: 500_000_000); waited += 1 }
            guard config.configurationModelStatus == .ready else { throw MandarineError("Le modèle d'upscale d'Apple n'a pas pu être téléchargé.") }
        }

        let src = try makeBuffer(width: w, height: h, attributes: config.sourcePixelBufferAttributes)
        let dst = try makeBuffer(width: w * factor, height: h * factor, attributes: config.destinationPixelBufferAttributes)
        try draw(image, into: src)

        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)
        defer { processor.endSession() }
        guard let sf = VTFrameProcessorFrame(buffer: src, presentationTimeStamp: .zero),
              let df = VTFrameProcessorFrame(buffer: dst, presentationTimeStamp: .zero),
              let params = VTSuperResolutionScalerParameters(sourceFrame: sf, previousFrame: nil, previousOutputFrame: nil,
                                                             opticalFlow: nil, submissionMode: .sequential, destinationFrame: df) else {
            throw MandarineError("Préparation de l'upscale impossible.")
        }
        _ = try await processor.process(parameters: params)

        guard let result = cgImage(from: dst) else { throw MandarineError("Lecture du résultat impossible.") }
        return result
    }

    private static func makeBuffer(width: Int, height: Int, attributes: [String: Any]) throws -> CVPixelBuffer {
        var attrs = attributes
        attrs[kCVPixelBufferWidthKey as String] = width
        attrs[kCVPixelBufferHeightKey as String] = height
        if attrs[kCVPixelBufferPixelFormatTypeKey as String] == nil { attrs[kCVPixelBufferPixelFormatTypeKey as String] = kCVPixelFormatType_32BGRA }
        var format = kCVPixelFormatType_32BGRA
        if let f = attrs[kCVPixelBufferPixelFormatTypeKey as String] as? OSType { format = f }
        else if let list = attrs[kCVPixelBufferPixelFormatTypeKey as String] as? [OSType], let f = list.first { format = f }
        attrs[kCVPixelBufferPixelFormatTypeKey as String] = format
        var buf: CVPixelBuffer?
        let r = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &buf)
        guard r == kCVReturnSuccess, let b = buf else { throw MandarineError("Mémoire insuffisante pour l'upscale (\(width)×\(height)).") }
        return b
    }

    /// Le modèle d'Apple travaille en RGBA 16 bits flottants (« RGhA ») ; BGRA 8 bits est géré aussi au cas où.
    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let ctx: CGContext?
        switch format {
        case kCVPixelFormatType_64RGBAHalf:
            ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                            bitsPerComponent: 16, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.extendedSRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        case kCVPixelFormatType_32BGRA:
            ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        default: ctx = nil
        }
        guard let c = ctx else { throw MandarineError("Format de pixels non pris en charge par l'upscale (\(format)).") }
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    /// Convertit le tampon de sortie en image 8 bits sRGB.
    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    // MARK: Core Image (Lanczos)
    static func lanczos(_ image: CGImage, factor: Double) -> CGImage {
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = CIImage(cgImage: image)
        f.scale = Float(factor)
        f.aspectRatio = 1
        let ctx = CIContext()
        guard let out = f.outputImage, let cg = ctx.createCGImage(out, from: out.extent) else { return image }
        return cg
    }

    /// Agrandit : IA si possible (facteur supporté, image assez petite), sinon Lanczos. Retourne aussi la méthode utilisée.
    static func upscale(_ image: CGImage, factor: Int, preferAI: Bool) async throws -> (CGImage, usedAI: Bool) {
        let size = CGSize(width: image.width, height: image.height)
        guard max(size.width, size.height) * CGFloat(factor) <= 16384 else { throw MandarineError("Le résultat dépasserait 16 384 px.") }
        if preferAI, #available(macOS 26.0, *), canUseAI(size, factor: factor) {
            if let r = try? await ai(image, factor: factor) { return (r, true) }
        }
        return (lanczos(image, factor: Double(factor)), false)
    }
}
