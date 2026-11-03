import SwiftUI
import AppKit

// MARK: Données — construites à partir du vrai catalogue de l'app, donc toujours à jour

/// Un onglet de la fenêtre : un type de fichier (ou de glisser) et les fichiers factices qui servent à interroger le catalogue.
private enum FeatureTab: String, CaseIterable, Identifiable {
    case image, video, audio, pdf, document, slides, spreadsheet, epub, subtitle, archive, folder, text, link, mixed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: return "Images"; case .video: return "Videos"; case .audio: return "Audio"; case .pdf: return "PDF"
        case .document: return "Documents"; case .slides: return "Slides"; case .spreadsheet: return "Spreadsheets"; case .epub: return "EPUB"
        case .subtitle: return "Subtitles"; case .archive: return "Archives"; case .folder: return "Folders"; case .text: return "Dragged text"
        case .link: return "Web links"; case .mixed: return "Mixed files"
        }
    }
    var symbol: String {
        switch self {
        case .image: return "photo"; case .video: return "film"; case .audio: return "waveform"; case .pdf: return "doc.richtext"
        case .document: return "doc.text"; case .slides: return "rectangle.on.rectangle"; case .spreadsheet: return "tablecells"; case .epub: return "book"
        case .subtitle: return "text.bubble"; case .archive: return "archivebox"; case .folder: return "folder"; case .text: return "text.alignleft"
        case .link: return "link"; case .mixed: return "square.stack.3d.up"
        }
    }
    var tagline: String {
        switch self {
        case .image: return "JPG, PNG, WebP, HEIC, TIFF, AVIF, BMP, GIF and SVG."
        case .video: return "MP4, MOV, MKV, WebM, AVI, WMV and more."
        case .audio: return "MP3, M4A, WAV, FLAC, OGG, Opus, AIFF, WMA and more."
        case .pdf: return "Any PDF, scanned or not."
        case .document: return "DOCX, Pages, Markdown, TXT, RTF, HTML."
        case .slides: return "PowerPoint and Keynote."
        case .spreadsheet: return "XLSX, XLS, ODS, CSV, TSV and Numbers."
        case .epub: return "E-books."
        case .subtitle: return "SRT and VTT."
        case .archive: return "ZIP, TAR, GZIP and RAR."
        case .folder: return "Drag a whole folder."
        case .text: return "Select some text and drag it: it becomes a small file."
        case .link: return "Drag a link from your browser. Videos and pages."
        case .mixed: return "Several different kinds of file in one selection."
        }
    }
    /// Un fichier, et deux fichiers du même type : l'écart entre les deux révèle ce qui ne s'offre qu'à partir de 2 fichiers.
    var samples: (one: [URL], many: [URL]) {
        func f(_ n: String) -> URL { URL(fileURLWithPath: "/Mandarine/\(n)") }
        func two(_ ext: String) -> (one: [URL], many: [URL]) { ([f("a.\(ext)")], [f("a.\(ext)"), f("b.\(ext)")]) }
        switch self {
        case .image: return two("jpg")
        case .video: return two("mp4")
        case .audio: return two("mp3")
        case .pdf: return two("pdf")
        case .document: return two("docx")
        case .slides: return two("pptx")
        case .spreadsheet: return two("xlsx")
        case .epub: return two("epub")
        case .subtitle: return two("srt")
        case .archive: return two("zip")
        case .folder: return ([HelpAssets.fakeFolder], [HelpAssets.fakeFolder, HelpAssets.fakeFolder])
        case .text:
            let t = SnippetStore.folder.appendingPathComponent("sample/Selected text.txt")
            return ([t], [t])
        case .link:
            let l = URL(string: "https://www.youtube.com/watch?v=abc")!
            return ([l], [l])
        case .mixed:
            let m = [f("a.jpg"), f("a.mp4"), f("a.pdf")]
            return (m, m)
        }
    }
}

private struct Feature: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    var severalOnly = false          // proposé seulement quand on glisse plusieurs fichiers
    var available = true
    var children: [Feature] = []
}

private struct Format: Identifiable { let id: String; let label: String; let available: Bool; let severalOnly: Bool }

