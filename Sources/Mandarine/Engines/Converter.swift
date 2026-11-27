import Foundation
import AppKit

/// Point d'entrée unique des conversions (roue « Shift »).
enum Converter {
    static var hasLibreOffice: Bool { libreOffice != nil }
    static var libreOffice: URL? {
        ["/Applications/LibreOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func supports(kind: FileKind, from: String, to: String) -> Bool {
        let src = Catalog.normalized(from)
        switch kind {
        case .image:
            if src == "svg" { return to == "pdf" || to == "png" }
            return ImageEngine.canWrite(to)
        case .video, .audio:
            return FFmpeg.isAvailable
        case .pdf:
            if to == "pages" { return AppleApps.App.pages.isInstalled }
            return ["jpg", "png", "txt", "md", "docx", "epub", "pptx", "xlsx"].contains(to)
        case .document:
            if to == "pages" || src == "pages" { return AppleApps.App.pages.isInstalled }     // .pages : via l'app Pages
            return ["pdf", "txt", "md", "html", "docx", "epub", "png", "jpg"].contains(to)
        case .slides:
            return AppleApps.App.keynote.isInstalled || hasLibreOffice
        case .spreadsheet:
            if src == "xls" || src == "numbers" { return AppleApps.App.numbers.isInstalled }
            return ["ods", "csv", "tsv", "xlsx", "pdf"].contains(to)
        case .epub:
            if to == "pages" { return AppleApps.App.pages.isInstalled }
            return ["pdf", "docx", "txt", "md", "html"].contains(to)
        case .subtitle, .archive:
            return true
        case .snippet:
            return SnippetEngine.supports(to)
        case .folder, .other:
            return false
        }
    }

    /// Convertit un ou plusieurs fichiers. Retourne les fichiers produits.
    static func run(urls: [URL], to ext: String, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let e = Catalog.normalized(ext)
        guard let first = urls.first, let kind = FileKind.common(of: urls) else { throw MandarineError(L("Sélection mixte non prise en charge.")) }

        if urls.count > 1 {
            guard kind == .image, e == "pdf" else { throw MandarineError(L("Cette conversion ne s'applique qu'à un seul fichier.")) }
            let out = OutputNaming.sibling(of: first, suffix: " combined", ext: "pdf")
            var imgs: [(CGImage, [String: Any])] = []
            for u in urls { let (i, p) = try ImageEngine.load(u); imgs.append((i, p)) }
            try ImageEngine.writePDF(images: imgs, to: out)
            return [out]
        }

        switch kind {
        case .image:
            return try await Task.detached { [try ImageEngine.convert(first, to: e)] }.value
        case .video: return [try await MediaEngine.convertVideo(first, to: e, progress: progress)]
        case .audio: return [try await MediaEngine.convertAudio(first, to: e, progress: progress)]
        case .pdf: return [try await Task.detached { try convertPDF(first, to: e) }.value]
        case .document, .epub: return [try await Task.detached { try convertDocument(first, to: e) }.value]
        case .slides: return [try await Task.detached { try convertSlides(first, to: e) }.value]
        case .spreadsheet: return [try await Task.detached { try convertSheet(first, to: e) }.value]
        case .subtitle: return [try SubtitleEngine.convert(first, to: e)]
        case .archive: return [try await Task.detached { try ArchiveEngine.convert(first, to: e) }.value]
        case .snippet: return [try await SnippetEngine.convert(first, to: e)]
        case .folder, .other: throw MandarineError(L("Type de fichier non pris en charge."))
        }
    }

    private static func convertPDF(_ url: URL, to e: String) throws -> URL {
        switch e {
        case "jpg", "png": return try PDFEngine.toImages(url, ext: e)
        case "txt":
            let out = OutputNaming.sibling(of: url, ext: "txt")
            try PDFEngine.text(of: try PDFEngine.open(url)).write(to: out, atomically: true, encoding: .utf8)
            return out
        case "md":
            let out = OutputNaming.sibling(of: url, ext: "md")
            try PDFEngine.text(of: try PDFEngine.open(url)).write(to: out, atomically: true, encoding: .utf8)
            return out
        case "docx", "epub":
            let text = NSAttributedString(string: PDFEngine.text(of: try PDFEngine.open(url)),
                                          attributes: [.font: NSFont.systemFont(ofSize: 11)])
            let out = OutputNaming.sibling(of: url, ext: e)
            if e == "docx" { try DocumentEngine.data(text, as: .officeOpenXML).write(to: out) }
            else { try EpubEngine.write(text, title: url.deletingPathExtension().lastPathComponent, to: out) }
            return out
        case "pptx":
            let out = OutputNaming.sibling(of: url, ext: "pptx")
            try PPTXWriter.fromPDF(url, to: out)
            return out
        case "xlsx":
            let out = OutputNaming.sibling(of: url, ext: "xlsx")
            try SheetEngine.writeXLSX(PDFEngine.table(try PDFEngine.open(url)), to: out)
            return out
        case "pages":
            let tmp = OutputNaming.tempURL(ext: "docx")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let text = NSAttributedString(string: PDFEngine.text(of: try PDFEngine.open(url)), attributes: [.font: NSFont.systemFont(ofSize: 11)])
            try DocumentEngine.data(text, as: .officeOpenXML).write(to: tmp)
            let out = OutputNaming.sibling(of: url, ext: "pages")
            try AppleApps.pagesImport(tmp, to: out)
            return out
        default: throw MandarineError(L("PDF vers .\(e) non pris en charge."))
        }
    }

    /// Documents : .pages passe par l'app Pages ; la sortie .pages aussi (via un DOCX intermédiaire).
    static func convertDocument(_ url: URL, to e: String) throws -> URL {
        let src = url.pathExtension.lowercased()
        let fm = FileManager.default
        if src == "pages" {
            let tmp = OutputNaming.tempURL(ext: "docx")
            defer { try? fm.removeItem(at: tmp) }
            switch e {
            case "docx":
                let out = OutputNaming.sibling(of: url, ext: "docx"); try AppleApps.pagesExport(url, to: out, format: "Microsoft Word"); return out
            case "pdf":
                let out = OutputNaming.sibling(of: url, ext: "pdf"); try AppleApps.pagesExport(url, to: out, format: "PDF"); return out
            case "epub":
                let out = OutputNaming.sibling(of: url, ext: "epub"); try AppleApps.pagesExport(url, to: out, format: "EPUB"); return out
            default:
                try AppleApps.pagesExport(url, to: tmp, format: "Microsoft Word")
                return try DocumentEngine.convert(tmp, to: e, origin: url)
            }
        }
        if e == "pages" {
            var source = url
            var tmp: URL?
            if src != "docx" && src != "rtf" && src != "txt" {
                let t = OutputNaming.tempURL(ext: "docx"); tmp = t
                try DocumentEngine.data(try DocumentEngine.read(url), as: .officeOpenXML).write(to: t)
                source = t
            }
            defer { if let t = tmp { try? fm.removeItem(at: t) } }
            let out = OutputNaming.sibling(of: url, ext: "pages")
            try AppleApps.pagesImport(source, to: out)
            return out
        }
        return try DocumentEngine.convert(url, to: e)
    }

    /// Tableurs : .xls / .numbers passent d'abord par Numbers (export XLSX), puis par notre moteur.
    private static func convertSheet(_ url: URL, to e: String) throws -> URL {
        let src = url.pathExtension.lowercased()
        guard src == "xls" || src == "numbers" else { return try SheetEngine.convert(url, to: e) }
        let tmp = OutputNaming.tempURL(ext: "xlsx")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try AppleApps.numbersExportXLSX(url, to: tmp)
        if e == "xlsx" { let out = OutputNaming.sibling(of: url, ext: "xlsx"); try FileManager.default.copyItem(at: tmp, to: out); return out }
        return try SheetEngine.convert(tmp, to: e, origin: url)
    }

    /// Présentations : Keynote (exporte en PDF) ou, à défaut, LibreOffice ; puis rendu des images depuis le PDF.
    private static func convertSlides(_ url: URL, to e: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let pdf = tmp.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".pdf")
        if AppleApps.App.keynote.isInstalled {
            try AppleApps.keynoteExportPDF(url, to: pdf)
        } else if let soffice = libreOffice {
            try Shell.run(soffice.path, ["--headless", "--convert-to", "pdf", "--outdir", tmp.path, url.path])
        } else {
            throw MandarineError(L("La conversion de présentations nécessite Keynote ou LibreOffice."))
        }
        if e == "pdf" {
            let out = OutputNaming.sibling(of: url, ext: "pdf")
            try FileManager.default.moveItem(at: pdf, to: out)
            return out
        }
        let result = try PDFEngine.toImages(pdf, ext: e)          // produit dans le dossier temporaire
        let isDir = (try? result.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let dest = isDir
            ? OutputNaming.unique(folder: url.deletingLastPathComponent(), base: url.deletingPathExtension().lastPathComponent + " slides", ext: "")
            : OutputNaming.sibling(of: url, ext: e)
        try FileManager.default.moveItem(at: result, to: dest)
        return dest
    }
}

enum MediaEngine {
    static func convertVideo(_ url: URL, to e: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let info = await FFmpeg.probe(url)
        let out = e == "prores" ? OutputNaming.sibling(of: url, suffix: " ProRes", ext: "mov") : OutputNaming.sibling(of: url, ext: e)
        switch e {
        case "prores":
            var o = EncodeOptions()
            o.container = "mov"; o.encoder = .proRes; o.proResProfile = 3; o.longSide = 0; o.fps = 0
            try await VideoEncoder.encode(o, input: url, output: out, progress: progress)
        case "mp3":
            try await FFmpeg.run(["-i", url.path, "-vn"] + FFmpeg.audioArgs(for: "mp3") + [out.path], duration: info.duration, progress: progress)
        case "m4r":
            try await FFmpeg.run(ringtoneArguments(url, out: out, duration: info.duration), duration: min(info.duration, Double(AppSettings.shared.ringtoneSeconds)), progress: progress)
        case "gif":
            let vf = "fps=15,scale='min(640,iw)':-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5"
            try await FFmpeg.run(["-i", url.path, "-vf", vf, "-an", "-loop", "0", out.path], duration: info.duration, progress: progress)
        default:
            var args = ["-i", url.path]
            if !info.hasAudio { args += ["-an"] }
            // MPEG-1/2 (.mpg, DVD, caméscopes) : souvent entrelacé → yadif ne touche que les images marquées entrelacées
            let ext = url.pathExtension.lowercased()
            let camcorder = FileKind.interlacedExts.contains(ext)
            let keep = camcorder && InterlaceMode.current == .keep && ["mp4", "mov", "mkv"].contains(e)          // les autres formats (GIF, WebM…) sont toujours désentrelacés
            let deinterlace = camcorder && !keep ? InterlaceMode.current.deinterlaceFilter + "," : ""
            let squarePixels = FileKind.dvdExts.contains(ext) && !keep ? "scale='trunc(iw*sar/2)*2':ih:flags=lanczos,setsar=1," : ""          // DVD 16:9 : pixels larges → vraie largeur
            args += ["-vf", deinterlace + squarePixels + "scale=trunc(iw/2)*2:trunc(ih/2)*2" + (keep ? ":interl=1" : "")] + FFmpeg.videoArgs(for: e) + (keep ? ["-flags", "+ildct+ilme"] : []) + [out.path]
            try await FFmpeg.run(args, duration: info.duration, progress: progress)
        }
        return out
    }

