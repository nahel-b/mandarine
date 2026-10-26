import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit

enum ImageEngine {
    static func utType(for ext: String) -> String? {
        switch ext {
        case "png": return "public.png"
        case "jpg", "jpeg": return "public.jpeg"
        case "heic": return "public.heic"
        case "tiff", "tif": return "public.tiff"
        case "avif": return "public.avif"
        case "bmp": return "com.microsoft.bmp"
        case "gif": return "com.compuserve.gif"
        default: return nil
        }
    }

    static func canWrite(_ ext: String) -> Bool {
        if ext == "webp" { return FFmpeg.locate("cwebp") != nil || FFmpeg.hasEncoder("libwebp") }
        if ext == "pdf" { return true }
        guard let t = utType(for: ext) else { return false }
        return (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(t) ?? false
    }

    /// Charge l'image avec l'orientation EXIF appliquée. `maxSide` limite la taille (aperçus).
    static func load(_ url: URL, maxSide: Int? = nil) throws -> (image: CGImage, properties: [String: Any]) {
        if url.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw MandarineError("Impossible de lire le SVG.")
            }
            return (cg, [:])
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw MandarineError("Image illisible : \(url.lastPathComponent)") }
        let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]
        let w = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let limit = maxSide ?? max(w, h, 1)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw MandarineError("Impossible de décoder \(url.lastPathComponent).")
        }
        return (cg, props)
    }

    static func flatten(_ image: CGImage, on color: CGColor = CGColor(gray: 1, alpha: 1)) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo { case .none, .noneSkipFirst, .noneSkipLast: return false; default: return true }
    }

    /// Écrit une image dans le format demandé.
    static func write(_ image: CGImage, properties: [String: Any] = [:], to url: URL, ext: String, quality: Double = 0.9) throws {
        let e = Catalog.normalized(ext)
        if e == "pdf" { try writePDF(images: [(image, properties)], to: url); return }
        if e == "webp" { try writeWebP(image, to: url, quality: quality); return }
        guard let type = utType(for: e) else { throw MandarineError("Format d'image non pris en charge : \(e)") }
        var img = image
        if (e == "jpg" || e == "bmp") && hasAlpha(img) { img = flatten(img) }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw MandarineError("Ce Mac ne peut pas écrire le format \(e.uppercased()).")
        }
        var out: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        // Conserver les métadonnées (sans l'orientation, déjà appliquée aux pixels).
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
            if var d = properties[key as String] as? [String: Any] {
                d.removeValue(forKey: kCGImagePropertyTIFFOrientation as String)
                out[key] = d
            }
        }
        out[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(dest, img, out as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw MandarineError("Échec de l'écriture de \(url.lastPathComponent).") }
    }

    private static func writeWebP(_ image: CGImage, to url: URL, quality: Double) throws {
        let tmp = OutputNaming.tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(image, to: tmp, ext: "png")
        if let cwebp = FFmpeg.locate("cwebp") {
            try Shell.run(cwebp.path, ["-quiet", "-q", String(Int(quality * 100)), tmp.path, "-o", url.path])
            return
        }
        guard FFmpeg.hasEncoder("libwebp") else { throw MandarineError("Le format WebP nécessite cwebp ou un ffmpeg avec libwebp.") }
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        Task.detached {
            do { try await FFmpeg.run(["-i", tmp.path, "-c:v", "libwebp", "-quality", String(Int(quality * 100)), url.path]) }
            catch { failure = error }
            sem.signal()
        }
        sem.wait()
        if let f = failure { throw f }
    }

    static func writePDF(images: [(CGImage, [String: Any])], to url: URL) throws {
        let pdf = PDFDocument()
        for (i, (cg, props)) in images.enumerated() {
            var dpi = 72.0
            if let d = props[kCGImagePropertyDPIWidth as String] as? Double, d > 1 { dpi = d }
            let size = NSSize(width: Double(cg.width) * 72 / dpi, height: Double(cg.height) * 72 / dpi)
            let ns = NSImage(cgImage: cg, size: size)
            guard let page = PDFPage(image: ns) else { throw MandarineError("Impossible de créer la page PDF.") }
            pdf.insert(page, at: i)
        }
        guard pdf.write(to: url) else { throw MandarineError("Impossible d'écrire le PDF.") }
    }

    /// SVG → PDF vectoriel.
    static func svgToPDF(_ url: URL, to out: URL) throws {
        guard let img = NSImage(contentsOf: url) else { throw MandarineError("SVG illisible.") }
        var box = CGRect(origin: .zero, size: img.size)
        guard let ctx = CGContext(out as CFURL, mediaBox: &box, nil) else { throw MandarineError("PDF impossible.") }
        ctx.beginPDFPage(nil)
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        img.draw(in: box)
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
    }

    static func convert(_ url: URL, to ext: String) throws -> URL {
        let e = Catalog.normalized(ext)
        let out = OutputNaming.sibling(of: url, ext: e == "jpg" ? "jpg" : e)
        if url.pathExtension.lowercased() == "svg" && e == "pdf" { try svgToPDF(url, to: out); return out }
        let (img, props) = try load(url)
        try write(img, properties: props, to: out, ext: e)
        return out
    }

    static func resize(_ image: CGImage, maxSide: Int) -> CGImage {
        let m = max(image.width, image.height)
        guard m > maxSide else { return image }
        let s = Double(maxSide) / Double(m)
        return resize(image, width: Int(Double(image.width) * s), height: Int(Double(image.height) * s))
    }

    static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard let ctx = CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height)))
        return ctx.makeImage() ?? image
    }

    static func data(_ image: CGImage, ext: String, quality: Double) -> Data? {
        guard let type = utType(for: Catalog.normalized(ext)) else { return nil }
        let md = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(md, type as CFString, 1, nil) else { return nil }
        var img = image
        if Catalog.normalized(ext) == "jpg" && hasAlpha(img) { img = flatten(img) }
        CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(d) ? md as Data : nil
    }
}