private struct FeatureSection: Identifiable {
    let mode: WheelMode
    var formats: [Format] = []
    var features: [Feature] = []
    var id: String { mode.rawValue }
    var count: Int { formats.count + features.reduce(0) { $0 + max(1, $1.children.count) } }
}

private enum FeatureLibrary {
    static func sections(for tab: FeatureTab) -> [FeatureSection] {
        let (one, many) = tab.samples
        return WheelMode.allCases.compactMap { mode in
            let a = Catalog.items(mode: mode, urls: one), b = Catalog.items(mode: mode, urls: many)
            var s = FeatureSection(mode: mode)
            if mode == .convert {
                let seen = Set(a.map(\.label))
                s.formats = (a + b.filter { !seen.contains($0.label) && $0.id != "multi-pdf" }).reduce(into: [Format]()) { out, item in
                    guard !out.contains(where: { $0.label == item.label }) else { return }
                    out.append(Format(id: item.id, label: item.label, available: item.enabled, severalOnly: !seen.contains(item.label)))
                }
                if b.contains(where: { $0.id == "multi-pdf" }) {
                    s.features.append(Feature(id: "multi-pdf", symbol: "doc.on.doc", title: "Several images → one PDF",
                                              detail: "Select many images and drop them on PDF: one page per image.", severalOnly: true))
                }
            } else {
                let known = Set(flatten(a))
                s.features = (b.isEmpty ? a : b).map { feature($0, known: known) }
            }
            return s.formats.isEmpty && s.features.isEmpty ? nil : s
        }
    }

    private static func flatten(_ items: [WheelItem]) -> [String] { items.flatMap { [$0.id] + flatten($0.children) } }

    private static func feature(_ item: WheelItem, known: Set<String>) -> Feature {
        let kids = item.children.map { feature($0, known: known) }
        let detail = item.id == "copyPath" && item.label == "COPY LINK" ? "Copy the link as text." : WiiText.description(item)
        return Feature(id: item.id, symbol: item.symbol ?? "circle", title: item.caption, detail: detail == item.caption ? "" : detail,
                       severalOnly: kids.isEmpty ? !known.contains(item.id) : kids.allSatisfy(\.severalOnly), available: item.enabled, children: kids)
    }

    /// Tout, pour la recherche : une ligne par fonction, avec les types de fichier qui la proposent.
    struct Hit: Identifiable {
        let id: String
        let symbol: String, title: String, detail: String
        let mode: WheelMode
        var tabs: [FeatureTab]
    }
    static func hits(_ all: [FeatureTab: [FeatureSection]]) -> [Hit] {
        var out: [Hit] = []
        func add(_ id: String, _ symbol: String, _ title: String, _ detail: String, _ mode: WheelMode, _ tab: FeatureTab) {
            if let i = out.firstIndex(where: { $0.id == id }) { if !out[i].tabs.contains(tab) { out[i].tabs.append(tab) } }
            else { out.append(Hit(id: id, symbol: symbol, title: title, detail: detail, mode: mode, tabs: [tab])) }
        }
        for tab in FeatureTab.allCases {
            for s in all[tab] ?? [] {
                for f in s.formats { add("c-" + f.label, "arrow.triangle.2.circlepath", "Convert to " + f.label.capitalized, "Saves a copy in this format next to the original.", .convert, tab) }
                for f in s.features {
                    add(s.mode.rawValue + "-" + f.id, f.symbol, f.title, f.detail, s.mode, tab)
                    for c in f.children { add(s.mode.rawValue + "-" + c.id, c.symbol, c.title, c.detail, s.mode, tab) }
                }
            }
        }
        return out
    }
}

// MARK: Vue

struct FeaturesView: View {
    let close: () -> Void
    @State private var selected: FeatureTab = .image
    @State private var query = ""
    @FocusState private var searching: Bool
    @ObservedObject private var settings = AppSettings.shared
    private let data: [FeatureTab: [FeatureSection]]
    private let hits: [FeatureLibrary.Hit]

    init(startTab: String = "image", startQuery: String = "", close: @escaping () -> Void) {
        self.close = close
        var d: [FeatureTab: [FeatureSection]] = [:]
        for t in FeatureTab.allCases { d[t] = FeatureLibrary.sections(for: t) }
        data = d
        hits = FeatureLibrary.hits(d)
        _selected = State(initialValue: FeatureTab(rawValue: startTab) ?? .image)
        _query = State(initialValue: startQuery)
    }

