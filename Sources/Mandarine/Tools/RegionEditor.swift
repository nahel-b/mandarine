import SwiftUI
import AVFoundation

struct Region: Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect            // normalisé 0…1, origine en haut à gauche
    var start: Double = 0       // pour la vidéo : plage de temps (s)
    var end: Double = .infinity
}

/// Éditeur de rectangles au-dessus d'un contenu (image, vidéo) : déplacer, redimensionner, dessiner.
struct RegionEditor<Content: View>: View {
    let contentSize: CGSize                 // taille en pixels du média (pour le ratio)
    @Binding var regions: [Region]
    @Binding var selected: UUID?
    var lockAspect: CGFloat? = nil          // ratio largeur/hauteur en pixels
    var allowsDraw = false
    var dimOutside = false
    var fillStyle: ((Region) -> AnyView)? = nil
    @ViewBuilder var content: () -> Content

    private enum Handle { case tl, tr, bl, br, t, b, l, r, move }
    @State private var active: (id: UUID, handle: Handle, startRect: CGRect, startPoint: CGPoint)?
    @State private var drawing: (id: UUID, origin: CGPoint)?

    var body: some View {
        GeometryReader { geo in
            let frame = fit(contentSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Theme.previewBG
                content().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                if dimOutside, let r = regions.first {
                    let vr = viewRect(r.rect, frame)
                    Path { p in p.addRect(frame); p.addRect(vr) }
                        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                }
                ForEach(regions) { r in
                    let vr = viewRect(r.rect, frame)
                    ZStack {
                        if let f = fillStyle { f(r).frame(width: vr.width, height: vr.height) }
                        Rectangle().stroke(Theme.orange, lineWidth: selected == r.id || dimOutside ? 2 : 1)
                        if selected == r.id || dimOutside {
                            ForEach([Handle.tl, .tr, .bl, .br], id: \.self) { h in
                                RoundedRectangle(cornerRadius: 2).fill(Theme.orange).frame(width: 9, height: 9)
                                    .position(handlePoint(h, in: CGRect(origin: .zero, size: vr.size)))
                            }
                            ForEach([Handle.t, .b, .l, .r], id: \.self) { h in
                                Capsule().fill(Theme.orange)
                                    .frame(width: h == .t || h == .b ? 18 : 4, height: h == .l || h == .r ? 18 : 4)
                                    .position(handlePoint(h, in: CGRect(origin: .zero, size: vr.size)))
                            }
                        }
                    }
                    .frame(width: vr.width, height: vr.height)
                    .position(x: vr.midX, y: vr.midY)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in onDrag(v, frame) }
                .onEnded { _ in active = nil; drawing = nil })
        }
    }

