import AppKit
import PDFKit

/// Un aperçu de fichier pour la pile du centre du menu « bulles » : une image (photo, image de vidéo, page de PDF) ou, à défaut, l'extension.
struct WheelPreviewItem: Identifiable {
    let id = UUID()
    let image: NSImage?
    let ext: String          // « PDF », « HEIC »… (« DIR » pour un dossier)
    var isVideo = false
}

enum WheelPreview {
    static func make(_ urls: [URL]) async -> [WheelPreviewItem] {
        var out: [WheelPreviewItem] = []
        for u in urls.prefix(4) {
            if Task.isCancelled { break }
            out.append(await item(for: u))
        }
        return out
    }

    static func item(for url: URL) async -> WheelPreviewItem {
        guard url.isFileURL else { return WheelPreviewItem(image: nil, ext: "URL") }
        func ns(_ cg: CGImage) -> NSImage { NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        let kind = FileKind.detect(url)
        let ext = kind == .folder ? "DIR" : (url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased())
        switch kind {
        case .image:
            if let (cg, _) = try? ImageEngine.load(url, maxSide: 360) { return WheelPreviewItem(image: ns(cg), ext: ext) }
        case .video:
            if let cg = await VideoFrames.native(url, at: 1) { return WheelPreviewItem(image: ns(ImageEngine.resize(cg, maxSide: 360)), ext: ext, isVideo: true) }
            if let cg = await VideoFrames.native(url, at: 0) { return WheelPreviewItem(image: ns(ImageEngine.resize(cg, maxSide: 360)), ext: ext, isVideo: true) }
        case .pdf:
            if let doc = PDFDocument(url: url), let page = doc.page(at: 0) { return WheelPreviewItem(image: page.thumbnail(of: CGSize(width: 360, height: 470), for: .mediaBox), ext: ext) }
        case .snippet:
            return WheelPreviewItem(image: nil, ext: "TXT")
        default: break
        }
        return WheelPreviewItem(image: nil, ext: ext)
    }
}