    private func count(_ tab: FeatureTab) -> Int { (data[tab] ?? []).reduce(0) { $0 + $1.count } }
    private var total: Int { hits.count }
    private func key(_ mode: WheelMode) -> String { String(settings.key(for: mode).title.prefix(1)) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            ZStack {
                if query.trimmingCharacters(in: .whitespaces).isEmpty { page(selected).id(selected) } else { results }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.985, green: 0.985, blue: 0.98))
        }
        .frame(width: 980, height: 640)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Barre latérale

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("All features").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(total) things Mandarine can do").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }.padding(.top, 44).padding(.horizontal, 18)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 13)).focused($searching)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted.opacity(0.7)) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.055)))
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(FeatureTab.allCases) { t in
                        let on = selected == t && query.isEmpty
                        Button { query = ""; withAnimation(.easeInOut(duration: 0.15)) { selected = t } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.symbol).font(.system(size: 13, weight: .medium)).frame(width: 20)
                                    .foregroundStyle(on ? Theme.orange : Theme.muted)
                                Text(t.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                                Spacer()
                                Text("\(count(t))").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(on ? Theme.orange : Theme.muted.opacity(0.8))
                            }
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Theme.orange.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10).padding(.bottom, 12)
            }
            Divider().opacity(0.6)
            Button { close() } label: {
                Label("Open the guide", systemImage: "chevron.left").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 228)
        .background(Color.white)
    }

    // MARK: Page d'un type

    private func page(_ tab: FeatureTab) -> some View {
        let sections = data[tab] ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(tab, sections)
                ForEach(sections) { s in sectionView(s) }
                Text("Some tools only appear when they are turned on in Settings → Petals, or when the app they need is installed (VS Code, ffmpeg…).")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ tab: FeatureTab, _ sections: [FeatureSection]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: tab.symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(LinearGradient(colors: [Theme.orange, Theme.orange.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: Theme.orange.opacity(0.35), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(tab.title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.text)
                Text(tab.tagline).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(sections) { s in
                    VStack(spacing: 1) {
                        Text("\(s.count)").font(.system(size: 18, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
                        Text(key(s.mode)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
                    }
                    .frame(width: 52, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
            }
        }
    }

    private func sectionView(_ s: FeatureSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(key(s.mode)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.orange))
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.mode.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Tap \(key(s.mode)) while you drag").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
            }
            if !s.formats.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Saved as a copy next to the original, in:").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 7) { ForEach(s.formats) { FormatChip(format: $0) } }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if !s.features.isEmpty { Masonry(items: s.features) { FeatureCard(feature: $0) } }
        }
    }

    // MARK: Recherche

    private var results: some View {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let found = hits.filter { h in
            let hay = (h.title + " " + h.detail + " " + h.tabs.map(\.title).joined(separator: " ")).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.sorted { a, b in
            let q = query.lowercased()
            let ta = a.title.lowercased().contains(q), tb = b.title.lowercased().contains(q)
            return ta != tb ? ta : false
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(found.isEmpty ? "Nothing found" : "\(found.count) result\(found.count == 1 ? "" : "s")")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text).padding(.bottom, 4)
                if found.isEmpty {
                    Text("Try a file type (“pdf”), an action (“trim”), a format (“webp”) or a word like “background”.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                ForEach(found) { h in
                    HStack(spacing: 12) {
                        IconTile(symbol: h.symbol)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(h.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(key(h.mode)).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.orange)
                                    .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Theme.orange.opacity(0.13)))
                            }
                            if !h.detail.isEmpty { Text(h.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                        }
                        Spacer(minLength: 8)
                        FlowLayout(spacing: 5, alignment: .trailing) {
                            ForEach(h.tabs) { t in
                                Button { query = ""; selected = t } label: {
                                    HStack(spacing: 4) { Image(systemName: t.symbol).font(.system(size: 9)); Text(t.title).font(.system(size: 10.5, weight: .medium)) }
                                        .foregroundStyle(Theme.text.opacity(0.75)).padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(Capsule().fill(Color.black.opacity(0.06)))
                                }.buttonStyle(.plain)
                            }
                        }.frame(width: 220, alignment: .trailing)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
            }
            .padding(.horizontal, 32).padding(.top, 44).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Éléments

private struct IconTile: View {
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Theme.orange)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Theme.orange.opacity(0.13)))
    }
}

private struct FormatChip: View {
    let format: Format
    var body: some View {
        HStack(spacing: 5) {
            Text(format.label).font(.system(size: 11.5, weight: .semibold))
            if format.severalOnly { Image(systemName: "square.on.square").font(.system(size: 9)).foregroundStyle(Theme.orange) }
        }
        .foregroundStyle(Theme.text.opacity(format.available ? 1 : 0.4))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.06)))
        .help(format.available ? (format.severalOnly ? "Only when you drag several files" : "") : "Needs an engine that isn't installed yet (Settings → Engines)")
    }
}