    // MARK: Géométrie
    private func fit(_ size: CGSize, in box: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: box) }
        let s = min(box.width / size.width, box.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }
    private func viewRect(_ n: CGRect, _ f: CGRect) -> CGRect {
        CGRect(x: f.minX + n.minX * f.width, y: f.minY + n.minY * f.height, width: n.width * f.width, height: n.height * f.height)
    }
    private func handlePoint(_ h: Handle, in r: CGRect) -> CGPoint {
        switch h {
        case .tl: return CGPoint(x: r.minX, y: r.minY)
        case .tr: return CGPoint(x: r.maxX, y: r.minY)
        case .bl: return CGPoint(x: r.minX, y: r.maxY)
        case .br: return CGPoint(x: r.maxX, y: r.maxY)
        case .t: return CGPoint(x: r.midX, y: r.minY)
        case .b: return CGPoint(x: r.midX, y: r.maxY)
        case .l: return CGPoint(x: r.minX, y: r.midY)
        case .r: return CGPoint(x: r.maxX, y: r.midY)
        case .move: return CGPoint(x: r.midX, y: r.midY)
        }
    }

    private func hit(_ p: CGPoint, _ frame: CGRect) -> (UUID, Handle)? {
        let order = regions.reversed()
        for r in order {
            let vr = viewRect(r.rect, frame)
            for h in [Handle.tl, .tr, .bl, .br, .t, .b, .l, .r] {
                if lockAspect != nil && [.t, .b, .l, .r].contains(h) { continue }
                let hp = handlePoint(h, in: vr)
                if hypot(hp.x - p.x, hp.y - p.y) < 12 { return (r.id, h) }
            }
        }
        for r in order where viewRect(r.rect, frame).contains(p) { return (r.id, .move) }
        return nil
    }

    // MARK: Gestes
    private func onDrag(_ v: DragGesture.Value, _ frame: CGRect) {
        let p = v.location
        let nx = { (x: CGFloat) in min(1, max(0, (x - frame.minX) / frame.width)) }
        let ny = { (y: CGFloat) in min(1, max(0, (y - frame.minY) / frame.height)) }

        if active == nil && drawing == nil {
            if let (id, h) = hit(v.startLocation, frame), let r = regions.first(where: { $0.id == id }) {
                active = (id, h, r.rect, v.startLocation); selected = id
            } else if allowsDraw, frame.contains(v.startLocation) {
                let r = Region(rect: CGRect(x: nx(v.startLocation.x), y: ny(v.startLocation.y), width: 0, height: 0))
                regions.append(r); selected = r.id
                drawing = (r.id, CGPoint(x: nx(v.startLocation.x), y: ny(v.startLocation.y)))
            } else { selected = nil }
        }
        if let d = drawing, let i = regions.firstIndex(where: { $0.id == d.id }) {
            let a = d.origin, b = CGPoint(x: nx(p.x), y: ny(p.y))
            regions[i].rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            return
        }
        guard let a = active, let i = regions.firstIndex(where: { $0.id == a.id }) else { return }
        let dx = (p.x - a.startPoint.x) / frame.width, dy = (p.y - a.startPoint.y) / frame.height
        var r = a.startRect
        switch a.handle {
        case .move:
            r.origin.x = min(max(0, r.origin.x + dx), 1 - r.width)
            r.origin.y = min(max(0, r.origin.y + dy), 1 - r.height)
        default:
            var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
            if [.tl, .bl, .l].contains(a.handle) { minX = min(max(0, minX + dx), maxX - 0.02) }
            if [.tr, .br, .r].contains(a.handle) { maxX = max(min(1, maxX + dx), minX + 0.02) }
            if [.tl, .tr, .t].contains(a.handle) { minY = min(max(0, minY + dy), maxY - 0.02) }
            if [.bl, .br, .b].contains(a.handle) { maxY = max(min(1, maxY + dy), minY + 0.02) }
            if let ratio = lockAspect, contentSize.width > 0 {
                // ratio px = (nw * W) / (nh * H)
                let k = ratio * contentSize.height / contentSize.width        // nw / nh
                let w = maxX - minX
                var h = w / k
                let anchorBottom = [.tl, .tr].contains(a.handle)
                if anchorBottom { minY = maxY - h; if minY < 0 { minY = 0; h = maxY; let w2 = h * k; if [.tl, .bl].contains(a.handle) { minX = maxX - w2 } else { maxX = minX + w2 } } }
                else { maxY = minY + h; if maxY > 1 { maxY = 1; h = maxY - minY; let w2 = h * k; if [.tl, .bl].contains(a.handle) { minX = maxX - w2 } else { maxX = minX + w2 } } }
            }
            r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        regions[i].rect = r
    }
}

extension CGRect {
    /// Rectangle le plus grand de ratio donné (px) centré dans l'image normalisée.
    static func normalizedFit(ratio: CGFloat, imageSize: CGSize) -> CGRect {
        let imgRatio = imageSize.width / imageSize.height
        if ratio > imgRatio {      // limité par la largeur
            let h = imgRatio / ratio
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        } else {
            let w = ratio / imgRatio
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        }
    }
}

struct AspectRatioChoice: Hashable {
    let label: String
    let ratio: CGFloat?
    static let all: [AspectRatioChoice] = [
        .init(label: "Free", ratio: nil), .init(label: "1:1", ratio: 1), .init(label: "16:9", ratio: 16.0 / 9),
        .init(label: "9:16", ratio: 9.0 / 16), .init(label: "4:3", ratio: 4.0 / 3), .init(label: "3:4", ratio: 3.0 / 4)
    ]
}

/// Ligne « Aspect ratio » + champs W × H, partagée par Crop Image / Crop Video.
struct CropControls: View {
    let pixelSize: CGSize
    @Binding var region: Region
    @Binding var ratio: AspectRatioChoice

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Aspect ratio").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                PillPicker(options: AspectRatioChoice.all.map { ($0, $0.label) }, selection: Binding(
                    get: { ratio },
                    set: { ratio = $0; if let r = $0.ratio { region.rect = .normalizedFit(ratio: r, imageSize: pixelSize) } }))
            }
            HStack(spacing: 6) {
                Text("W").sectionLabel()
                field(width: true)
                Text("H").sectionLabel()
                field(width: false)
                Text("px").sectionLabel()
                Spacer()
            }
        }
    }

    private func field(width: Bool) -> some View {
        let value = Binding<Int>(
            get: { Int((width ? region.rect.width * pixelSize.width : region.rect.height * pixelSize.height).rounded()) },
            set: { v in
                var r = region.rect
                if width {
                    r.size.width = min(CGFloat(max(2, v)) / pixelSize.width, 1 - r.minX)
                    if let k = ratio.ratio { r.size.height = min(r.width * pixelSize.width / k / pixelSize.height, 1 - r.minY) }
                } else {
                    r.size.height = min(CGFloat(max(2, v)) / pixelSize.height, 1 - r.minY)
                    if let k = ratio.ratio { r.size.width = min(r.height * pixelSize.height * k / pixelSize.width, 1 - r.minX) }
                }
                region.rect = r
            })
        return TextField("", value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
    }
}
