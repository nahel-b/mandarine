import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Table AppKit : sélection multiple (clic, ⌘-clic, ⇧-clic, flèches), glisser une ou plusieurs lignes pour les réordonner ensemble,
/// dépôt de fichiers depuis le Finder, touche Supprimer. C'est AppKit qui gère la sélection et le glissement.
struct OrderList: NSViewRepresentable {
    @Binding var urls: [URL]
    @Binding var selection: IndexSet
    var thumbs: [URL: NSImage]
    var accepts: Set<String>                // extensions acceptées au dépôt de fichiers

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = ReorderTable()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 44
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.draggingDestinationFeedbackStyle = .gap
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.registerForDraggedTypes([Coordinator.rowType, .fileURL])
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.onDelete = { [weak c = context.coordinator] in c?.deleteSelected() }
        context.coordinator.table = table
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let table = c.table else { return }
        if c.shownURLs != urls || c.shownThumbCount != thumbs.count {
            c.shownURLs = urls; c.shownThumbCount = thumbs.count
            table.reloadData()
        }
        let wanted = selection.filteredIndexSet { $0 < urls.count }
        if table.selectedRowIndexes != wanted { table.selectRowIndexes(wanted, byExtendingSelection: false) }
    }

    /// Déplace les lignes `rows` (triées) devant la ligne `row` de la liste d'origine, en gardant leur ordre. Retourne la liste et la plage déplacée.
    static func move<T>(_ items: [T], rows: [Int], to row: Int) -> ([T], Range<Int>) {
        var out = items
        let moved = rows.map { items[$0] }
        let above = rows.filter { $0 < row }.count
        for i in rows.reversed() { out.remove(at: i) }
        let at = min(max(row - above, 0), out.count)
        out.insert(contentsOf: moved, at: at)
        return (out, at..<(at + moved.count))
    }

    final class ReorderTable: NSTableView {
        var onDelete: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
        }
    }

    final class OrderCell: NSTableCellView {
        let num = NSTextField(labelWithString: ""), name = NSTextField(labelWithString: ""), thumb = NSImageView()
        override init(frame: NSRect) {
            super.init(frame: frame)
            num.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); num.textColor = .secondaryLabelColor; num.alignment = .right
            name.font = .systemFont(ofSize: 13); name.lineBreakMode = .byTruncatingMiddle
            thumb.imageScaling = .scaleProportionallyUpOrDown; thumb.wantsLayer = true; thumb.layer?.cornerRadius = 3; thumb.layer?.masksToBounds = true
            textField = name
            for v in [num, thumb, name] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
            NSLayoutConstraint.activate([
                num.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), num.widthAnchor.constraint(equalToConstant: 24), num.centerYAnchor.constraint(equalTo: centerYAnchor),
                thumb.leadingAnchor.constraint(equalTo: num.trailingAnchor, constant: 8), thumb.widthAnchor.constraint(equalToConstant: 44),
                thumb.heightAnchor.constraint(equalToConstant: 30), thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
                name.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10), name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                name.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError() }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let rowType = NSPasteboard.PasteboardType("com.mandarine.order-row")
        var parent: OrderList
        weak var table: NSTableView?
        var shownURLs: [URL] = []
        var shownThumbCount = -1
        init(_ p: OrderList) { parent = p }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.urls.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("cell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? OrderCell) ?? { let c = OrderCell(frame: .zero); c.identifier = id; return c }()
            let u = parent.urls[row]
            cell.num.stringValue = "\(row + 1)"
            cell.name.stringValue = u.lastPathComponent
            cell.thumb.image = parent.thumbs[u] ?? NSWorkspace.shared.icon(forFile: u.path)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let t = table else { return }
            let s = t.selectedRowIndexes
            DispatchQueue.main.async { if self.parent.selection != s { self.parent.selection = s } }
        }

        // MARK: Glisser
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            let item = NSPasteboardItem()
            item.setString(String(row), forType: Self.rowType)
            return item
        }

        private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
            let all = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            return all.filter { parent.accepts.contains($0.pathExtension.lowercased()) }
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            if (info.draggingSource as? NSTableView) === tableView, info.draggingPasteboard.types?.contains(Self.rowType) == true {
                tableView.setDropRow(row, dropOperation: .above); return .move
            }
            if !droppedFiles(info).isEmpty { tableView.setDropRow(row, dropOperation: .above); return .copy }
            return []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            var urls = parent.urls
            if (info.draggingSource as? NSTableView) === tableView {
                let idx = (info.draggingPasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: Self.rowType).flatMap { Int($0) } }
                    .filter { urls.indices.contains($0) }.sorted()
                guard !idx.isEmpty else { return false }
                let (result, range) = OrderList.move(urls, rows: idx, to: row)
                parent.urls = result
                parent.selection = IndexSet(integersIn: range)     // la sélection suit les lignes déplacées
                return true
            }
            let files = droppedFiles(info)
            guard !files.isEmpty else { return false }
            let at = min(max(row, 0), urls.count)
            urls.insert(contentsOf: files, at: at)
            parent.urls = urls
            parent.selection = IndexSet(integersIn: at..<(at + files.count))
            return true
        }

        func deleteSelected() {
            guard let t = table, !t.selectedRowIndexes.isEmpty else { return }
            var urls = parent.urls
            for i in t.selectedRowIndexes.reversed() where urls.indices.contains(i) { urls.remove(at: i) }
            parent.urls = urls
            parent.selection = []
        }
    }
}

/// Éditeur d'ordre complet : compteur, Add…, Remove, liste, aide. Utilisé par Merge PDFs et Join Videos.
struct OrderEditor: View {
    @Binding var urls: [URL]
    var thumbs: [URL: NSImage]
    var accepts: Set<String>
    var noun: String                    // « document », « video »
    var types: [UTType]
    var width: CGFloat = 420
    var height: CGFloat = 264
    @State private var selection = IndexSet()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(urls.count) \(noun)\(urls.count == 1 ? "" : "s")" + (selection.count > 1 ? " · \(selection.count) selected" : "")).sectionLabel()
                Spacer()
                Button("Add…") { Pickers.files(types) { picked in urls.append(contentsOf: picked) } }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.orange)
                Button("Remove") { remove() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selection.isEmpty ? Theme.muted.opacity(0.5) : Theme.orange).disabled(selection.isEmpty)
            }
            OrderList(urls: $urls, selection: $selection, thumbs: thumbs, accepts: accepts)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.1)))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Drag a row to reorder it. ⌘-click or ⇧-click to select several, then drag them together. Drop files from Finder to add them. Delete removes the selection.")
                .sectionLabel().fixedSize(horizontal: false, vertical: true)
        }.frame(width: width, alignment: .leading)
    }

    private func remove() {
        for i in selection.reversed() where urls.indices.contains(i) { urls.remove(at: i) }
        selection = []
    }
}

/// Vignettes de la première page de PDF.
enum PDFThumbs {
    static func load(_ urls: [URL]) async -> [URL: NSImage] {
        await Task.detached {
            var out: [URL: NSImage] = [:]
            for u in urls where out[u] == nil {
                if let doc = PDFDocument(url: u), let p = doc.page(at: 0) { out[u] = p.thumbnail(of: CGSize(width: 88, height: 60), for: .mediaBox); withExtendedLifetime(doc) {} }
            }
            return out
        }.value
    }
}