    /// Sonnerie iPhone : le début du son (durée réglable, 30 s par défaut), fondu de sortie d'une seconde, AAC dans un conteneur .m4r.
    static func ringtoneArguments(_ url: URL, out: URL, duration: Double) -> [String] {
        let n = Double(AppSettings.shared.ringtoneSeconds)
        let length = duration > 0 ? min(n, duration) : n
        let fade = min(1.0, length / 3)
        return ["-i", url.path, "-vn", "-t", String(length), "-af", "afade=t=out:st=\(max(0, length - fade)):d=\(fade)",
                "-c:a", "aac", "-b:a", "192k", "-f", "ipod", out.path]
    }

    static func convertAudio(_ url: URL, to e: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let info = await FFmpeg.probe(url)
        let out = OutputNaming.sibling(of: url, ext: e)
        if e == "m4r" {
            try await FFmpeg.run(ringtoneArguments(url, out: out, duration: info.duration), duration: min(info.duration, Double(AppSettings.shared.ringtoneSeconds)), progress: progress)
            return out
        }
        try await FFmpeg.run(["-i", url.path, "-vn"] + FFmpeg.audioArgs(for: e) + [out.path], duration: info.duration, progress: progress)
        return out
    }
}


/// Un DVD range chaque titre en morceaux d'au plus 1 Go : VTS_01_1.VOB, VTS_01_2.VOB… À convertir un par un, la vidéo serait coupée en plein milieu d'une scène.
/// Si on dépose tous les morceaux d'un même titre, on les recolle dans l'ordre (de simples octets mis bout à bout, sans recompression) avant de convertir.
enum DVDJoin {
    static func parts(of urls: [URL]) -> [URL]? {
        guard urls.count > 1, urls.allSatisfy({ $0.pathExtension.lowercased() == "vob" }) else { return nil }
        var title: String?
        var numbered: [(Int, URL)] = []
        for u in urls {
            let stem = u.deletingPathExtension().lastPathComponent.uppercased()          // VTS_01_3
            let bits = stem.split(separator: "_")
            guard bits.count == 3, bits[0] == "VTS", let n = Int(bits[2]), n > 0 else { return nil }          // _0 = le menu : on ne le recolle pas
            let t = String(bits[0]) + "_" + String(bits[1])
            if title == nil { title = t } else if title != t { return nil }
            numbered.append((n, u))
        }
        return numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func title(of parts: [URL]) -> String { String(parts[0].deletingPathExtension().lastPathComponent.uppercased().split(separator: "_").prefix(2).joined(separator: "_")) }

    /// Recolle les morceaux dans un fichier temporaire « VTS_01.vob ».
    static func join(_ parts: [URL], progress: (Double) -> Void) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-dvd-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(title(of: parts) + ".vob")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        let w = try FileHandle(forWritingTo: out)
        defer { try? w.close() }
        let total = Double(parts.reduce(0) { $0 + $1.fileSize })
        var done = 0.0
        for p in parts {
            let r = try FileHandle(forReadingFrom: p)
            defer { try? r.close() }
            while true {
                try Task.checkCancellation()
                let chunk = r.readData(ofLength: 8 << 20)
                if chunk.isEmpty { break }
                w.write(chunk); done += Double(chunk.count)
                progress(total > 0 ? done / total : 0)
            }
        }
        return out
    }
}
