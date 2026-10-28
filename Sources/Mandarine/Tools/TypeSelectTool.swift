import SwiftUI

/// Type Select : dans une sélection, ne garder que certaines extensions, catégories (photos, vidéos…) ou étiquettes Finder, avec un filtre de taille et de date,
/// puis sélectionner le résultat dans le Finder.
struct TypeSelectTool: View {
    let urls: [URL]
    let close: () -> Void

    private struct Item { let url: URL; let ext: String; let kind: FileKind; let size: Int64; let date: Date?; let tags: [FinderTag] }
    private struct TagChip: Identifiable { let key: String; let tag: FinderTag?; let count: Int; var id: String { key } }
    private static let noTag = "\u{1}no-tag"
    private struct Chip: Identifiable { let ext: String; let kind: FileKind; let count: Int; var id: String { ext } }

    @State private var items: [Item] = []
    @State private var chosen: Set<String> = []
    @State private var chosenTags: Set<String> = []
    @State private var sizeMode = 0                 // 0 : toutes tailles, 1 : plus grand que, 2 : plus petit que
    @State private var sizeMB = 10.0
    @State private var dateChoice = 0
    @State private var loading = true

    private static let sizes: [Double] = [1, 5, 10, 50, 100, 500, 1000]
    private static let dates = ["Any date", "Today", "Last 7 days", "Last 30 days", "Last year", "Older than a year"]

