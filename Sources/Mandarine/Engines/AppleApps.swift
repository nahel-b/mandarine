import Foundation
import AppKit
import PDFKit

/// Pilote Pages / Keynote / Numbers (gratuits, installés sur le Mac) pour les formats propriétaires :
/// .pages en entrée ou en sortie, .key / .ppt / .pptx → PDF ou images, .numbers / .xls → XLSX.
enum AppleApps {
    enum App: String {
        case pages = "com.apple.iWork.Pages", keynote = "com.apple.iWork.Keynote", numbers = "com.apple.iWork.Numbers"
        var name: String { self == .pages ? "Pages" : self == .keynote ? "Keynote" : "Numbers" }
        var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil }
    }

    private static func q(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Exécute un AppleScript avec délai maximal : une app qui affiche un écran d'accueil / une boîte de dialogue bloquerait sinon indéfiniment.
    @discardableResult
    static func script(_ source: String, app: String = "L'app", timeout: TimeInterval = 90) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        try p.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            throw MandarineError("\(app) ne répond pas. Ouvrez-la une fois, fermez son écran d'accueil ou ses boîtes de dialogue, puis réessayez.")
        }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else {
            let msg = String(data: e, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if msg.contains("-1743") { throw MandarineError("Autorisez Mandarine à contrôler \(app) dans Réglages Système → Confidentialité et sécurité → Automatisation.") }
            throw MandarineError(msg.isEmpty ? "Le script a échoué." : msg)
        }
        return String(data: o, encoding: .utf8) ?? ""
    }

    // MARK: Pages
    /// DOCX/RTF/TXT → .pages
    static func pagesImport(_ file: URL, to out: URL) throws {
        try script("""
        tell application "Pages"
            set d to open POSIX file "\(q(file.path))"
            save d in POSIX file "\(q(out.path))"
            close d saving no
        end tell
        """, app: "Pages")
    }

    /// .pages → PDF / Word / texte / EPUB
    static func pagesExport(_ file: URL, to out: URL, format: String) throws {
        try script("""
        tell application "Pages"
            set d to open POSIX file "\(q(file.path))"
            export d to POSIX file "\(q(out.path))" as \(format)
            close d saving no
        end tell
        """, app: "Pages")
    }

    // MARK: Keynote
    static func keynoteExportPDF(_ file: URL, to out: URL) throws {
        try script("""
        tell application "Keynote"
            set d to open POSIX file "\(q(file.path))"
            export d to POSIX file "\(q(out.path))" as PDF
            close d saving no
        end tell
        """, app: "Keynote")
    }

    static func keynoteExportImages(_ file: URL, to folder: URL, format: String) throws {
        try script("""
        tell application "Keynote"
            set d to open POSIX file "\(q(file.path))"
            export d to POSIX file "\(q(folder.path))" as slide images with properties {image format:\(format), skipped slides:false}
            close d saving no
        end tell
        """, app: "Keynote")
    }

    // MARK: Numbers
    static func numbersExportXLSX(_ file: URL, to out: URL) throws {
        try script("""
        tell application "Numbers"
            set d to open POSIX file "\(q(file.path))"
            export d to POSIX file "\(q(out.path))" as Microsoft Excel
            close d saving no
        end tell
        """, app: "Numbers")
    }
}

