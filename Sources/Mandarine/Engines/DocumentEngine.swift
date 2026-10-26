import Foundation
import AppKit
import PDFKit
import CoreText

/// Documents texte : DOCX, RTF, HTML, TXT, MD, EPUB → PDF/DOCX/TXT/MD/HTML/EPUB/images.
enum DocumentEngine {
    // MARK: Lecture
    static func read(_ url: URL) throws -> NSAttributedString {
        switch url.pathExtension.lowercased() {
        case "docx": return try attributed(url, .officeOpenXML)
        case "doc": return try attributed(url, .docFormat)
        case "rtf": return try attributed(url, .rtf)
        case "rtfd": return try attributed(url, .rtfd)
        case "html", "htm": return try attributed(url, .html)
        case "md", "markdown":
            let s = try String(contentsOf: url, encoding: .utf8)
            return markdown(s)
        case "txt":
            let s = try (try? String(contentsOf: url, encoding: .utf8)) ?? String(contentsOf: url, encoding: .isoLatin1)
            return NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        case "epub": return try EpubEngine.read(url)
        default: throw MandarineError("Format de document non pris en charge : .\(url.pathExtension)")
        }
    }

    private static func attributed(_ url: URL, _ type: NSAttributedString.DocumentType) throws -> NSAttributedString {
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .html { opts[.characterEncoding] = String.Encoding.utf8.rawValue }
        if type == .rtfd, let w = try? FileWrapper(url: url, options: []) {
            if let a = NSAttributedString(rtfdFileWrapper: w, documentAttributes: nil) { return a }
        }
        return try NSAttributedString(url: url, options: opts, documentAttributes: nil)
    }

    static func markdown(_ s: String) -> NSAttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        if let a = try? AttributedString(markdown: s, options: opts) {
            let m = NSMutableAttributedString(attributedString: NSAttributedString(a))
            m.enumerateAttribute(.font, in: NSRange(location: 0, length: m.length)) { v, r, _ in
                if v == nil { m.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: r) }
            }
            return m
        }
        return NSAttributedString(string: s)
    }

    // MARK: Écriture
    static func data(_ text: NSAttributedString, as type: NSAttributedString.DocumentType) throws -> Data {
        let range = NSRange(location: 0, length: text.length)
        if type == .html {
            return try text.data(from: range, documentAttributes: [.documentType: type, .characterEncoding: String.Encoding.utf8.rawValue])
        }
        return try text.data(from: range, documentAttributes: [.documentType: type])
    }

    static func plainText(_ text: NSAttributedString) -> String { text.string }

    /// Export Markdown approximatif : titres selon la taille, gras / italique.
    static func markdownString(_ text: NSAttributedString) -> String {
        var out = ""
        let ns = text.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            var line = ""
            var maxSize: CGFloat = 0
            text.enumerateAttributes(in: range) { attrs, r, _ in
                var piece = ns.substring(with: r)
                guard let font = attrs[.font] as? NSFont else { line += piece; return }
                maxSize = max(maxSize, font.pointSize)
                let t = font.fontDescriptor.symbolicTraits
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if t.contains(.bold) && t.contains(.italic) { piece = piece.replacingOccurrences(of: trimmed, with: "***\(trimmed)***") }
                    else if t.contains(.bold) { piece = piece.replacingOccurrences(of: trimmed, with: "**\(trimmed)**") }
                    else if t.contains(.italic) { piece = piece.replacingOccurrences(of: trimmed, with: "*\(trimmed)*") }
                }
                line += piece
            }
            let level = maxSize >= 22 ? "# " : maxSize >= 17 ? "## " : maxSize >= 14.5 ? "### " : ""
            if !level.isEmpty { line = line.replacingOccurrences(of: "**", with: "") }
            out += level + line + "\n"
            _ = enclosing
        }
        return out
    }

    /// Pagination Core Text → PDF (A4 / Letter selon la locale, marges 0,75").
    static func pdf(_ text: NSAttributedString, to url: URL) throws {
        let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let inset = page.insetBy(dx: 54, dy: 54)
        var mediaBox = page
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { throw MandarineError("Création du PDF impossible.") }
        let setter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        var start = 0
        let total = text.length
        if total == 0 { ctx.beginPDFPage(nil); ctx.endPDFPage() }
        while start < total {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: inset, transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            start += visible.length
        }
        ctx.closePDF()
    }

    // MARK: Conversions
    /// `origin` : fichier d'origine pour nommer les sorties (quand `url` est un intermédiaire temporaire).
    static func convert(_ url: URL, to ext: String, origin: URL? = nil) throws -> URL {
        let src = origin ?? url
        let e = Catalog.normalized(ext)
        let text = try read(url)
        let out = OutputNaming.sibling(of: src, ext: e)
        switch e {
        case "txt": try plainText(text).write(to: out, atomically: true, encoding: .utf8)
        case "md": try markdownString(text).write(to: out, atomically: true, encoding: .utf8)
        case "html": try data(text, as: .html).write(to: out)
        case "docx": try data(text, as: .officeOpenXML).write(to: out)
        case "rtf": try data(text, as: .rtf).write(to: out)
        case "pdf": try pdf(text, to: out)
        case "epub": try EpubEngine.write(text, title: src.deletingPathExtension().lastPathComponent, to: out)
        case "png", "jpg":
            let tmp = OutputNaming.tempURL(ext: "pdf")
            defer { try? FileManager.default.removeItem(at: tmp) }
            try pdf(text, to: tmp)
            let dest = OutputNaming.folder(of: src, suffix: "pages")
            let doc = try PDFEngine.open(tmp)
            var single: URL = dest
            for i in 0..<doc.pageCount {
                guard let p = doc.page(at: i), let img = PDFEngine.render(page: p, dpi: 200) else { continue }
                let f = dest.appendingPathComponent("\(src.deletingPathExtension().lastPathComponent) \(i + 1)").appendingPathExtension(e)
                try ImageEngine.write(img, to: f, ext: e)
                single = f
            }
            if doc.pageCount == 1 {
                let moved = OutputNaming.sibling(of: src, ext: e)
                try FileManager.default.moveItem(at: single, to: moved)
                try? FileManager.default.removeItem(at: dest)
                return moved
            }
            return dest
        default: throw MandarineError("Conversion vers .\(e) non prise en charge.")
        }
        return out
    }
}

