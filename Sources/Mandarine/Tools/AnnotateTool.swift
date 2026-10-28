import SwiftUI
import AppKit

enum AnnotationKind: CaseIterable {
    case arrow, pen, text, rect, ellipse, highlighter, number, magnifier, image
    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.left"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .highlighter: return "highlighter"
        case .number: return "1.circle"
        case .magnifier: return "plus.magnifyingglass"
        case .image: return "photo.badge.plus"
        }
    }
    var hint: String {
        switch self {
        case .arrow: return "Drag from the tail toward the arrowhead. Drag an annotation to move it."
        case .pen: return "Draw freely on the photo."
        case .text: return "Click to place text, then type below."
        case .rect: return "Drag to draw a rectangle."
        case .ellipse: return "Drag to draw an ellipse."
        case .highlighter: return "Draw to highlight."
        case .number: return "Click to place the next numbered callout."
        case .magnifier: return "Drag to magnify an area."
        case .image: return "Drag to place an image."
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    var points: [CGPoint]            // normalisés
    var color: Color
    var text = ""
    var number = 0
    var image: NSImage?
}

enum AnnotationRenderer {
    /// Dessine toutes les annotations dans un contexte de taille `size` (px ou pt).
    static func draw(_ anns: [Annotation], in ctx: inout GraphicsContext, size: CGSize, base: NSImage?) {
        let unit = max(size.width, size.height) / 600
        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        for a in anns {
            guard let f = a.points.first else { continue }
            let l = a.points.last ?? f
            let lw = 3.5 * unit
            switch a.kind {
            case .arrow:
                var p = Path(); p.move(to: P(f)); p.addLine(to: P(l))
                ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                let ang = atan2(P(l).y - P(f).y, P(l).x - P(f).x), hl = 16 * unit
                var h = Path()
                h.move(to: P(l))
                h.addLine(to: CGPoint(x: P(l).x - hl * cos(ang - .pi / 6), y: P(l).y - hl * sin(ang - .pi / 6)))
                h.move(to: P(l))
                h.addLine(to: CGPoint(x: P(l).x - hl * cos(ang + .pi / 6), y: P(l).y - hl * sin(ang + .pi / 6)))
                ctx.stroke(h, with: .color(a.color), style: StrokeStyle(lineWidth: lw, lineCap: .round))
            case .pen, .highlighter:
                var p = Path(); p.move(to: P(f)); for q in a.points.dropFirst() { p.addLine(to: P(q)) }
                let hi = a.kind == .highlighter
                ctx.stroke(p, with: .color(hi ? a.color.opacity(0.4) : a.color), style: StrokeStyle(lineWidth: hi ? lw * 4 : lw, lineCap: .round, lineJoin: .round))
            case .rect, .ellipse:
                let r = rect(f, l, size)
                let p = a.kind == .rect ? Path(roundedRect: r, cornerRadius: 3 * unit) : Path(ellipseIn: r)
                ctx.stroke(p, with: .color(a.color), style: StrokeStyle(lineWidth: lw))
            case .text:
                let t = Text(a.text.isEmpty ? "Text" : a.text).font(.system(size: 22 * unit, weight: .bold)).foregroundColor(a.color)
                ctx.draw(ctx.resolve(t), at: P(f), anchor: .topLeading)
            case .number:
                let d = 30 * unit
                let c = Path(ellipseIn: CGRect(x: P(f).x - d / 2, y: P(f).y - d / 2, width: d, height: d))
                ctx.fill(c, with: .color(a.color))
                ctx.stroke(c, with: .color(.white), style: StrokeStyle(lineWidth: 2 * unit))
                ctx.draw(ctx.resolve(Text("\(a.number)").font(.system(size: 16 * unit, weight: .bold)).foregroundColor(.white)), at: P(f), anchor: .center)
            case .magnifier:
                let r = rect(f, l, size)
                let d = max(r.width, r.height)
                let circle = Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d))
                if let base = base {
                    var c2 = ctx
                    c2.clip(to: circle)
                    c2.translateBy(x: r.midX, y: r.midY); c2.scaleBy(x: 2, y: 2); c2.translateBy(x: -r.midX, y: -r.midY)
                    c2.draw(Image(nsImage: base), in: CGRect(origin: .zero, size: size))
                }
                ctx.stroke(circle, with: .color(a.color), style: StrokeStyle(lineWidth: lw))
            case .image:
                let r = rect(f, l, size)
                if let img = a.image { ctx.draw(Image(nsImage: img), in: r) }
            }
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint, _ s: CGSize) -> CGRect {
        CGRect(x: min(a.x, b.x) * s.width, y: min(a.y, b.y) * s.height, width: abs(a.x - b.x) * s.width, height: abs(a.y - b.y) * s.height)
    }

    static func bounds(_ a: Annotation) -> CGRect {
        let xs = a.points.map(\.x), ys = a.points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return .zero }
        var r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        if a.kind == .text { r.size = CGSize(width: max(r.width, 0.2), height: max(r.height, 0.06)) }
        if a.kind == .number { r = r.insetBy(dx: -0.03, dy: -0.03) }
        return r.insetBy(dx: -0.015, dy: -0.015)
    }
}

