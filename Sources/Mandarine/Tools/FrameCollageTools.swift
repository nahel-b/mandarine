import SwiftUI
import AppKit

// MARK: Add BG
enum BGChoice: Hashable {
    case gradient(Int), color(Int), image
}

enum BGPresets {
    static let gradients: [[Color]] = [
        [Color(red: 0.96, green: 0.36, blue: 0.16), Color(red: 0.98, green: 0.78, blue: 0.3)],
        [Color(red: 0.85, green: 0.9, blue: 1), Color.white],
        [Color(red: 0.98, green: 0.55, blue: 0.6), Color(red: 0.55, green: 0.7, blue: 1), Color(red: 1, green: 0.9, blue: 0.4)],
        [Color(red: 0.7, green: 0.55, blue: 0.95), Color(red: 0.98, green: 0.7, blue: 0.85)],
        [Color(red: 0.95, green: 0.7, blue: 0.9), Color(red: 0.8, green: 0.85, blue: 1)],
        [Color(red: 0.1, green: 0.55, blue: 0.45), Color(red: 0.95, green: 0.4, blue: 0.2)],
        [Color(red: 0.4, green: 0.7, blue: 1), Color(red: 0.7, green: 0.95, blue: 0.9)],
        [Color(red: 0.2, green: 0.7, blue: 0.8), Color(red: 0.7, green: 0.95, blue: 0.95)],
        [Color(red: 0.1, green: 0.1, blue: 0.2), Color(red: 0.4, green: 0.2, blue: 0.6)]
    ]
    static let colors: [Color] = [.white, Color(red: 0.95, green: 0.8, blue: 0.35), Color(red: 0.7, green: 0.85, blue: 0.45),
                                  Color(red: 0.35, green: 0.62, blue: 0.45), Color(red: 0.3, green: 0.6, blue: 0.55),
                                  Color(red: 0.5, green: 0.8, blue: 0.9), Color(red: 0.25, green: 0.4, blue: 0.8),
                                  Color(red: 0.2, green: 0.25, blue: 0.4), Color(red: 0.55, green: 0.35, blue: 0.8), .black]
}

struct FrameParams: Equatable {
    var bg: BGChoice = .gradient(0)
    var padding: Double = 0.1       // fraction du plus grand côté
    var corners: Double = 0.03
    var shadow: Double = 0.4
    var ratio: CGFloat? = nil
    var customColor: Color? = nil
}

/// Composition partagée par l'aperçu et l'export : l'image sur un fond, avec marge, coins arrondis et ombre.
struct FrameComposition: View {
    let image: NSImage
    let bgImage: NSImage?
    let params: FrameParams
    let size: CGSize

    var body: some View {
        let side = max(image.size.width, image.size.height)
        let pad = params.padding * side
        let natural = CGSize(width: image.size.width + pad * 2, height: image.size.height + pad * 2)
        ZStack {
            background.frame(width: size.width, height: size.height)
            let scale = min(size.width / natural.width, size.height / natural.height)
            let w = image.size.width * scale, h = image.size.height * scale
            Image(nsImage: image).resizable().frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: params.corners * max(w, h), style: .continuous))
                .shadow(color: .black.opacity(params.shadow * 0.55), radius: params.shadow * 0.06 * max(w, h), y: params.shadow * 0.02 * max(w, h))
        }
        .frame(width: size.width, height: size.height).clipped()
    }

    @ViewBuilder private var background: some View {
        switch params.bg {
        case .gradient(let i): LinearGradient(colors: BGPresets.gradients[i], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .color(let i): (params.customColor ?? BGPresets.colors[i])
        case .image:
            if let b = bgImage { Image(nsImage: b).resizable().scaledToFill() } else { Color.gray }
        }
    }

    static func canvasSize(for image: CGSize, params: FrameParams) -> CGSize {
        let side = max(image.width, image.height)
        let pad = params.padding * side
        var w = image.width + pad * 2, h = image.height + pad * 2
        if let r = params.ratio {
            if w / h > r { h = w / r } else { w = h * r }
        }
        return CGSize(width: w.rounded(), height: h.rounded())
    }
}

