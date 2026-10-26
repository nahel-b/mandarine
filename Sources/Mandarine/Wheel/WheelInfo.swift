import Foundation
import AVFoundation
import ImageIO
import PDFKit

/// Petites lignes d'information affichées au centre de la roue pour la sélection en cours de glissement.
enum WheelInfo {
    static func items(_ n: Int) -> String { "\(n) item\(n == 1 ? "" : "s")" }

    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Immédiat (aucune lecture lourde) : sert d'affichage initial.
    static func quick(_ urls: [URL]) -> [String] {
        guard !urls.isEmpty else { return [] }
        if urls.count == 1, SnippetStore.isSnippet(urls[0]) { return snippetLines(urls[0]) }
        if !urls.allSatisfy(\.isFileURL) { return [urls.count == 1 ? "Link" : "\(urls.count) links", urls[0].host ?? ""].filter { !$0.isEmpty } }
        if urls.count > 1 {
            let total = urls.reduce(Int64(0)) { $0 + $1.fileSize }
            return ["\(urls.count) items", total.humanSize]
        }
        let u = urls[0]
        if FileKind.detect(u) == .folder { return [items(itemCount(u))] }
        return [u.fileSize.humanSize]
    }

    private static func itemCount(_ folder: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != ".DS_Store" }.count
    }

    private static func snippetLines(_ u: URL) -> [String] {
        let t = SnippetStore.text(of: u)
        let first = t.split(whereSeparator: \.isNewline).first.map { String($0.prefix(26)) + ($0.count > 26 ? "…" : "") } ?? ""
        return ["\(SnippetStore.wordCount(t)) words", "\(t.count) characters", first].filter { !$0.isEmpty }
    }

    /// Complet : durée, dimensions, pages… (peut lire un peu le fichier).
    static func detailed(_ urls: [URL]) async -> [String] {
        if urls.count == 1, YtDlp.isYouTube(urls[0]), let i = await YtDlp.info(urls[0]) {
            return [i.title, i.author, "YouTube"].filter { !$0.isEmpty }
        }
        if urls.count == 1, SnippetStore.isSnippet(urls[0]) { return snippetLines(urls[0]) }
        guard urls.count == 1, urls[0].isFileURL else {
            if urls.count > 1, urls.allSatisfy(\.isFileURL) {
                let kinds = Set(urls.map { FileKind.detect($0) })
                let total = urls.reduce(Int64(0)) { $0 + $1.fileSize }
                var lines = ["\(urls.count) items", total.humanSize]
                if kinds.count == 1, let k = kinds.first { lines.append(k.rawValue.capitalized) } else { lines.append("Mixed") }
                // plusieurs vidéos / audios : durée totale
                if kinds.count == 1, [.video, .audio].contains(kinds.first!) {
                    var sum = 0.0
                    for u in urls { sum += (try? await AVURLAsset(url: u).load(.duration).seconds) ?? 0 }
                    if sum > 0 { lines = ["\(urls.count) items", duration(sum), total.humanSize] }
                }
                return lines
            }
            return quick(urls)
        }
        let u = urls[0]
        let size = u.fileSize.humanSize
        let ext = u.pathExtension.uppercased()
        switch FileKind.detect(u) {
        case .folder:
            let (n, bytes, capped) = await Task.detached { folderStats(u) }.value
            return [items(n), (capped ? "≥ " : "") + bytes.humanSize]
        case .image:
            if let s = CGImageSourceCreateWithURL(u as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any],
               let w = p[kCGImagePropertyPixelWidth as String] as? Int, let h = p[kCGImagePropertyPixelHeight as String] as? Int {
                return [size, "\(w) × \(h)", ext]
            }
            return [size, ext]
        case .video:
            let a = AVURLAsset(url: u)
            let d = (try? await a.load(.duration).seconds) ?? 0
            var res = "", fps = ""
            if let t = try? await a.loadTracks(withMediaType: .video).first {
                if let n = try? await t.load(.naturalSize), let tr = try? await t.load(.preferredTransform) {
                    let r = n.applying(tr); res = "\(Int(abs(r.width)))×\(Int(abs(r.height)))"
                }
                if let f = try? await t.load(.nominalFrameRate), f > 0 { fps = String(format: "%g fps", (Double(f) * 100).rounded() / 100) }
            }
            if d <= 0 && res.isEmpty { return [size, ext] }
            return [d > 0 ? duration(d) : size, res.isEmpty ? ext : res, [fps, size].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }
        case .audio:
            let d = (try? await AVURLAsset(url: u).load(.duration).seconds) ?? 0
            return d > 0 ? [duration(d), size, ext] : [size, ext]
        case .pdf:
            if let doc = PDFDocument(url: u) { return ["\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")", size] }
            return [size]
        default:
            return [size, ext].filter { !$0.isEmpty }
        }
    }

    /// Nombre d'éléments et taille d'un dossier (récursif, plafonné pour rester instantané).
    private static func folderStats(_ folder: URL) -> (Int, Int64, Bool) {
        let top = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0 != ".DS_Store" }.count
        var bytes: Int64 = 0, seen = 0, capped = false
        let started = Date()
        if let en = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            while let f = en.nextObject() as? URL {
                bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                seen += 1
                if seen > 30000 || Date().timeIntervalSince(started) > 1.0 { capped = true; break }
            }
        }
        return (top, bytes, capped)
    }
}