// MARK: PDF → PPTX (une diapositive par page, image pleine page)
enum PPTXWriter {
    static func write(pages: [(jpeg: Data, size: CGSize)], to url: URL) throws {
        guard let first = pages.first else { throw MandarineError("PDF vide.") }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        for d in ["_rels", "ppt/_rels", "ppt/slides/_rels", "ppt/slideMasters/_rels", "ppt/slideLayouts/_rels", "ppt/theme", "ppt/media"] {
            try fm.createDirectory(at: tmp.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        func w(_ path: String, _ s: String) throws { try s.write(to: tmp.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        let hdr = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        let emu = { (pt: CGFloat) in Int(pt * 12700) }
        let cx = emu(first.size.width), cy = emu(first.size.height)
        let n = pages.count

        var overrides = ""
        for i in 1...n { overrides += "<Override PartName=\"/ppt/slides/slide\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }
        try w("[Content_Types].xml", hdr + """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpg" ContentType="image/jpeg"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\(overrides)</Types>
        """)
        try w("_rels/.rels", hdr + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>")

        var ids = "", rels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for i in 1...n {
            ids += "<p:sldId id=\"\(255 + i)\" r:id=\"rId\(i + 1)\"/>"
            rels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i).xml\"/>"
        }
        rels += "<Relationship Id=\"rId\(n + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>"
        try w("ppt/presentation.xml", hdr + "<p:presentation xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst><p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        try w("ppt/_rels/presentation.xml.rels", hdr + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>")

        let tree = "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        try w("ppt/slideMasters/slideMaster1.xml", hdr + "<p:sldMaster \(ns)><p:cSld><p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>\(tree)</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst></p:sldMaster>")
        try w("ppt/slideMasters/_rels/slideMaster1.xml.rels", hdr + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/></Relationships>")
        try w("ppt/slideLayouts/slideLayout1.xml", hdr + "<p:sldLayout \(ns) type=\"blank\"><p:cSld name=\"Blank\">\(tree)</p:spTree></p:cSld></p:sldLayout>")
        try w("ppt/slideLayouts/_rels/slideLayout1.xml.rels", hdr + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>")
        let font = "<a:latin typeface=\"Helvetica\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        let fill = "<a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:fillStyleLst>"
        let line = "<a:lnStyleLst><a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln><a:ln w=\"19050\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln></a:lnStyleLst>"
        let eff = "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
        let bg = "<a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:bgFillStyleLst>"
        try w("ppt/theme/theme1.xml", hdr + "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Mandarine\"><a:themeElements><a:clrScheme name=\"Mandarine\"><a:dk1><a:srgbClr val=\"000000\"/></a:dk1><a:lt1><a:srgbClr val=\"FFFFFF\"/></a:lt1><a:dk2><a:srgbClr val=\"282B29\"/></a:dk2><a:lt2><a:srgbClr val=\"F4F4F4\"/></a:lt2><a:accent1><a:srgbClr val=\"F35B28\"/></a:accent1><a:accent2><a:srgbClr val=\"F7A72B\"/></a:accent2><a:accent3><a:srgbClr val=\"5B9A6E\"/></a:accent3><a:accent4><a:srgbClr val=\"4A6CC8\"/></a:accent4><a:accent5><a:srgbClr val=\"8A5CC8\"/></a:accent5><a:accent6><a:srgbClr val=\"828782\"/></a:accent6><a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink></a:clrScheme><a:fontScheme name=\"Mandarine\"><a:majorFont>\(font)</a:majorFont><a:minorFont>\(font)</a:minorFont></a:fontScheme><a:fmtScheme name=\"Mandarine\">\(fill)\(line)\(eff)\(bg)</a:fmtScheme></a:themeElements></a:theme>")

        for (i, p) in pages.enumerated() {
            let k = i + 1
            try p.jpeg.write(to: tmp.appendingPathComponent("ppt/media/image\(k).jpg"))
            try w("ppt/slides/slide\(k).xml", hdr + "<p:sld \(ns)><p:cSld>\(tree)<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Page \(k)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic></p:spTree></p:cSld></p:sld>")
            try w("ppt/slides/_rels/slide\(k).xml.rels", hdr + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(k).jpg\"/></Relationships>")
        }
        try? fm.removeItem(at: url)
        try Shell.run("/usr/bin/zip", ["-q", "-X", "-D", "-r", url.path, "[Content_Types].xml", "_rels", "ppt"], cwd: tmp)
    }

    static func fromPDF(_ pdf: URL, to out: URL) throws {
        let doc = try PDFEngine.open(pdf)
        var pages: [(Data, CGSize)] = []
        for i in 0..<doc.pageCount {
            guard let p = doc.page(at: i), let img = PDFEngine.render(page: p, dpi: 150), let data = ImageEngine.data(img, ext: "jpg", quality: 0.85) else { continue }
            let b = p.bounds(for: .mediaBox)
            pages.append((data, p.rotation % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)))
        }
        try write(pages: pages.map { (jpeg: $0.0, size: $0.1) }, to: out)
    }
}

extension PDFEngine {
    /// PDF → table (lignes de texte découpées sur les espaces multiples ou tabulations) pour l'export XLSX.
    static func table(_ doc: PDFDocument) -> [[String]] {
        var rows: [[String]] = []
        let splitter = try? NSRegularExpression(pattern: "\\t+|\\s{2,}")
        for i in 0..<doc.pageCount {
            guard let text = doc.page(at: i)?.string else { continue }
            for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let ns = line as NSString
                var cells: [String] = [], last = 0
                splitter?.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let r = m?.range else { return }
                    cells.append(ns.substring(with: NSRange(location: last, length: r.location - last)))
                    last = r.location + r.length
                }
                cells.append(ns.substring(from: last))
                rows.append(cells.map { $0.trimmingCharacters(in: .whitespaces) })
            }
        }
        // Texte extrait sans espaces multiples : si toutes les lignes ont le même nombre de mots (≥ 2), on découpe sur les espaces simples.
        if rows.count > 1, rows.allSatisfy({ $0.count == 1 }) {
            let tokens = rows.map { $0[0].split(separator: " ").map(String.init) }
            if let n = tokens.first?.count, n >= 2, tokens.allSatisfy({ $0.count == n }) { return tokens }
        }
        return rows
    }
}
