import SwiftUI
import AppKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Chargement d'un aperçu + image pleine résolution à la demande.
final class ImageSource: ObservableObject {
    let url: URL
    @Published var preview: NSImage?
    @Published var pixelSize: CGSize = .zero
    init(_ url: URL) {
        self.url = url
        if let (cg, _) = try? ImageEngine.load(url) {
            pixelSize = CGSize(width: cg.width, height: cg.height)
            let small = ImageEngine.resize(cg, maxSide: 1600)
            preview = NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height))
        }
    }
    func full() throws -> (CGImage, [String: Any]) { try ImageEngine.load(url) }
}

// MARK: Crop

/// Damier : ce qui est transparent.
private struct CropChecker: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 10
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            for y in 0..<Int(size.height / s) + 1 { for x in 0..<Int(size.width / s) + 1 where (x + y) % 2 == 0 {
                ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)), with: .color(Color(white: 0.78)))
            } }
        }
    }
}

struct CropImageTool: View {
    private enum Fill: Hashable { case transparent, color }

    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource
    @State private var regions = [Region(rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
    @State private var selected: UUID?
    @State private var ratio = AspectRatioChoice.all[0]
    @State private var fill = Fill.transparent
    @State private var fillColor = Color.white
    @State private var bounds = CGRect(x: 0, y: 0, width: 1, height: 1)          // zone où le cadre peut aller : l'image, ou la taille tapée dans W / H

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
        if let e = ProcessInfo.processInfo.environment["MANDARINE_CROPRECT"] {          // essais : cadre de départ « x,y,largeur,hauteur » (0…1, peut dépasser)
            let v = e.split(separator: ",").compactMap { Double($0) }
            if v.count == 4 { let r = CGRect(x: v[0], y: v[1], width: v[2], height: v[3]); _regions = State(initialValue: [Region(rect: r)]); _bounds = State(initialValue: CGRect(x: 0, y: 0, width: 1, height: 1).union(r)) }
        }
    }

    /// Le cadre sort de l'image : il faut décider de ce qui remplit la partie ajoutée.
    private var extended: Bool {
        let r = regions[0].rect
        return r.minX < -0.0005 || r.minY < -0.0005 || r.maxX > 1.0005 || r.maxY > 1.0005
    }
    /// Une photo JPEG ne peut pas être transparente : le résultat est alors enregistré en PNG.
    private static func keepsAlpha(_ ext: String) -> Bool { ["png", "webp", "tiff", "tif"].contains(ext.lowercased()) }
    private var needsPNG: Bool { extended && fill == .transparent && urls.contains { !Self.keepsAlpha($0.pathExtension) } }

    var body: some View {
        ToolShell(title: L("Crop Image"), close: close) {
            VStack(spacing: 12) {
                RegionEditor(contentSize: src.pixelSize, regions: $regions, selected: $selected, lockAspect: ratio.ratio, dimOutside: true,
                             bounds: bounds,
                             outsideFill: AnyView(fill == .transparent ? AnyView(CropChecker()) : AnyView(fillColor))) {
                    if let i = src.preview { Image(nsImage: i).resizable() }
                }
                .frame(width: 400, height: 420)
                CropControls(extend: true, didType: { bounds = CGRect(x: 0, y: 0, width: 1, height: 1).union($0) }, pixelSize: src.pixelSize, region: $regions[0], ratio: $ratio)
                if extended {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("Added area")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            Spacer()
                            PillPicker(options: [(Fill.transparent, L("Transparent")), (Fill.color, L("Color"))], selection: $fill)
                            if fill == .color { ColorPicker("", selection: $fillColor, supportsOpacity: false).labelsHidden() }
                        }
                        if needsPNG {
                            Text(L("A JPEG can't be transparent: the result is saved as a PNG."))
                                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text(L("Type a bigger W or H to add room around the photo."))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 400)
        } footer: {
            Button(L("Reset")) { regions[0].rect = CGRect(x: 0, y: 0, width: 1, height: 1); bounds = regions[0].rect; ratio = AspectRatioChoice.all[0] }.buttonStyle(PillButtonStyle())
            ReplaceButton(L("Apply")) { apply() }
        }
    }

    private func apply() {
        let r = regions[0].rect
        let files = urls
        let added = extended
        let transparent = fill == .transparent
        let color = NSColor(fillColor).usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 1, alpha: 1)
        close()
        Dispatcher.job(L("Cropping…"), light: true, replaces: files) { _ in
            try await Task.detached {
                try files.map { url in
                    let (img, props) = try ImageEngine.load(url)
                    let W = CGFloat(img.width), H = CGFloat(img.height)
                    let rect = CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H).integral
                    let out: CGImage
                    var ext = url.pathExtension
                    if added, !CGRect(x: 0, y: 0, width: W, height: H).contains(rect) {
                        // cadre plus grand que l'image : nouveau canevas (transparent ou de la couleur choisie) avec l'image à sa place
                        guard let c = ImageEngine.crop(img, to: rect, fill: transparent ? nil : color) else { throw MandarineError(L("Recadrage impossible.")) }
                        out = c
                        if transparent && !Self.keepsAlpha(ext) { ext = "png" }
                    } else {
                        guard let c = img.cropping(to: rect) else { throw MandarineError(L("Recadrage impossible.")) }
                        out = c
                    }
                    let dest = OutputNaming.sibling(of: url, suffix: " cropped", ext: ext)
                    try ImageEngine.write(out, properties: props, to: dest, ext: ext, quality: 0.95)
                    return dest
                }
            }.value
        }
    }
}

