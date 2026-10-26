import SwiftUI
import PDFKit

struct MergePDFTool: View {
    @State var urls: [URL]
    let close: () -> Void
    @State private var thumbs: [URL: NSImage] = [:]
    var body: some View {
        ToolShell(title: "Merge PDFs", close: close) {
            OrderEditor(urls: $urls, thumbs: thumbs, accepts: ["pdf"], noun: "document", types: [.pdf])
        } footer: {
            Button("Merge PDFs") {
                let files = urls
                close()
                Dispatcher.job("Merging PDFs…", light: true) { _ in
                    let out = OutputNaming.sibling(of: files[0], suffix: " merged")
                    try await Task.detached { try PDFEngine.merge(files, to: out) }.value
                    return [out]
                }
            }.buttonStyle(PillButtonStyle()).disabled(urls.count < 2)
        }
        .task(id: urls) {
            let missing = urls.filter { thumbs[$0] == nil }
            if !missing.isEmpty { thumbs.merge(await PDFThumbs.load(missing)) { $1 } }
        }
    }
}

// MARK: Organize
struct PDFPageItem: Identifiable, Equatable {
    let id = UUID()
    let sourceIndex: Int
    var rotation = 0
}

final class OrganizeModel: ObservableObject {
    let doc: PDFDocument
    @Published var pages: [PDFPageItem]
    @Published var sameWidth = false
    @Published var thumbs: [Int: NSImage] = [:]
    let original: [Int]
    init(url: URL) {
        doc = PDFDocument(url: url) ?? PDFDocument()
        pages = (0..<doc.pageCount).map { PDFPageItem(sourceIndex: $0) }
        original = Array(0..<doc.pageCount)
    }
    func thumb(_ i: Int) -> NSImage? {
        if let t = thumbs[i] { return t }
        DispatchQueue.global().async {
            if let p = self.doc.page(at: i) {
                let img = p.thumbnail(of: CGSize(width: 240, height: 320), for: .mediaBox)
                DispatchQueue.main.async { self.thumbs[i] = img }
            }
        }
        return nil
    }
    var isModified: Bool { pages.map(\.sourceIndex) != original || pages.contains { $0.rotation != 0 } || sameWidth }
}

struct OrganizePDFTool: View {
    let url: URL
    let close: () -> Void
    @StateObject private var m: OrganizeModel
    @State private var dragging: UUID?

    init(url: URL, close: @escaping () -> Void) {
        self.url = url; self.close = close
        _m = StateObject(wrappedValue: OrganizeModel(url: url))
    }

    var body: some View {
        ToolShell(title: "Organize PDF", close: close) {
            VStack(spacing: 12) {
                HStack {
                    Text("\(m.pages.count) page\(m.pages.count == 1 ? "" : "s")").sectionLabel()
                    Spacer()
                    Button("Reset Order") { m.pages = (0..<m.doc.pageCount).map { PDFPageItem(sourceIndex: $0) } }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(m.isModified ? Theme.text : Theme.muted.opacity(0.5))
                        .disabled(!m.isModified)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(Array(m.pages.enumerated()), id: \.element.id) { n, p in card(n, p) }
                    }.padding(4)
                }.frame(height: 360)
                Divider()
                Toggle("Make all pages the same width", isOn: $m.sameWidth)
                Text("Pages are scaled proportionally to match the narrowest page; their heights may still differ.").sectionLabel()
            }.frame(width: 560, alignment: .leading)
        } footer: {
            Button("Save Organized PDF") { save() }.buttonStyle(PillButtonStyle()).disabled(m.pages.isEmpty)
        }
    }

    private func card(_ n: Int, _ p: PDFPageItem) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            Group {
                if let t = m.thumb(p.sourceIndex) {
                    Image(nsImage: t).resizable().scaledToFit().rotationEffect(.degrees(Double(p.rotation)))
                } else { ProgressView().controlSize(.small) }
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(n + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.orange)).padding(6)
            HStack(spacing: 4) {
                iconButton("rotate.right") { m.pages[n].rotation = (m.pages[n].rotation + 90) % 360 }
                iconButton("plus.square.on.square") { m.pages.insert(PDFPageItem(sourceIndex: p.sourceIndex, rotation: p.rotation), at: n + 1) }
                iconButton("trash") { m.pages.remove(at: n) }
            }.frame(maxWidth: .infinity, alignment: .trailing).padding(6)
        }
        .frame(height: 160)
        .opacity(dragging == p.id ? 0.4 : 1)
        .onDrag { dragging = p.id; return NSItemProvider(object: p.id.uuidString as NSString) }
        .onDrop(of: [.text], delegate: PageDropDelegate(target: p, model: m, dragging: $dragging))
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Color.black.opacity(0.55)))
        }.buttonStyle(.plain)
    }

    private func save() {
        let items = m.pages, doc = m.doc, same = m.sameWidth, file = url
        close()
        Dispatcher.job("Saving PDF…", light: true) { _ in
            let out = OutputNaming.sibling(of: file, suffix: " organized")
            try await Task.detached {
                let result = PDFDocument()
                var widths: [CGFloat] = []
                for (k, it) in items.enumerated() {
                    guard let page = doc.page(at: it.sourceIndex)?.copy() as? PDFPage else { continue }
                    page.rotation = (page.rotation + it.rotation) % 360
                    result.insert(page, at: k)
                    let b = page.bounds(for: .mediaBox)
                    widths.append(page.rotation % 180 == 0 ? b.width : b.height)
                }
                if same, let minW = widths.min(), minW > 0 {
                    for k in 0..<result.pageCount {
                        guard let page = result.page(at: k) else { continue }
                        let s = minW / widths[k]
                        let b = page.bounds(for: .mediaBox)
                        // met à l'échelle via la crop box
                        page.setBounds(CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height), for: .cropBox)
                        if s != 1 { page.setBounds(CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height), for: .mediaBox) }
                    }
                }
                guard result.write(to: out) else { throw MandarineError("Écriture impossible.") }
            }.value
            return [out]
        }
    }
}

struct PageDropDelegate: DropDelegate {
    let target: PDFPageItem
    let model: OrganizeModel
    @Binding var dragging: UUID?
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target.id,
              let from = model.pages.firstIndex(where: { $0.id == d }),
              let to = model.pages.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeOut(duration: 0.15)) { model.pages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
