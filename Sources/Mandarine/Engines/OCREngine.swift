import Foundation
import Vision
import PDFKit
import AppKit

/// Reconnaissance de texte hors ligne (Vision) pour les images et les PDF scannés.
enum OCREngine {
    /// Lignes lues dans l'image, dans l'ordre de lecture (haut → bas, puis gauche → droite). La langue est détectée automatiquement.
    static func lines(in image: CGImage) throws -> [String] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        if #available(macOS 13.0, *) { req.automaticallyDetectsLanguage = true }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let obs = (req.results ?? []).filter { $0.topCandidates(1).first != nil }
        // Vision a l'origine en bas à gauche : on trie par ligne (tolérance = demi-hauteur), puis par x.
        let sorted = obs.sorted {
            let a = $0.boundingBox, b = $1.boundingBox
            if abs(a.midY - b.midY) > min(a.height, b.height) * 0.5 { return a.midY > b.midY }
            return a.minX < b.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }

    /// Une entrée par page (une seule pour une image). `progress` reçoit (page lue, total).
    static func pages(of url: URL, progress: ((Int, Int) -> Void)? = nil) throws -> [[String]] {
        if url.pathExtension.lowercased() == "pdf" {
            let doc = try PDFEngine.open(url)
            let n = doc.pageCount
            guard n > 0 else { throw MandarineError("PDF vide.") }
            var out: [[String]] = []
            for i in 0..<n {
                try Task.checkCancellation()
                progress?(i, n)
                guard let page = doc.page(at: i), let img = PDFEngine.render(page: page, dpi: 200) else { out.append([]); continue }
                out.append(try lines(in: img))
            }
            progress?(n, n)
            return out
        }
        progress?(0, 1)
        let (img, _) = try ImageEngine.load(url)
        let r = try lines(in: img)
        progress?(1, 1)
        return [r]
    }

    static func join(_ pages: [[String]], keepLineBreaks: Bool) -> String {
        pages.map { keepLineBreaks ? $0.joined(separator: "\n") : $0.joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
