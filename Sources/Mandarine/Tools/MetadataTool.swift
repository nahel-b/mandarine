import SwiftUI
import ImageIO
import PDFKit

struct MetaRow: Identifiable {
    let id = UUID()
    var group: String
    var path: String          // clé technique (chemin CGImageMetadata, clé ffmpeg, clé PDF)
    var name: String
    var value: String
    var original: String
    var removed = false
}

enum MetadataIO {
    static func groupName(_ prefix: String) -> String {
        switch prefix.lowercased() {
        case "exif": return "ExifIFD"
        case "exifaux": return "ExifAux"
        case "tiff": return "TIFF"
        case "gps": return "GPS"
        case "iptc", "iptc4xmpcore", "iptc4xmpext": return "IPTC"
        case "xmp", "xmpmm", "xmprights": return "XMP"
        case "photoshop": return "Photoshop"
        case "dc": return "Dublin Core"
        default: return prefix.uppercased() == prefix ? prefix : prefix.capitalized
        }
    }

    static func prettify(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, ch.isUppercase, let last = out.last, !last.isUppercase, last != " " { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    static func read(_ url: URL) async -> [MetaRow] {
        switch FileKind.detect(url) {
        case .image: return readImage(url)
        case .pdf: return readPDF(url)
        default: return await readMedia(url)
        }
    }

    static func readImage(_ url: URL) -> [MetaRow] {
        var rows: [MetaRow] = []
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let md = CGImageSourceCopyMetadataAtIndex(src, 0, nil) else { return rows }
        CGImageMetadataEnumerateTagsUsingBlock(md, nil, nil) { path, tag in
            guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?, let name = CGImageMetadataTagCopyName(tag) as String? else { return true }
            let v = CGImageMetadataTagCopyValue(tag)
            guard let value = v as? String ?? (v as? NSNumber).map({ "\($0)" }) else { return true }   // ignore les structures
            rows.append(MetaRow(group: groupName(prefix), path: path as String, name: prettify(name), value: value, original: value))
            return true
        }
        return rows.sorted { ($0.group, $0.name) < ($1.group, $1.name) }
    }

    static func readPDF(_ url: URL) -> [MetaRow] {
        guard let d = PDFDocument(url: url), let a = d.documentAttributes else { return [] }
        return a.compactMap { k, v in
            let key = "\(k)"
            let s: String
            if let date = v as? Date { s = ISO8601DateFormatter().string(from: date) } else if let arr = v as? [Any] { s = arr.map { "\($0)" }.joined(separator: ", ") } else { s = "\(v)" }
            return MetaRow(group: "PDF", path: key, name: key, value: s, original: s)
        }.sorted { $0.name < $1.name }
    }

    static func readMedia(_ url: URL) async -> [MetaRow] {
        let info = await FFmpeg.probe(url)
        return info.tags.map { MetaRow(group: "File", path: $0.key, name: prettify($0.key), value: $0.value, original: $0.value) }
            .sorted { $0.name < $1.name }
    }

    // MARK: Écriture
    static func write(url: URL, rows: [MetaRow], removeAll: Bool) async throws -> URL {
        switch FileKind.detect(url) {
        case .image: return try writeImage(url, rows: rows, removeAll: removeAll)
        case .pdf: return try writePDF(url, rows: rows, removeAll: removeAll)
        default: return try await writeMedia(url, rows: rows, removeAll: removeAll)
        }
    }

    static func writeImage(_ url: URL, rows: [MetaRow], removeAll: Bool) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src) else { throw MandarineError("Image illisible.") }
        let out = OutputNaming.sibling(of: url, suffix: removeAll ? " clean" : " metadata")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else { throw MandarineError("Écriture impossible.") }
        let md: CGMutableImageMetadata
        var opts: [CFString: Any] = [kCGImageDestinationMergeMetadata: false]
        if removeAll {
            md = CGImageMetadataCreateMutable()
            opts[kCGImageMetadataShouldExcludeGPS] = true
            opts[kCGImageMetadataShouldExcludeXMP] = true
        } else {
            guard let orig = CGImageSourceCopyMetadataAtIndex(src, 0, nil), let copy = CGImageMetadataCreateMutableCopy(orig) else { throw MandarineError("Métadonnées illisibles.") }
            md = copy
            for r in rows {
                if r.removed { CGImageMetadataRemoveTagWithPath(md, nil, r.path as CFString) }
                else if r.value != r.original { CGImageMetadataSetValueWithPath(md, nil, r.path as CFString, r.value as CFString) }
            }
            if rows.contains(where: { $0.removed && $0.group == "GPS" }) { opts[kCGImageMetadataShouldExcludeGPS] = true }
        }
        opts[kCGImageDestinationMetadata] = md
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &err) else {
            try? FileManager.default.removeItem(at: out)
            throw MandarineError((err?.takeRetainedValue() as Error?)?.localizedDescription ?? "Écriture impossible.")
        }
        return out
    }

    static func writePDF(_ url: URL, rows: [MetaRow], removeAll: Bool) throws -> URL {
        guard let d = PDFDocument(url: url) else { throw MandarineError("PDF illisible.") }
        var attrs: [AnyHashable: Any] = [:]
        if !removeAll { for r in rows where !r.removed { attrs[PDFDocumentAttribute(rawValue: r.path)] = r.value } }
        d.documentAttributes = attrs
        let out = OutputNaming.sibling(of: url, suffix: removeAll ? " clean" : " metadata")
        guard d.write(to: out) else { throw MandarineError("Écriture impossible.") }
        return out
    }

    static func writeMedia(_ url: URL, rows: [MetaRow], removeAll: Bool) async throws -> URL {
        let out = OutputNaming.sibling(of: url, suffix: removeAll ? " clean" : " metadata")
        var args = ["-i", url.path, "-map", "0", "-c", "copy", "-map_metadata", "-1", "-map_chapters", removeAll ? "-1" : "0"]
        if !removeAll { for r in rows where !r.removed { args += ["-metadata", "\(r.path)=\(r.value)"] } }
        try await FFmpeg.run(args + [out.path])
        return out
    }
}

