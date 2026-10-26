import Foundation
import AppKit

// MARK: Sous-titres
enum SubtitleEngine {
    struct Cue { var start: Double; var end: Double; var text: String }

    static func parse(_ s: String) -> [Cue] {
        let text = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[ti].components(separatedBy: "-->")
            guard parts.count == 2, let a = time(parts[0]), let b = time(String(parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "")) else { continue }
            cues.append(Cue(start: a, end: b, text: lines[(ti + 1)...].joined(separator: "\n")))
        }
        return cues
    }

    private static func time(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let p = t.split(separator: ":").map(String.init)
        guard p.count >= 2 else { return nil }
        var sec = 0.0
        for comp in p { sec = sec * 60 + (Double(comp) ?? 0) }
        return sec
    }

    private static func stamp(_ t: Double, comma: Bool) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, comma ? "," : ".", ms % 1000)
    }

    static func convert(_ url: URL, to ext: String) throws -> URL {
        let raw = try (try? String(contentsOf: url, encoding: .utf8)) ?? String(contentsOf: url, encoding: .isoLatin1)
        let cues = parse(raw)
        let out = OutputNaming.sibling(of: url, ext: ext)
        switch ext {
        case "vtt":
            var s = "WEBVTT\n\n"
            for c in cues { s += "\(stamp(c.start, comma: false)) --> \(stamp(c.end, comma: false))\n\(c.text)\n\n" }
            try s.write(to: out, atomically: true, encoding: .utf8)
        case "srt":
            var s = ""
            for (i, c) in cues.enumerated() { s += "\(i + 1)\n\(stamp(c.start, comma: true)) --> \(stamp(c.end, comma: true))\n\(c.text)\n\n" }
            try s.write(to: out, atomically: true, encoding: .utf8)
        case "txt":
            try cues.map(\.text).joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        default: throw MandarineError("Format de sous-titres non pris en charge : \(ext)")
        }
        return out
    }
}

// MARK: Archives
enum ArchiveEngine {
    static func extract(_ url: URL, into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try Shell.run("/usr/bin/bsdtar", ["-xf", url.path, "-C", dir.path]) }
        catch {
            // .gz d'un seul fichier (non tar)
            if url.pathExtension.lowercased() == "gz" || url.pathExtension.lowercased() == "gzip" {
                let name = url.deletingPathExtension().lastPathComponent
                let out = dir.appendingPathComponent(name)
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); p.arguments = ["-dc", url.path]
                FileManager.default.createFile(atPath: out.path, contents: nil)
                p.standardOutput = try FileHandle(forWritingTo: out)
                try p.run(); p.waitUntilExit()
                if p.terminationStatus != 0 { throw MandarineError("Archive illisible.") }
            } else { throw error }
        }
    }

    /// « Extract » : dépose le contenu dans un dossier à côté de l'archive.
    static func extractNextTo(_ url: URL) throws -> URL {
        var base = url.deletingPathExtension()
        if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }
        let dir = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: base.lastPathComponent, ext: "")
        try extract(url, into: dir)
        return dir
    }

    static func convert(_ url: URL, to ext: String) throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        try extract(url, into: tmp)
        var items = try fm.contentsOfDirectory(atPath: tmp.path).filter { $0 != "__MACOSX" && $0 != ".DS_Store" }
        items.sort()
        var base = url.deletingPathExtension()
        if base.pathExtension.lowercased() == "tar" { base = base.deletingPathExtension() }
        let name = base.lastPathComponent
        switch ext {
        case "zip":
            let out = OutputNaming.sibling(of: url, ext: "zip").deletingLastPathComponent().appendingPathComponent(name)
            let dest = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: name, ext: "zip")
            _ = out
            try Shell.run("/usr/bin/zip", ["-q", "-r", "-X", dest.path] + items, cwd: tmp)
            return dest
        case "tar":
            let dest = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: name, ext: "tar")
            try Shell.run("/usr/bin/bsdtar", ["-cf", dest.path] + items, cwd: tmp)
            return dest
        case "gzip":
            // un seul fichier → name.ext.gz ; sinon tar.gz
            if items.count == 1, !isDir(tmp.appendingPathComponent(items[0])) {
                let dest = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: items[0], ext: "gz")
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); p.arguments = ["-c", tmp.appendingPathComponent(items[0]).path]
                fm.createFile(atPath: dest.path, contents: nil)
                p.standardOutput = try FileHandle(forWritingTo: dest)
                try p.run(); p.waitUntilExit()
                return dest
            }
            let dest = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: name + ".tar", ext: "gz")
            try Shell.run("/usr/bin/bsdtar", ["-czf", dest.path] + items, cwd: tmp)
            return dest
        default: throw MandarineError("Archive vers .\(ext) non prise en charge.")
        }
    }

    private static func isDir(_ u: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
    }

    /// Compresser n'importe quel fichier / dossier en ZIP ou GZIP (outil « Compress » générique).
    static func compress(_ url: URL) throws -> URL {
        let dest = OutputNaming.unique(folder: url.deletingLastPathComponent(), base: url.lastPathComponent, ext: "zip")
        try Shell.run("/usr/bin/zip", ["-q", "-r", "-X", dest.path, url.lastPathComponent], cwd: url.deletingLastPathComponent())
        return dest
    }
}

