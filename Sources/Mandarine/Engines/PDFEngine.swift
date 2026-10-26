import Foundation
import PDFKit
import AppKit

enum PDFEngine {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: url) else { throw MandarineError("PDF illisible : \(url.lastPathComponent)") }
        if d.isLocked { throw MandarineError("Ce PDF est protégé par un mot de passe.") }
        return d
    }

    static func render(page: PDFPage, dpi: CGFloat = 300) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let rot = page.rotation % 180 != 0
        let wPt = rot ? box.height : box.width
        let hPt = rot ? box.width : box.height
        let scale = dpi / 72
        let w = Int(wPt * scale), h = Int(hPt * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        // Remet l'origine après rotation de la page
        let t = page.transform(for: .mediaBox)
        ctx.concatenate(t)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// PDF → images (un fichier par page, dans un dossier si plusieurs pages).
    static func toImages(_ url: URL, ext: String, dpi: CGFloat = 300, progress: ((Double) -> Void)? = nil) throws -> URL {
        let doc = try open(url)
        let e = Catalog.normalized(ext)
        let n = doc.pageCount
        guard n > 0 else { throw MandarineError("PDF vide.") }
        let folder: URL? = n > 1 ? OutputNaming.folder(of: url, suffix: "pages") : nil
        var last = url
        for i in 0..<n {
            guard let page = doc.page(at: i), let img = render(page: page, dpi: dpi) else { continue }
            let out: URL
            if let f = folder {
                out = f.appendingPathComponent(String(format: "%@ %0\(String(n).count)d", url.deletingPathExtension().lastPathComponent, i + 1)).appendingPathExtension(e)
            } else {
                out = OutputNaming.sibling(of: url, ext: e)
            }
            try ImageEngine.write(img, to: out, ext: e)
            last = out
            progress?(Double(i + 1) / Double(n))
        }
        return folder ?? last
    }

    static func text(of doc: PDFDocument) -> String {
        (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    static func merge(_ urls: [URL], to out: URL) throws {
        let result = PDFDocument()
        var idx = 0
        for u in urls {
            let d = try open(u)
            for i in 0..<d.pageCount {
                if let p = d.page(at: i)?.copy() as? PDFPage { result.insert(p, at: idx); idx += 1 }
            }
        }
        guard result.write(to: out) else { throw MandarineError("Impossible d'écrire le PDF fusionné.") }
    }

    static func split(_ url: URL, ranges: [ClosedRange<Int>]? = nil) throws -> URL {
        let doc = try open(url)
        let folder = OutputNaming.folder(of: url, suffix: "pages")
        let rs = ranges ?? (0..<doc.pageCount).map { $0...$0 }
        for (n, r) in rs.enumerated() {
            let part = PDFDocument()
            for (k, i) in r.enumerated() { if let p = doc.page(at: i)?.copy() as? PDFPage { part.insert(p, at: k) } }
            let name = "\(url.deletingPathExtension().lastPathComponent) \(n + 1)"
            part.write(to: folder.appendingPathComponent(name).appendingPathExtension("pdf"))
        }
        return folder
    }

    /// Compression : réencode les images en JPEG (strong = en plus, rastérisation à basse résolution).
    static func compress(_ url: URL, strong: Bool) throws -> URL {
        let doc = try open(url)
        let out = OutputNaming.sibling(of: url, suffix: " compressed")
        if strong {
            let result = PDFDocument()
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i), let img = render(page: page, dpi: 110) else { continue }
                let box = page.bounds(for: .mediaBox)
                guard let data = ImageEngine.data(img, ext: "jpg", quality: 0.55), let ns = NSImage(data: data) else { continue }
                ns.size = box.size
                if let np = PDFPage(image: ns) { result.insert(np, at: result.pageCount) }
            }
            guard result.write(to: out) else { throw MandarineError("Écriture impossible.") }
        } else {
            let opts: [PDFDocumentWriteOption: Any] = [
                PDFDocumentWriteOption(rawValue: "PDFDocumentSaveImagesAsJPEGOption"): true,
                PDFDocumentWriteOption(rawValue: "PDFDocumentOptimizeImagesForScreenOption"): true
            ]
            guard doc.write(to: out, withOptions: opts) else { throw MandarineError("Écriture impossible.") }
        }
        // Si le résultat est plus gros, on garde quand même le fichier mais on prévient l'appelant par la taille.
        return out
    }
}