// MARK: Redact (photo)
enum RedactStyle { case solid, blur }

struct RedactImageTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource
    @State private var regions: [Region] = []
    @State private var selected: UUID?
    @State private var style = RedactStyle.solid
    @State private var color = Color.black
    @State private var detecting = false

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
    }

    var body: some View {
        ToolShell(title: L("Redact Photo"), close: close) {
            VStack(spacing: 12) {
                RegionEditor(contentSize: src.pixelSize, regions: $regions, selected: $selected, allowsDraw: true,
                             fillStyle: { _ in
                                 style == .solid ? AnyView(Rectangle().fill(color))
                                                 : AnyView(Rectangle().fill(.ultraThinMaterial).overlay(Color.white.opacity(0.15)))
                             }) {
                    if let i = src.preview { Image(nsImage: i).resizable() }
                }
                .frame(width: 400, height: 420)
                .onDeleteCommand { regions.removeAll { $0.id == selected } }
                row(L("Style")) { PillPicker(options: [(RedactStyle.solid, "Solid"), (.blur, "Blur")], selection: $style) }
                if style == .solid { row(L("Color")) { ColorPicker("", selection: $color).labelsHidden() } }
                row(L("Detect")) {
                    HStack {
                        Button(L("Faces")) { detect(faces: true) }.buttonStyle(PillButtonStyle())
                        Button(L("Text")) { detect(faces: false) }.buttonStyle(PillButtonStyle())
                    }.disabled(detecting)
                }
                Text(L("Drag on the photo to add an area. Select one and press Delete to remove it.")).sectionLabel()
            }
            .frame(width: 400)
        } footer: {
            Button(L("Reset")) { regions = []; selected = nil }.buttonStyle(PillButtonStyle())
            ReplaceButton(L("Save Redacted Copy")) { save() }.disabled(regions.isEmpty)
        }
    }

    private func row<V: View>(_ title: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack { Text(L(title)).sectionLabel(); Spacer(); v() }
    }

    private func detect(faces: Bool) {
        detecting = true
        let url = urls[0]
        DispatchQueue.global().async {
            var found: [CGRect] = []
            if let (cg, _) = try? ImageEngine.load(url) {
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                if faces {
                    let req = VNDetectFaceRectanglesRequest()
                    try? handler.perform([req])
                    found = (req.results ?? []).map { $0.boundingBox }
                } else {
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    try? handler.perform([req])
                    found = (req.results ?? []).map { $0.boundingBox }
                }
            }
            DispatchQueue.main.async {
                for b in found {      // Vision : origine en bas à gauche
                    let r = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height).insetBy(dx: -0.01, dy: -0.01)
                    regions.append(Region(rect: r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))))
                }
                detecting = false
                if found.isEmpty { Toast.shared.done(faces ? L("No faces found") : L("No text found")) }
            }
        }
    }

    private func save() {
        let rects = regions.map(\.rect), style = style, color = NSColor(color)
        let file = urls[0]
        close()
        Dispatcher.job(L("Redacting…"), light: true, replaces: [file]) { _ in
            [try await Task.detached { try Self.render(file, rects: rects, style: style, color: color) }.value]
        }
    }

    nonisolated static func render(_ url: URL, rects: [CGRect], style: RedactStyle, color: NSColor) throws -> URL {
        let (img, props) = try ImageEngine.load(url)
        let W = CGFloat(img.width), H = CGFloat(img.height)
        let ctx = CIContext()
        var base = CIImage(cgImage: img)
        for n in rects {
            // CIImage : origine en bas à gauche
            let r = CGRect(x: n.minX * W, y: (1 - n.maxY) * H, width: n.width * W, height: n.height * H).integral
            let patch: CIImage
            switch style {
            case .solid:
                patch = CIImage(color: CIColor(color: color) ?? .black).cropped(to: r)
            case .blur:
                let f = CIFilter.pixellate()
                f.inputImage = base.clampedToExtent()
                f.scale = Float(max(8, min(r.width, r.height) / 6))
                let blur = CIFilter.gaussianBlur()
                blur.inputImage = f.outputImage
                blur.radius = Float(max(6, min(r.width, r.height) / 10))
                patch = blur.outputImage!.cropped(to: r)
            }
            base = patch.composited(over: base)
        }
        guard let out = ctx.createCGImage(base, from: CGRect(x: 0, y: 0, width: W, height: H)) else { throw MandarineError(L("Rendu impossible.")) }
        let dest = OutputNaming.sibling(of: url, suffix: " redacted")
        try ImageEngine.write(out, properties: [:], to: dest, ext: url.pathExtension, quality: 0.95)
        _ = props
        return dest
    }
}