struct AnnotateTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource
    @State private var tool = AnnotationKind.arrow
    @State private var anns: [Annotation] = []
    @State private var color = Color(red: 0.88, green: 0.3, blue: 0.27)
    @State private var selected: UUID?
    @State private var dragMove: (UUID, [CGPoint], CGPoint)?
    @State private var nextNumber = 1
    @State private var pickedImage: NSImage?

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
    }

    var body: some View {
        ToolShell(title: "Annotate Photo", close: close) {
            VStack(spacing: 12) {
                canvas.frame(width: 420, height: 420)
                HStack(spacing: 4) {
                    ForEach(AnnotationKind.allCases, id: \.self) { k in
                        Image(systemName: k.symbol).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(tool == k ? .white : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tool == k ? Theme.orange : Color.black.opacity(0.07)))
                            .onTapGesture { tool = k; if k == .image { pickImage() } }
                    }
                }
                HStack {
                    ColorPicker("", selection: $color).labelsHidden()
                    if let i = anns.firstIndex(where: { $0.id == selected }), anns[i].kind == .text {
                        TextField("Text", text: $anns[i].text).textFieldStyle(.roundedBorder)
                    }
                    Spacer()
                    smallButton("arrow.uturn.backward", enabled: !anns.isEmpty) { _ = anns.popLast() }
                    smallButton("trash", enabled: selected != nil) { anns.removeAll { $0.id == selected }; selected = nil }
                }
                Text(tool.hint).font(.system(size: 11)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 420)
        } footer: {
            Button("Reset") { anns = []; nextNumber = 1; selected = nil }.buttonStyle(PillButtonStyle())
            Button("Save Annotated Copy") { save() }.buttonStyle(PillButtonStyle())
        }
    }

    private func smallButton(_ name: String, enabled: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: name).frame(width: 30, height: 22) }.buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.07))).opacity(enabled ? 1 : 0.35).disabled(!enabled)
    }

    private var canvas: some View {
        GeometryReader { geo in
            let fit = fitRect(src.pixelSize, geo.size)
            ZStack {
                Theme.previewBG
                if let p = src.preview {
                    Image(nsImage: p).resizable().frame(width: fit.width, height: fit.height).position(x: fit.midX, y: fit.midY)
                    Canvas { ctx, size in
                        var c = ctx
                        c.translateBy(x: fit.minX, y: fit.minY)
                        AnnotationRenderer.draw(anns, in: &c, size: fit.size, base: p)
                        if let s = anns.first(where: { $0.id == selected }) {
                            let b = AnnotationRenderer.bounds(s)
                            c.stroke(Path(CGRect(x: b.minX * fit.width, y: b.minY * fit.height, width: b.width * fit.width, height: b.height * fit.height)),
                                     with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in drag(v, fit) }.onEnded { _ in dragMove = nil; finishDrag() })
        }
    }

    private func fitRect(_ s: CGSize, _ box: CGSize) -> CGRect {
        guard s.width > 0 else { return CGRect(origin: .zero, size: box) }
        let k = min(box.width / s.width, box.height / s.height)
        return CGRect(x: (box.width - s.width * k) / 2, y: (box.height - s.height * k) / 2, width: s.width * k, height: s.height * k)
    }

    @State private var creating: UUID?

    private func drag(_ v: DragGesture.Value, _ fit: CGRect) {
        let n = { (p: CGPoint) in CGPoint(x: min(1, max(0, (p.x - fit.minX) / fit.width)), y: min(1, max(0, (p.y - fit.minY) / fit.height))) }
        let cur = n(v.location), start = n(v.startLocation)
        if creating == nil && dragMove == nil {
            if let hit = anns.last(where: { AnnotationRenderer.bounds($0).contains(start) }) {
                dragMove = (hit.id, hit.points, start); selected = hit.id
            } else {
                var a = Annotation(kind: tool, points: [start], color: color)
                if tool == .number { a.number = nextNumber; nextNumber += 1 }
                if tool == .image { a.image = pickedImage }
                if [.arrow, .rect, .ellipse, .magnifier, .image].contains(tool) { a.points.append(start) }
                anns.append(a); creating = a.id; selected = a.id
            }
        }
        if let (id, orig, s) = dragMove, let i = anns.firstIndex(where: { $0.id == id }) {
            let dx = cur.x - s.x, dy = cur.y - s.y
            anns[i].points = orig.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        } else if let id = creating, let i = anns.firstIndex(where: { $0.id == id }) {
            switch anns[i].kind {
            case .pen, .highlighter: anns[i].points.append(cur)
            case .text, .number: break
            default: anns[i].points[1] = cur
            }
        }
    }

    private func finishDrag() { creating = nil }

    private func pickImage() {
        Pickers.image { u in if let u = u { pickedImage = NSImage(contentsOf: u) } }
    }

    @MainActor private func save() {
        let list = anns, file = urls[0]
        close()
        Dispatcher.job("Saving annotated copy…", light: true) { _ in
            try await MainActor.run {
                let (cg, props) = try ImageEngine.load(file)
                let size = CGSize(width: cg.width, height: cg.height)
                let ns = NSImage(cgImage: cg, size: size)
                let view = ZStack {
                    Image(nsImage: ns).resizable().frame(width: size.width, height: size.height)
                    Canvas { ctx, s in var c = ctx; AnnotationRenderer.draw(list, in: &c, size: s, base: ns) }
                        .frame(width: size.width, height: size.height)
                }.frame(width: size.width, height: size.height)
                let r = ImageRenderer(content: view); r.scale = 1
                guard let out = r.cgImage else { throw MandarineError("Rendu impossible.") }
                let dest = OutputNaming.sibling(of: file, suffix: " annotated")
                try ImageEngine.write(out, properties: props, to: dest, ext: file.pathExtension, quality: 0.95)
                return [dest]
            }
        }
    }
}
