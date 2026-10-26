import SwiftUI

/// Scan de document : corrige la perspective d'une photo de feuille, nettoie l'éclairage, et enregistre un PDF (plusieurs pages possibles).
struct ScanTool: View {
    let urls: [URL]
    let close: () -> Void

    private struct Page: Identifiable {
        let id = UUID()
        let url: URL
        var image: CGImage
        var corners: [CGPoint]
    }

    @State private var pages: [Page] = []
    @State private var index = 0
    @State private var filter: ScanFilter = .color
    @State private var showResult = false
    @State private var result: NSImage?
    @State private var loading = true

    var body: some View {
        ToolShell(title: "Scan Document", close: close) {
            VStack(spacing: 12) {
                ZStack {
                    Color.black.opacity(0.06)
                    if loading {
                        ProgressView("Looking for the sheet…")
                    } else if showResult, let r = result {
                        Image(nsImage: r).resizable().scaledToFit().padding(8)
                    } else if pages.indices.contains(index) {
                        CornerEditor(image: pages[index].image, corners: Binding(get: { pages[index].corners }, set: { pages[index].corners = $0; result = nil }))
                    }
                }
                .frame(width: 520, height: 400).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Picker("", selection: $showResult) { Text("Corners").tag(false); Text("Result").tag(true) }
                        .pickerStyle(.segmented).frame(width: 170).labelsHidden()
                    Spacer()
                    if pages.count > 1 {
                        Button { index = max(0, index - 1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(index == 0)
                        Text("Page \(index + 1) of \(pages.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.muted)
                        Button { index = min(pages.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).disabled(index == pages.count - 1)
                    }
                }
                HStack {
                    Text("Filter").sectionLabel()
                    Spacer()
                    Picker("", selection: $filter) { ForEach(ScanFilter.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 300).labelsHidden()
                }
                Text("Drag the corners onto the sheet if the detection missed. Each photo becomes a page.").sectionLabel()
            }.frame(width: 520)
        } footer: {
            Button("Save as Images") { save(pdf: false) }.buttonStyle(PillButtonStyle()).disabled(loading || pages.isEmpty)
            Button(pages.count > 1 ? "Save PDF (\(pages.count) pages)" : "Save PDF") { save(pdf: true) }.buttonStyle(PillButtonStyle()).disabled(loading || pages.isEmpty)
        }
        .task { await load() }
        .task(id: renderKey) { await renderPreview() }
    }

    private var renderKey: String {
        guard showResult, pages.indices.contains(index) else { return "-" }
        return "\(index)|\(filter.rawValue)|" + pages[index].corners.map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }

    private func load() async {
        var loaded: [Page] = []
        for u in urls {
            let page = await Task.detached { () -> Page? in
                guard let (img, _) = try? ImageEngine.load(u, maxSide: 3000) else { return nil }
                return Page(url: u, image: img, corners: DocumentScanner.detectCorners(img))
            }.value
            if let p = page { loaded.append(p) }
        }
        pages = loaded
        loading = false
    }

    private func renderPreview() async {
        guard showResult, pages.indices.contains(index) else { return }
        let (img, c, f) = (pages[index].image, pages[index].corners, filter)
        let out = await Task.detached { DocumentScanner.render(img, corners: c, filter: f, maxSide: 1400) }.value
        if let out = out { result = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)) }
    }

    private func save(pdf: Bool) {
        let items = pages.map { ($0.url, $0.image, $0.corners) }, f = filter
        guard let first = items.first?.0 else { return }
        close()
        Dispatcher.job("Scanning…") { progress in
            let outs: [(URL, CGImage)] = try await Task.detached {
                try items.enumerated().map { i, it in
                    guard let img = DocumentScanner.render(it.1, corners: it.2, filter: f, maxSide: 3000) else { throw MandarineError("Couldn't scan \(it.0.lastPathComponent).") }
                    progress(Double(i + 1) / Double(items.count) * 0.8)
                    return (it.0, img)
                }
            }.value
            if pdf {
                let out = OutputNaming.sibling(of: first, suffix: " scan", ext: "pdf")
                try ImageEngine.writePDF(images: outs.map { ($0.1, [kCGImagePropertyDPIWidth as String: 200.0] as [String: Any]) }, to: out)
                return [out]
            }
            return try outs.map { u, img in
                let out = OutputNaming.sibling(of: u, suffix: " scan", ext: "jpg")
                try ImageEngine.write(img, to: out, ext: "jpg")
                return out
            }
        }
    }
}

/// Photo avec un quadrilatère à quatre poignées déplaçables.
struct CornerEditor: View {
    let image: CGImage
    @Binding var corners: [CGPoint]          // normalisés, origine en haut à gauche
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geo in
            let box = fit(CGSize(width: image.width, height: image.height), in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY)
                Path { p in
                    let pts = corners.map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
                }
                .fill(Theme.orange.opacity(0.14))
                Path { p in
                    let pts = corners.map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
                }
                .stroke(Theme.orange, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                ForEach(0..<corners.count, id: \.self) { i in
                    Circle().fill(Color.white).frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Theme.orange, lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: box.minX + corners[i].x * box.width, y: box.minY + corners[i].y * box.height)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("scan")).onChanged { v in
                            corners[i] = CGPoint(x: min(max((v.location.x - box.minX) / box.width, 0), 1), y: min(max((v.location.y - box.minY) / box.height, 0), 1))
                        })
                }
            }
            .coordinateSpace(name: "scan")
        }
    }

    private func fit(_ size: CGSize, in box: CGSize) -> CGRect {
        let s = min(box.width / size.width, box.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }
}