struct FrameImageTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource
    @State private var p = FrameParams()
    @State private var bgImage: NSImage?
    @State private var ratioChoice = 0
    @State private var customColor = Color.white
    @State private var cutEnabled = false          // « Remove BG » d'abord, puis on pose le nouveau fond
    @State private var cutPreview: NSImage?
    @State private var cutting = false

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
    }

    private let ratios: [(String, CGFloat?)] = [("Auto", nil), ("1:1", 1), ("16:9", 16.0 / 9), ("4:5", 4.0 / 5)]

    var body: some View {
        ToolShell(title: "Add BG", close: close) {
            VStack(spacing: 12) {
                if let img = (cutEnabled ? cutPreview : nil) ?? src.preview {
                    let cs = FrameComposition.canvasSize(for: img.size, params: p)
                    ZStack {
                        Color.black.opacity(0.04)
                        FrameComposition(image: img, bgImage: bgImage, params: p, size: cs)
                            .scaleEffect(min(1, min(400 / cs.width, 300 / cs.height)))
                    }.frame(width: 400, height: 300).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack {
                    Toggle(isOn: Binding(get: { cutEnabled }, set: { setCut($0) })) {
                        Label(cutting ? "Removing background…" : "Remove the original background first", systemImage: "wand.and.stars").font(.system(size: 12))
                    }.disabled(!BackgroundRemover.isAvailable || cutting)
                    if cutting { ProgressView().controlSize(.small) }
                    Spacer()
                }
                HStack(alignment: .top) {
                    Text("Background").sectionLabel().frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(0..<BGPresets.gradients.count, id: \.self) { i in swatch(.gradient(i)) { LinearGradient(colors: BGPresets.gradients[i], startPoint: .topLeading, endPoint: .bottomTrailing) } }
                            Button { pickImage() } label: { Image(systemName: "photo").frame(width: 24, height: 24) }
                                .buttonStyle(.plain)
                        }
                        HStack(spacing: 6) {
                            ForEach(0..<BGPresets.colors.count, id: \.self) { i in swatch(.color(i)) { BGPresets.colors[i] } }
                            ColorPicker("", selection: Binding(get: { customColor }, set: { customColor = $0; p.customColor = $0; p.bg = .color(0) })).labelsHidden()
                        }
                    }
                }
                slider("Padding", $p.padding, 0...0.4, "%.0f px") { Int($0 * Double(max(src.pixelSize.width, src.pixelSize.height))) }
                slider("Corners", $p.corners, 0...0.15, "%.0f px") { Int($0 * Double(max(src.pixelSize.width, src.pixelSize.height))) }
                slider("Shadow", $p.shadow, 0...1, "%.0f px") { Int($0 * 60) }
                HStack {
                    Text("Ratio").sectionLabel().frame(width: 70, alignment: .leading)
                    Spacer()
                    PillPicker(options: ratios.enumerated().map { ($0.offset, $0.element.0) }, selection: Binding(get: { ratioChoice }, set: { ratioChoice = $0; p.ratio = ratios[$0].1 }))
                }
            }.frame(width: 400)
        } footer: {
            Button("Reset") { p = FrameParams(); ratioChoice = 0; bgImage = nil; cutEnabled = false }.buttonStyle(PillButtonStyle())
            Spacer()
            Button("Save with Background") { save() }.buttonStyle(PillButtonStyle())
        }
    }

    private func swatch<S: View>(_ c: BGChoice, @ViewBuilder _ fill: () -> S) -> some View {
        fill().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(p.bg == c && p.customColor == nil ? Theme.orange : Color.black.opacity(0.1), lineWidth: p.bg == c && p.customColor == nil ? 2 : 1))
            .onTapGesture { p.bg = c; p.customColor = nil }
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ f: String, _ display: @escaping (Double) -> Int) -> some View {
        HStack {
            Text(title).sectionLabel().frame(width: 70, alignment: .leading)
            Slider(value: v, in: r).controlSize(.mini)
            Text("\(display(v.wrappedValue)) px").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 60, alignment: .trailing)
        }
    }

    /// Active / désactive le détourage : calculé sur l'aperçu (rapide), appliqué en pleine résolution à l'enregistrement.
    private func setCut(_ on: Bool) {
        cutEnabled = on
        guard on, cutPreview == nil, let cg = src.preview?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        cutting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = try? BackgroundRemover.cutout(cg)
            DispatchQueue.main.async {
                cutting = false
                if let out = out { cutPreview = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height)) }
                else { cutEnabled = false; Toast.shared.fail("No subject found", subtitle: "The background couldn't be removed from this image.") }
            }
        }
    }

    private func pickImage() {
        Pickers.image { u in
            if let u = u, let (cg, _) = try? ImageEngine.load(u, maxSide: 2400) {
                bgImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)); p.bg = .image
            }
        }
    }

    @MainActor private func save() {
        let params = p, files = urls, bg = bgImage, cut = cutEnabled
        close()
        Dispatcher.job("Adding background…", light: true) { _ in
            try await MainActor.run {
                try files.map { url in
                    var (cg, _) = try ImageEngine.load(url)
                    if cut { cg = try BackgroundRemover.cutout(cg) }
                    let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    let size = FrameComposition.canvasSize(for: ns.size, params: params)
                    let r = ImageRenderer(content: FrameComposition(image: ns, bgImage: bg, params: params, size: size))
                    r.scale = 1
                    guard let out = r.cgImage else { throw MandarineError("Rendu impossible.") }
                    let dest = OutputNaming.sibling(of: url, suffix: " framed", ext: "png")
                    try ImageEngine.write(out, to: dest, ext: "png")
                    return dest
                }
            }
        }
    }
}