    private var chips: [Chip] {
        Dictionary(grouping: items, by: \.ext).map { Chip(ext: $0.key, kind: $0.value[0].kind, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.ext < $1.ext }
    }
    private var categories: [(String, FileKind)] {
        [("Photos", .image), ("Videos", .video), ("Audio", .audio), ("PDF", .pdf), ("Documents", .document), ("Archives", .archive), ("Folders", .folder)]
            .filter { c in items.contains { $0.kind == c.1 } }
    }
    private var tagChips: [TagChip] {
        var byName: [String: (FinderTag, Int)] = [:], order: [String] = []
        for it in items { for t in it.tags { if byName[t.name] == nil { byName[t.name] = (t, 0); order.append(t.name) }; byName[t.name]!.1 += 1 } }
        guard !order.isEmpty else { return [] }
        var chips = order.map { TagChip(key: $0, tag: byName[$0]!.0, count: byName[$0]!.1) }
        let untagged = items.filter { $0.tags.isEmpty }.count
        if untagged > 0 { chips.append(TagChip(key: Self.noTag, tag: nil, count: untagged)) }
        return chips
    }
    private var filtering: Bool { !chosen.isEmpty || !chosenTags.isEmpty || sizeMode != 0 || dateChoice != 0 }

    private var matches: [URL] {
        guard filtering else { return [] }
        let now = Date(), cal = Calendar.current
        return items.filter { it in
            if !chosen.isEmpty && !chosen.contains(it.ext) { return false }
            if !chosenTags.isEmpty {
                let has = it.tags.isEmpty ? chosenTags.contains(Self.noTag) : it.tags.contains { chosenTags.contains($0.name) }
                if !has { return false }
            }
            if sizeMode == 1 && it.size < Int64(sizeMB * 1_000_000) { return false }
            if sizeMode == 2 && it.size > Int64(sizeMB * 1_000_000) { return false }
            if dateChoice != 0 {
                guard let d = it.date else { return false }
                switch dateChoice {
                case 1: if !cal.isDateInToday(d) { return false }
                case 2: if d < now.addingTimeInterval(-7 * 86400) { return false }
                case 3: if d < now.addingTimeInterval(-30 * 86400) { return false }
                case 4: if d < now.addingTimeInterval(-365 * 86400) { return false }
                default: if d >= now.addingTimeInterval(-365 * 86400) { return false }
                }
            }
            return true
        }.map(\.url)
    }

    var body: some View {
        ToolShell(title: "Type Select", close: close) {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(30)
                } else {
                    Text("Extensions in your selection").sectionLabel()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(chips) { c in chip(c) }
                    }
                    if categories.count > 1 {
                        HStack(spacing: 6) {
                            Text("Kinds").sectionLabel()
                            ForEach(categories, id: \.1) { name, kind in
                                Button(name) { toggle(kind) }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                        }
                    }
                    let tc = tagChips
                    if !tc.isEmpty {
                        Text("Finder tags").sectionLabel()
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], alignment: .leading, spacing: 8) {
                            ForEach(tc) { c in tagDot(c) }
                        }
                    }
                    Divider()
                    HStack {
                        Text("Size").sectionLabel().frame(width: 40, alignment: .leading)
                        Picker("", selection: $sizeMode) { Text("Any").tag(0); Text("Larger than").tag(1); Text("Smaller than").tag(2) }.labelsHidden().frame(width: 140)
                        if sizeMode != 0 {
                            Picker("", selection: $sizeMB) { ForEach(Self.sizes, id: \.self) { Text($0 >= 1000 ? "1 GB" : "\(Int($0)) MB").tag($0) } }.labelsHidden().frame(width: 90)
                        }
                        Spacer()
                    }
                    HStack {
                        Text("Date").sectionLabel().frame(width: 40, alignment: .leading)
                        Picker("", selection: $dateChoice) { ForEach(0..<Self.dates.count, id: \.self) { Text(Self.dates[$0]).tag($0) } }.labelsHidden().frame(width: 180)
                        Text("last modified").sectionLabel()
                        Spacer()
                    }
                    Text(filtering ? "\(matches.count) of \(items.count) items match" : "Pick extensions or tags, or set a size or date filter.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                }
            }.frame(width: 470, alignment: .leading)
        } footer: {
            Button("Clear") { chosen = []; chosenTags = []; sizeMode = 0; dateChoice = 0 }.buttonStyle(PillButtonStyle()).disabled(!filtering)
            Button(matches.count == 1 ? "Select 1 item" : "Select \(matches.count) items") {
                let f = matches, n = urls.count; close(); TagSelect.select(f, of: n)
            }.buttonStyle(PillButtonStyle()).disabled(matches.isEmpty)
        }
        .task { await load() }
    }

    private func chip(_ c: Chip) -> some View {
        let on = chosen.contains(c.ext)
        return Button { if on { chosen.remove(c.ext) } else { chosen.insert(c.ext) } } label: {
            HStack(spacing: 6) {
                Text(c.ext.uppercased()).font(.system(size: 12, weight: .semibold))
                Text("\(c.count)").font(.system(size: 11).monospacedDigit()).opacity(0.7)
            }
            .foregroundStyle(on ? Color.white : Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(Capsule().fill(on ? Theme.orange : Color.primary.opacity(0.08)))
        }.buttonStyle(.plain)
    }

    /// Rond de couleur d'une étiquette : sélectionné = bord blanc ; sinon estompé. « No tag » = rond vide.
    private func tagDot(_ c: TagChip) -> some View {
        let on = chosenTags.contains(c.key)
        return Button { if on { chosenTags.remove(c.key) } else { chosenTags.insert(c.key) } } label: {
            VStack(spacing: 4) {
                Circle().fill(c.tag?.swiftUIColor ?? Color.clear).frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.black.opacity(c.tag == nil || c.tag?.color == 0 ? 0.3 : 0), lineWidth: 1.2))
                    .overlay(Circle().stroke(Color.white, lineWidth: on ? 3.2 : 0))
                    .shadow(color: on ? Color.black.opacity(0.35) : .clear, radius: 2.2, y: 1)
                    .opacity(on ? 1 : 0.5)
                Text(c.tag?.name ?? "No tag").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(c.count)").font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func toggle(_ kind: FileKind) {
        let exts = Set(items.filter { $0.kind == kind }.map(\.ext))
        if exts.isSubset(of: chosen) { chosen.subtract(exts) } else { chosen.formUnion(exts) }
    }

    private func load() async {
        let list = urls
        items = await Task.detached {
            list.map { u in
                let kind = FileKind.detect(u)
                let ext = kind == .folder ? "folder" : (u.pathExtension.isEmpty ? "no extension" : Catalog.normalized(u.pathExtension))
                let date = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return Item(url: u, ext: ext, kind: kind, size: kind == .folder ? 0 : u.fileSize, date: date, tags: TagSelect.tags(of: u))
            }
        }.value
        if let e = ProcessInfo.processInfo.environment["MANDARINE_TYPES"] { chosen = Set(e.split(separator: ",").map(String.init)) }      // (tests)
        if let e = ProcessInfo.processInfo.environment["MANDARINE_TAGS"] { chosenTags = Set(e.split(separator: ",").map(String.init)) }
        loading = false
    }
}
