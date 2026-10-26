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
struct CropImageTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource
    @State private var regions = [Region(rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
    @State private var selected: UUID?
    @State private var ratio = AspectRatioChoice.all[0]

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
    }

    var body: some View {
        ToolShell(title: "Crop Image", close: close) {
            VStack(spacing: 12) {
                RegionEditor(contentSize: src.pixelSize, regions: $regions, selected: $selected, lockAspect: ratio.ratio, dimOutside: true) {
                    if let i = src.preview { Image(nsImage: i).resizable() }
                }
                .frame(width: 400, height: 420)
                CropControls(pixelSize: src.pixelSize, region: $regions[0], ratio: $ratio)
            }
            .frame(width: 400)
        } footer: {
            Button("Reset") { regions[0].rect = CGRect(x: 0, y: 0, width: 1, height: 1); ratio = AspectRatioChoice.all[0] }.buttonStyle(PillButtonStyle())
            Spacer()
            Button("Apply") { apply() }.buttonStyle(PillButtonStyle())
        }
    }

    private func apply() {
        let r = regions[0].rect
        let files = urls
        close()
        Dispatcher.job("Cropping…", light: true) { _ in
            try await Task.detached {
                try files.map { url in
                    let (img, props) = try ImageEngine.load(url)
                    let rect = CGRect(x: r.minX * CGFloat(img.width), y: r.minY * CGFloat(img.height),
                                      width: r.width * CGFloat(img.width), height: r.height * CGFloat(img.height)).integral
                    guard let c = img.cropping(to: rect) else { throw MandarineError("Recadrage impossible.") }
                    let out = OutputNaming.sibling(of: url, suffix: " cropped")
                    try ImageEngine.write(c, properties: props, to: out, ext: url.pathExtension, quality: 0.95)
                    return out
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
        ToolShell(title: "Redact Photo", close: close) {
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
                row("Style") { PillPicker(options: [(RedactStyle.solid, "Solid"), (.blur, "Blur")], selection: $style) }
                if style == .solid { row("Color") { ColorPicker("", selection: $color).labelsHidden() } }
                row("Detect") {
                    HStack {
                        Button("Faces") { detect(faces: true) }.buttonStyle(PillButtonStyle())
                        Button("Text") { detect(faces: false) }.buttonStyle(PillButtonStyle())
                    }.disabled(detecting)
                }
                Text("Drag on the photo to add an area. Select one and press Delete to remove it.").sectionLabel()
            }
            .frame(width: 400)
        } footer: {
            Button("Reset") { regions = []; selected = nil }.buttonStyle(PillButtonStyle())
            Spacer()
            Button("Save Redacted Copy") { save() }.buttonStyle(PillButtonStyle()).disabled(regions.isEmpty)
        }
    }

    private func row<V: View>(_ title: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack { Text(title).sectionLabel(); Spacer(); v() }
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
                if found.isEmpty { Toast.shared.done(faces ? "No faces found" : "No text found") }
            }
        }
    }

    private func save() {
        let rects = regions.map(\.rect), style = style, color = NSColor(color)
        let file = urls[0]
        close()
        Dispatcher.job("Redacting…", light: true) { _ in
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
        guard let out = ctx.createCGImage(base, from: CGRect(x: 0, y: 0, width: W, height: H)) else { throw MandarineError("Rendu impossible.") }
        let dest = OutputNaming.sibling(of: url, suffix: " redacted")
        try ImageEngine.write(out, properties: [:], to: dest, ext: url.pathExtension, quality: 0.95)
        _ = props
        return dest
    }
}