// MARK: Collage
enum CollageStyle: String, CaseIterable { case grid = "Grid", row = "Row", column = "Column", featured = "Featured" }

enum CollageLayout {
    static func cells(style: CollageStyle, count n: Int, columns: Int, canvas: CGSize, spacing: CGFloat) -> [CGRect] {
        guard n > 0 else { return [] }
        let W = canvas.width - spacing * 2, H = canvas.height - spacing * 2
        func grid(_ cols: Int, _ rows: Int, in r: CGRect, count: Int) -> [CGRect] {
            let cw = (r.width - spacing * CGFloat(cols - 1)) / CGFloat(cols), ch = (r.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            return (0..<count).map { i in CGRect(x: r.minX + CGFloat(i % cols) * (cw + spacing), y: r.minY + CGFloat(i / cols) * (ch + spacing), width: cw, height: ch) }
        }
        let area = CGRect(x: spacing, y: spacing, width: W, height: H)
        switch style {
        case .grid:
            let cols = max(1, min(columns, n)); let rows = Int(ceil(Double(n) / Double(cols)))
            return grid(cols, rows, in: area, count: n)
        case .row: return grid(n, 1, in: area, count: n)
        case .column: return grid(1, n, in: area, count: n)
        case .featured:
            if n == 1 { return [area] }
            let big = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height * 0.62)
            let rest = CGRect(x: area.minX, y: big.maxY + spacing, width: area.width, height: area.height - big.height - spacing)
            return [big] + grid(n - 1, 1, in: rest, count: n - 1)
        }
    }
}

struct CollageView: View {
    let images: [NSImage]
    let style: CollageStyle, columns: Int
    let size: CGSize
    let spacing: CGFloat, corners: CGFloat
    let fill: Bool
    let background: Color

    var body: some View {
        let cells = CollageLayout.cells(style: style, count: images.count, columns: columns, canvas: size, spacing: spacing)
        ZStack(alignment: .topLeading) {
            background
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                let img = images[i]
                Group {
                    if fill { Image(nsImage: img).resizable().scaledToFill() } else { Image(nsImage: img).resizable().scaledToFit() }
                }
                .frame(width: c.width, height: c.height).clipped()
                .clipShape(RoundedRectangle(cornerRadius: corners, style: .continuous))
                .position(x: c.midX, y: c.midY)
            }
        }.frame(width: size.width, height: size.height)
    }
}

struct CollageTool: View {
    @State var urls: [URL]
    let close: () -> Void
    @State private var style = CollageStyle.grid
    @State private var columns = 2
    @State private var canvasIdx = 0
    @State private var width = 2048
    @State private var fill = true
    @State private var spacing = 0.0
    @State private var corners = 0.0
    @State private var bg = Color.white
    @State private var showSpacing = false
    @State private var showOrder = false
    @State private var images: [URL: NSImage] = [:]