private struct FeatureCard: View {
    let feature: Feature
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: feature.symbol)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(feature.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                        if feature.severalOnly { SeveralBadge() }
                    }
                    if !feature.detail.isEmpty {
                        Text(feature.detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if !feature.children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(feature.children.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider().opacity(0.5) }
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: c.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange).frame(width: 18).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(c.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                                    if c.severalOnly && !feature.severalOnly { SeveralBadge() }
                                }
                                if !c.detail.isEmpty { Text(c.detail).font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.035)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(feature.available ? 1 : 0.5)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(hover ? Theme.orange.opacity(0.45) : Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(hover ? 0.09 : 0.03), radius: hover ? 10 : 3, y: hover ? 4 : 1)
        .offset(y: hover ? -1 : 0)
        .animation(.easeOut(duration: 0.14), value: hover)
        .onHover { hover = $0 }
    }
}

private struct SeveralBadge: View {
    var body: some View {
        HStack(spacing: 3) { Image(systemName: "square.on.square").font(.system(size: 8, weight: .bold)); Text("2+ files").font(.system(size: 9.5, weight: .semibold)) }
            .foregroundStyle(Theme.orange).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Theme.orange.opacity(0.13)))
            .help("Only offered when you drag several files")
    }
}

/// Deux colonnes : chaque carte va dans la colonne la moins remplie (les groupes sont plus hauts).
private struct Masonry<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let card: (Item) -> Card
    init(items: [Item], @ViewBuilder card: @escaping (Item) -> Card) { self.items = items; self.card = card }

    private var columns: [[Item]] {
        var cols: [[Item]] = [[], []], heights = [0.0, 0.0]
        for it in items {
            let weight = 1.0 + Double((it as? Feature)?.children.count ?? 0) * 0.85
            let i = heights[0] <= heights[1] ? 0 : 1
            cols[i].append(it); heights[i] += weight
        }
        return cols
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { c in
                VStack(spacing: 12) { ForEach(columns[c]) { card($0) } }.frame(maxWidth: .infinity)
            }
        }
    }
}

/// Étiquettes qui passent à la ligne.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(proposal.width ?? 600, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in layout(bounds.width, subviews) {
            var x = bounds.minX + (alignment == .trailing ? bounds.width - row.width : 0)
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
        }
    }
    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }
    private func layout(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()], y: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            let add = (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + s.width
            if rows[rows.count - 1].width + add > maxWidth, !rows[rows.count - 1].indices.isEmpty {
                y += rows[rows.count - 1].height + spacing
                rows.append(Row(y: y))
            }
            let n = rows.count - 1
            rows[n].width += (rows[n].indices.isEmpty ? 0 : spacing) + s.width
            rows[n].height = max(rows[n].height, s.height)
            rows[n].indices.append(i)
        }
        return rows
    }
}

// MARK: Fenêtre

final class FeaturesWindowController: NSObject, NSWindowDelegate {
    static let shared = FeaturesWindowController()
    private var window: NSWindow?

    static func show(tab: String = "image") { shared.present(tab) }

    private func present(_ tab: String) {
        if let w = window { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let host = NSHostingView(rootView: FeaturesView(startTab: tab, close: { [weak self] in
            self?.window?.close()
            HelpWindowController.show()
        }))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .white
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