// MARK: Tableurs
enum SheetEngine {
    typealias Table = [[String]]

    static func read(_ url: URL) throws -> Table {
        switch url.pathExtension.lowercased() {
        case "csv": return parseDelimited(try text(url), delimiter: ",")
        case "tsv": return parseDelimited(try text(url), delimiter: "\t")
        case "xlsx": return try readXLSX(url)
        case "ods": return try readODS(url)
        default: throw MandarineError("Tableur non pris en charge : .\(url.pathExtension)")
        }
    }

    private static func text(_ url: URL) throws -> String {
        try (try? String(contentsOf: url, encoding: .utf8)) ?? String(contentsOf: url, encoding: .isoLatin1)
    }

    static func parseDelimited(_ s: String, delimiter: Character) -> Table {
        var rows: Table = [], row: [String] = [], field = "", quoted = false
        var it = s.makeIterator()
        var pending: Character? = nil
        func next() -> Character? { if let p = pending { pending = nil; return p }; return it.next() }
        while let c = next() {
            if quoted {
                if c == "\"" { if let n = next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == delimiter { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" { row.append(field); field = ""; rows.append(row); row = [] }
            else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func serialize(_ t: Table, delimiter: Character) -> String {
        t.map { row in
            row.map { f in
                f.contains(delimiter) || f.contains("\"") || f.contains("\n") ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(delimiter))
        }.joined(separator: "\n") + "\n"
    }

    // XLSX
    private final class XMLCollector: NSObject, XMLParserDelegate {
        var strings: [String] = []
        var rows: Table = []
        var curRow: [String] = []
        var curType = "", curRef = "", buf = "", inV = false, inT = false, inSI = false, siBuf = ""
        var isSharedStrings: Bool
        init(shared: Bool) { isSharedStrings = shared }
        func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            switch name {
            case "si": inSI = true; siBuf = ""
            case "t": inT = true; buf = ""
            case "row": curRow = []
            case "c": curType = a["t"] ?? ""; curRef = a["r"] ?? ""; buf = ""
            case "v": inV = true; buf = ""
            case "is": buf = ""
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inV || inT { buf += s } }
        func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "t": inT = false; if inSI { siBuf += buf } else if curType == "inlineStr" { /* géré à la fin de c */ }
            case "si": inSI = false; strings.append(siBuf)
            case "v": inV = false
            case "c":
                var val = buf
                if curType == "s", let i = Int(buf), strings.indices.contains(i) { val = strings[i] }
                let col = Self.columnIndex(curRef)
                while curRow.count < col { curRow.append("") }
                curRow.append(val)
            case "row": rows.append(curRow)
            default: break
            }
        }
        static func columnIndex(_ ref: String) -> Int {
            var n = 0
            for ch in ref.uppercased() { guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }; n = n * 26 + Int(a - 64) }
            return max(0, n - 1)
        }
    }

    static func readXLSX(_ url: URL) throws -> Table {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Shell.run("/usr/bin/unzip", ["-q", "-o", url.path, "-d", tmp.path])
        let col = XMLCollector(shared: true)
        if let d = try? Data(contentsOf: tmp.appendingPathComponent("xl/sharedStrings.xml")) {
            let p = XMLParser(data: d); p.delegate = col; p.parse()
        }
        let sheet = XMLCollector(shared: false)
        sheet.strings = col.strings
        guard let d = try? Data(contentsOf: tmp.appendingPathComponent("xl/worksheets/sheet1.xml")) else { throw MandarineError("XLSX illisible.") }
        let p = XMLParser(data: d); p.delegate = sheet; p.parse()
        return sheet.rows
    }

    static func writeXLSX(_ t: Table, to url: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        for d in ["_rels", "xl/_rels", "xl/worksheets"] { try fm.createDirectory(at: tmp.appendingPathComponent(d), withIntermediateDirectories: true) }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        func colName(_ i: Int) -> String { var n = i + 1, s = ""; while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }; return s }
        var rowsXML = ""
        for (r, row) in t.enumerated() {
            rowsXML += "<row r=\"\(r + 1)\">"
            for (c, v) in row.enumerated() {
                let ref = "\(colName(c))\(r + 1)"
                if Double(v) != nil, !v.isEmpty { rowsXML += "<c r=\"\(ref)\"><v>\(v)</v></c>" }
                else { rowsXML += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(v))</t></is></c>" }
            }
            rowsXML += "</row>"
        }
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(rowsXML)</sheetData></worksheet>"
            .write(to: tmp.appendingPathComponent("xl/worksheets/sheet1.xml"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
            .write(to: tmp.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
            .write(to: tmp.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
            .write(to: tmp.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>"
            .write(to: tmp.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: url)
        try Shell.run("/usr/bin/zip", ["-q", "-r", "-X", "-D", url.path, "[Content_Types].xml", "_rels", "xl"], cwd: tmp)
    }

    // ODS
    private final class ODSParser: NSObject, XMLParserDelegate {
        var rows: Table = [], row: [String] = [], cell = "", inText = false, repeatCols = 1, repeatRows = 1
        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            switch n {
            case "table:table-row": row = []; repeatRows = Int(a["table:number-rows-repeated"] ?? "1") ?? 1
            case "table:table-cell": cell = ""; repeatCols = Int(a["table:number-columns-repeated"] ?? "1") ?? 1
                if let v = a["office:value"] { cell = v }
            case "text:p": inText = true
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inText { cell += s } }
        func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            switch n {
            case "text:p": inText = false
            case "table:table-cell": for _ in 0..<min(repeatCols, 200) { row.append(cell) }
            case "table:table-row":
                while let l = row.last, l.isEmpty { row.removeLast() }
                if !row.isEmpty { for _ in 0..<min(repeatRows, 200) { rows.append(row) } } else if repeatRows == 1 { rows.append([]) }
            default: break
            }
        }
    }

    static func readODS(_ url: URL) throws -> Table {
        let data = try Shell.runData("/usr/bin/unzip", ["-p", url.path, "content.xml"])
        let parser = ODSParser()
        let xp = XMLParser(data: data); xp.delegate = parser; xp.parse()
        var rows = parser.rows
        while let l = rows.last, l.isEmpty { rows.removeLast() }
        return rows
    }

    static func writeODS(_ t: Table, to url: URL) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        var body = ""
        for row in t {
            body += "<table:table-row>"
            for v in row {
                if Double(v) != nil, !v.isEmpty { body += "<table:table-cell office:value-type=\"float\" office:value=\"\(v)\"><text:p>\(v)</text:p></table:table-cell>" }
                else { body += "<table:table-cell office:value-type=\"string\"><text:p>\(esc(v))</text:p></table:table-cell>" }
            }
            body += "</table:table-row>"
        }
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" office:version=\"1.2\"><office:body><office:spreadsheet><table:table table:name=\"Sheet1\">\(body)</table:table></office:spreadsheet></office:body></office:document-content>"
            .write(to: tmp.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        try "application/vnd.oasis.opendocument.spreadsheet".write(to: tmp.appendingPathComponent("mimetype"), atomically: true, encoding: .ascii)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\"><manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.spreadsheet\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>"
            .write(to: tmp.appendingPathComponent("META-INF/manifest.xml"), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: url)
        try Shell.run("/usr/bin/zip", ["-q", "-X", "-0", url.path, "mimetype"], cwd: tmp)
        try Shell.run("/usr/bin/zip", ["-q", "-X", "-D", "-r", url.path, "content.xml", "META-INF"], cwd: tmp)
    }

    static func convert(_ url: URL, to ext: String, origin: URL? = nil) throws -> URL {
        let table = try read(url)
        let out = OutputNaming.sibling(of: origin ?? url, ext: ext)
        switch ext {
        case "csv": try serialize(table, delimiter: ",").write(to: out, atomically: true, encoding: .utf8)
        case "tsv": try serialize(table, delimiter: "\t").write(to: out, atomically: true, encoding: .utf8)
        case "xlsx": try writeXLSX(table, to: out)
        case "ods": try writeODS(table, to: out)
        case "pdf": try writePDF(table, to: out)
        default: throw MandarineError("Tableur vers .\(ext) non pris en charge.")
        }
        return out
    }

    /// Tableau paginé avec filets, colonnes dimensionnées d'après le contenu.
    static func writePDF(_ t: Table, to url: URL) throws {
        let cols = t.map(\.count).max() ?? 0
        guard cols > 0 else { throw MandarineError("Tableau vide.") }
        let font = NSFont.systemFont(ofSize: 9)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var widths = [CGFloat](repeating: 40, count: cols)
        for row in t { for (i, v) in row.enumerated() { widths[i] = min(220, max(widths[i], (v as NSString).size(withAttributes: attrs).width + 12)) } }
        let total = widths.reduce(0, +)
        let landscape = total > 520
        let page = landscape ? CGRect(x: 0, y: 0, width: 841.89, height: 595.28) : CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let margin: CGFloat = 36
        let scale = min(1, (page.width - 2 * margin) / total)
        let rowH: CGFloat = 16
        var box = page
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw MandarineError("PDF impossible.") }
        let perPage = Int((page.height - 2 * margin) / rowH)
        var r = 0
        repeat {
            ctx.beginPDFPage(nil)
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gc
            for k in 0..<perPage where r + k < t.count {
                let y = page.height - margin - CGFloat(k + 1) * rowH
                var x = margin
                for (i, v) in t[r + k].enumerated() {
                    let w = widths[i] * scale
                    ctx.setStrokeColor(CGColor(gray: 0.82, alpha: 1)); ctx.stroke(CGRect(x: x, y: y, width: w, height: rowH))
                    (v as NSString).draw(in: CGRect(x: x + 4, y: y + 3, width: w - 8, height: rowH - 4), withAttributes: attrs)
                    x += w
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
            r += perPage
        } while r < t.count
        ctx.closePDF()
    }
}

extension Shell {
    static func runData(_ exe: String, _ args: [String]) throws -> Data {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MandarineError("\(exe) a échoué.") }
        return d
    }
}