    private let canvases: [(String, CGFloat?)] = [("Square · 1:1", 1), ("Landscape · 16:9", 16.0 / 9), ("Portrait · 9:16", 9.0 / 16), ("Photo · 4:3", 4.0 / 3), ("Portrait · 3:4", 3.0 / 4)]

    private var canvasSize: CGSize {
        let r = canvases[canvasIdx].1 ?? 1
        return CGSize(width: CGFloat(width), height: CGFloat(width) / r)
    }
    private var ordered: [NSImage] { urls.compactMap { images[$0] } }

    var body: some View {
        ToolShell(title: "Create Collage", close: close) {
            VStack(spacing: 10) {
                let cs = canvasSize
                let k = min(380 / cs.width, 300 / cs.height)
                ZStack {
                    Color.black.opacity(0.04)
                    if ordered.count == urls.count {
                        CollageView(images: ordered, style: style, columns: columns, size: cs, spacing: spacing / 100 * cs.width, corners: corners / 100 * cs.width, fill: fill, background: bg)
                            .scaleEffect(k)
                    }
                }.frame(width: 380, height: 300).clipShape(RoundedRectangle(cornerRadius: 8))
                row("Style") { Picker("", selection: $style) { ForEach(CollageStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 150) }
                if style == .grid { row("Columns") { Stepper("\(columns)", value: $columns, in: 1...6).frame(width: 90) } }
                row("Canvas") { Picker("", selection: $canvasIdx) { ForEach(Array(canvases.enumerated()), id: \.offset) { Text($1.0).tag($0) } }.labelsHidden().frame(width: 170) }
                row("Width") { Picker("", selection: $width) { ForEach([1024, 2048, 3072, 4096], id: \.self) { Text("\($0) px").tag($0) } }.labelsHidden().frame(width: 120) }
                row("Image fit") { Picker("", selection: $fill) { Text("Fill cells (crop edges)").tag(true); Text("Fit inside cells").tag(false) }.labelsHidden().frame(width: 190) }
                Divider()
                DisclosureGroup("Spacing & background", isExpanded: $showSpacing) {
                    VStack {
                        row("Spacing") { Slider(value: $spacing, in: 0...8).frame(width: 160) }
                        row("Corners") { Slider(value: $corners, in: 0...10).frame(width: 160) }
                        row("Background") { ColorPicker("", selection: $bg).labelsHidden() }
                    }.padding(.top, 6)
                }
                DisclosureGroup("Image order", isExpanded: $showOrder) {
                    OrderEditor(urls: $urls, thumbs: images, accepts: FileKind.imageExts, noun: "image", types: [.image], width: 380, height: 210).padding(.top, 6)
                }
            }.frame(width: 380).font(.system(size: 12))
        } footer: {
            Button("Reset Layout") { style = .grid; columns = 2; spacing = 0; corners = 0; urls.sort { $0.path < $1.path } }.buttonStyle(PillButtonStyle())
            Spacer()
            Button("Create Collage") { save() }.buttonStyle(PillButtonStyle())
        }
        .task(id: urls) {
            for u in urls where images[u] == nil {
                if let (cg, _) = try? ImageEngine.load(u, maxSide: 1600) { images[u] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
            }
        }
    }

    private func row<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View { HStack { Text(t).foregroundStyle(Theme.muted); Spacer(); v() } }

    @MainActor private func save() {
        let files = urls, cs = canvasSize
        let (st, cols, sp, co, f, b) = (style, columns, spacing, corners, fill, bg)
        close()
        Dispatcher.job("Creating collage…", light: true) { _ in
            try await MainActor.run {
                let imgs: [NSImage] = try files.map { u in
                    let (cg, _) = try ImageEngine.load(u, maxSide: Int(cs.width))
                    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                }
                let r = ImageRenderer(content: CollageView(images: imgs, style: st, columns: cols, size: cs, spacing: sp / 100 * cs.width, corners: co / 100 * cs.width, fill: f, background: b))
                r.scale = 1
                guard let out = r.cgImage else { throw MandarineError("Rendu impossible.") }
                let dest = OutputNaming.sibling(of: files[0], suffix: " collage", ext: "png")
                try ImageEngine.write(out, to: dest, ext: "png")
                return [dest]
            }
        }
    }
}