/// EPUB minimal : lecture (spine → HTML → texte riche) et écriture (un chapitre XHTML).
enum EpubEngine {
    static func read(_ url: URL) throws -> NSAttributedString {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Shell.run("/usr/bin/unzip", ["-q", "-o", url.path, "-d", tmp.path])
        let container = try String(contentsOf: tmp.appendingPathComponent("META-INF/container.xml"), encoding: .utf8)
        guard let opfPath = firstMatch(in: container, pattern: "full-path=\"([^\"]+)\"") else { throw MandarineError("EPUB invalide.") }
        let opfURL = tmp.appendingPathComponent(opfPath)
        let opf = try String(contentsOf: opfURL, encoding: .utf8)
        let base = opfURL.deletingLastPathComponent()
        var manifest: [String: String] = [:]
        for m in matches(in: opf, pattern: "<item\\b[^>]*>") {
            if let id = firstMatch(in: m, pattern: "\\bid=\"([^\"]+)\""), let href = firstMatch(in: m, pattern: "href=\"([^\"]+)\"") {
                manifest[id] = href.removingPercentEncoding ?? href
            }
        }
        let result = NSMutableAttributedString()
        for ref in matches(in: opf, pattern: "<itemref\\b[^>]*>") {
            guard let idref = firstMatch(in: ref, pattern: "idref=\"([^\"]+)\""), let href = manifest[idref] else { continue }
            let file = base.appendingPathComponent(href)
            guard let data = try? Data(contentsOf: file) else { continue }
            if let a = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                       .characterEncoding: String.Encoding.utf8.rawValue],
                                               documentAttributes: nil) {
                result.append(a)
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result
    }

    static func write(_ text: NSAttributedString, title: String, to url: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try "application/epub+zip".write(to: tmp.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        try """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.write(to: tmp.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)
        let esc = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let paragraphs = text.string.components(separatedBy: "\n").map { "<p>\(esc($0))</p>" }.joined(separator: "\n")
        let chapter = """
        <?xml version="1.0" encoding="utf-8"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(esc(title))</title></head><body>\(paragraphs)</body></html>
        """
        try chapter.write(to: tmp.appendingPathComponent("OEBPS/chapter1.xhtml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(esc(title))</title></head><body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">\(esc(title))</a></li></ol></nav></body></html>
        """.write(to: tmp.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)
        try """
        <?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:uuid:\(UUID().uuidString)</dc:identifier><dc:title>\(esc(title))</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">\(ISO8601DateFormatter().string(from: Date()).prefix(19))Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>
        """.write(to: tmp.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: url)
        // mimetype doit être le premier fichier, non compressé.
        try Shell.run("/usr/bin/zip", ["-q", "-X", "-0", url.path, "mimetype"], cwd: tmp)
        try Shell.run("/usr/bin/zip", ["-q", "-X", "-r", url.path, "META-INF", "OEBPS"], cwd: tmp)
    }

    private static func firstMatch(in s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
    private static func matches(in s: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
}

enum Shell {
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let c = cwd { p.currentDirectoryURL = c }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let edata = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw MandarineError(String(data: edata, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(exe) a échoué.")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