struct MetadataTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var rows: [MetaRow] = []
    @State private var query = ""
    @State private var loading = true

    private var isPhoto: Bool { FileKind.detect(urls[0]) == .image }
    private var groups: [String] { Array(Set(rows.map(\.group))).sorted() }

    var body: some View {
        ToolShell(title: "Metadata", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(urls[0].lastPathComponent).sectionLabel()
                    Spacer()
                    TextField("Search metadata", text: $query).textFieldStyle(.roundedBorder).frame(width: 190)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                        else if rows.isEmpty { Text("No metadata found.").foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding() }
                        ForEach(groups, id: \.self) { g in
                            let items = rows.indices.filter { rows[$0].group == g && matches(rows[$0]) && !rows[$0].removed }
                            if !items.isEmpty {
                                Text(g).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                                Divider()
                                ForEach(items, id: \.self) { i in
                                    HStack(spacing: 10) {
                                        Text(rows[i].name).font(.system(size: 12, weight: .medium)).frame(width: 150, alignment: .trailing).lineLimit(1)
                                        TextField("", text: $rows[i].value).textFieldStyle(.plain).font(.system(size: 12))
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(rows[i].value != rows[i].original ? 0.1 : 0.05)))
                                        Button { rows[i].removed = true } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.muted) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }.padding(.trailing, 8)
                }.frame(height: 330)
                Text("For photos, Remove All also clears hidden camera and processing data. HDR and portrait effects may change.")
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 520)
        } footer: {
            Spacer()
            Button("Remove All") { run(removeAll: true) }.buttonStyle(PillButtonStyle())
            Button("Save") { run(removeAll: false) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(!rows.contains { $0.removed || $0.value != $0.original })
        }
        .task { rows = await MetadataIO.read(urls[0]); loading = false }
    }

    private func matches(_ r: MetaRow) -> Bool {
        query.isEmpty || r.name.localizedCaseInsensitiveContains(query) || r.value.localizedCaseInsensitiveContains(query)
    }

    private func run(removeAll: Bool) {
        let files = urls, rs = rows
        close()
        Dispatcher.job(removeAll ? "Removing metadata…" : "Saving metadata…", light: true) { _ in
            var outs: [URL] = []
            for (i, f) in files.enumerated() { outs.append(try await MetadataIO.write(url: f, rows: i == 0 ? rs : [], removeAll: removeAll || i > 0)) }
            return outs
        }
    }
}
