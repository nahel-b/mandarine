import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct AdjustParam: Identifiable {
    let id: String
    let title: String
    let range: ClosedRange<Double>
    let neutral: Double
    let unit: String
    let decimals: Int
}

enum AdjustGroup: String, CaseIterable {
    case light = "Light", color = "Color", detail = "Detail", effects = "Effects"
    var params: [AdjustParam] {
        switch self {
        case .light: return [
            .init(id: "exposure", title: "Exposure", range: -3...3, neutral: 0, unit: " EV", decimals: 2),
            .init(id: "brightness", title: "Brightness", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "contrast", title: "Contrast", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "highlights", title: "Highlights", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "shadows", title: "Shadows", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "whites", title: "Whites", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "blacks", title: "Blacks", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "gamma", title: "Gamma", range: -100...100, neutral: 0, unit: "", decimals: 0)]
        case .color: return [
            .init(id: "temperature", title: "Temperature", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "tint", title: "Tint", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "saturation", title: "Saturation", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "vibrance", title: "Vibrance", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "hue", title: "Hue", range: -180...180, neutral: 0, unit: "°", decimals: 0)]
        case .detail: return [
            .init(id: "clarity", title: "Clarity", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "dehaze", title: "Dehaze", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "sharpen", title: "Sharpen", range: 0...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "noise", title: "Noise reduction", range: 0...100, neutral: 0, unit: "", decimals: 0)]
        case .effects: return [
            .init(id: "grain", title: "Grain", range: 0...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "vignette", title: "Vignette", range: -100...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "fade", title: "Fade", range: 0...100, neutral: 0, unit: "", decimals: 0),
            .init(id: "mono", title: "Black & white", range: 0...100, neutral: 0, unit: "", decimals: 0)]
        }
    }
}

enum PhotoAdjuster {
    static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func apply(_ values: [String: Double], to input: CIImage) -> CIImage {
        func v(_ k: String) -> Double { values[k] ?? 0 }
        var img = input
        let extent = input.extent

        if v("exposure") != 0 { let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(v("exposure")); img = f.outputImage ?? img }
        if v("highlights") != 0 || v("shadows") != 0 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = img
            f.highlightAmount = Float(1 - v("highlights") / 100 * 0.9)      // 1 = neutre ; <1 assombrit les hautes lumières
            f.shadowAmount = Float(v("shadows") / 100)
            img = f.outputImage ?? img
        }
        if v("whites") != 0 || v("blacks") != 0 {
            let f = CIFilter.toneCurve(); f.inputImage = img
            let w = v("whites") / 100 * 0.12, b = v("blacks") / 100 * 0.12
            f.point0 = CGPoint(x: 0, y: max(0, b)); f.point1 = CGPoint(x: 0.25, y: 0.25 + b * 0.6)
            f.point2 = CGPoint(x: 0.5, y: 0.5); f.point3 = CGPoint(x: 0.75, y: 0.75 + w * 0.6); f.point4 = CGPoint(x: 1, y: min(1, 1 + w))
            img = f.outputImage ?? img
        }
        if v("gamma") != 0 { let f = CIFilter.gammaAdjust(); f.inputImage = img; f.power = Float(pow(2, -v("gamma") / 100)); img = f.outputImage ?? img }
        if v("brightness") != 0 || v("contrast") != 0 || v("saturation") != 0 {
            let f = CIFilter.colorControls(); f.inputImage = img
            f.brightness = Float(v("brightness") / 100 * 0.5)
            f.contrast = Float(1 + v("contrast") / 100 * 0.6)
            f.saturation = Float(1 + v("saturation") / 100)
            img = f.outputImage ?? img
        }
        if v("temperature") != 0 || v("tint") != 0 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = img
            f.neutral = CIVector(x: 6500 + CGFloat(v("temperature")) * 25, y: CGFloat(v("tint")) * 0.8)
            f.targetNeutral = CIVector(x: 6500, y: 0)
            img = f.outputImage ?? img
        }
        if v("vibrance") != 0 { let f = CIFilter.vibrance(); f.inputImage = img; f.amount = Float(v("vibrance") / 100); img = f.outputImage ?? img }
        if v("hue") != 0 { let f = CIFilter.hueAdjust(); f.inputImage = img; f.angle = Float(v("hue") * .pi / 180); img = f.outputImage ?? img }
        if v("clarity") != 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = img
            f.radius = Float(max(extent.width, extent.height) / 120); f.intensity = Float(v("clarity") / 100 * 1.2)
            img = f.outputImage ?? img
        }
        if v("dehaze") != 0 {
            let d = v("dehaze") / 100
            let f = CIFilter.colorControls(); f.inputImage = img
            f.contrast = Float(1 + d * 0.35); f.saturation = Float(1 + d * 0.2); f.brightness = Float(-d * 0.06)
            img = f.outputImage ?? img
        }
        if v("noise") != 0 { let f = CIFilter.noiseReduction(); f.inputImage = img; f.noiseLevel = Float(v("noise") / 100 * 0.06); f.sharpness = 0.4; img = f.outputImage ?? img }
        if v("sharpen") != 0 { let f = CIFilter.sharpenLuminance(); f.inputImage = img; f.sharpness = Float(v("sharpen") / 100 * 1.5); img = f.outputImage ?? img }
        if v("mono") != 0 {
            let f = CIFilter.colorControls(); f.inputImage = img; f.saturation = Float(1 - v("mono") / 100); img = f.outputImage ?? img
        }
        if v("fade") != 0 {
            let f = CIFilter.colorMatrix(); f.inputImage = img
            let a = CGFloat(1 - v("fade") / 100 * 0.25)
            f.rVector = CIVector(x: a, y: 0, z: 0, w: 0); f.gVector = CIVector(x: 0, y: a, z: 0, w: 0); f.bVector = CIVector(x: 0, y: 0, z: a, w: 0)
            f.biasVector = CIVector(x: 1 - a, y: 1 - a, z: 1 - a, w: 0)
            img = f.outputImage ?? img
        }
        if v("vignette") != 0 {
            let f = CIFilter.vignette(); f.inputImage = img; f.intensity = Float(v("vignette") / 100 * 1.5); f.radius = Float(max(extent.width, extent.height) / 400 * 1.2)
            img = f.outputImage ?? img
        }
        if v("grain") != 0 {
            let noise = CIFilter.randomGenerator().outputImage!
            let mono = CIFilter.colorMatrix(); mono.inputImage = noise
            let g = CGFloat(v("grain") / 100 * 0.35)
            mono.rVector = CIVector(x: g, y: 0, z: 0, w: 0); mono.gVector = CIVector(x: g, y: 0, z: 0, w: 0); mono.bVector = CIVector(x: g, y: 0, z: 0, w: 0)
            mono.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0); mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            if let n = mono.outputImage?.cropped(to: extent) {
                let blend = CIFilter.additionCompositing(); blend.inputImage = n; blend.backgroundImage = img
                img = (blend.outputImage ?? img).cropped(to: extent)
            }
        }
        return img.cropped(to: extent)
    }
}

struct EditPhotoTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var values: [String: Double] = [:]
    @State private var preview: NSImage?
    @State private var base: CIImage?
    @State private var original: NSImage?

    var body: some View {
        ToolShell(title: "Edit Photo", close: close) {
            VStack(spacing: 12) {
                ZStack {
                    Theme.previewBG
                    if let p = preview ?? original { Image(nsImage: p).resizable().scaledToFit().padding(4) }
                }
                .frame(width: 420, height: 300).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(AdjustGroup.allCases, id: \.self) { g in
                            Text(g.rawValue).sectionLabel()
                            ForEach(g.params) { p in slider(p) }
                        }
                    }.padding(.trailing, 6)
                }.frame(height: 240)
            }
            .frame(width: 420)
        } footer: {
            Button("Reset") { values = [:]; refresh() }.buttonStyle(PillButtonStyle())
            Button { let f = urls; close(); ToolWindowController.present(.resizeImage, urls: f) } label: { Label("Resize…", systemImage: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(PillButtonStyle()).help("Open Resize for the same image")
            Spacer()
            Button("Save Edited Copy") { save() }.buttonStyle(PillButtonStyle())
        }
        .onAppear(perform: load)
    }

    private func slider(_ p: AdjustParam) -> some View {
        let b = Binding<Double>(get: { values[p.id] ?? p.neutral }, set: { values[p.id] = $0; refresh() })
        return HStack(spacing: 8) {
            Text(p.title).font(.system(size: 11)).frame(width: 95, alignment: .leading)
            Slider(value: b, in: p.range).controlSize(.mini)
            Text(String(format: "%@%.\(p.decimals)f%@", (values[p.id] ?? 0) > 0 && p.range.lowerBound < 0 ? "+" : "", values[p.id] ?? p.neutral, p.unit))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 56, alignment: .trailing)
            Button { values[p.id] = p.neutral; refresh() } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).opacity((values[p.id] ?? p.neutral) == p.neutral ? 0.3 : 1)
        }
    }

    private func load() {
        guard let (cg, _) = try? ImageEngine.load(urls[0], maxSide: 1000) else { return }
        base = CIImage(cgImage: cg)
        original = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func refresh() {
        guard let base = base else { return }
        let vals = values
        DispatchQueue.global(qos: .userInteractive).async {
            let out = PhotoAdjuster.apply(vals, to: base)
            if let cg = PhotoAdjuster.context.createCGImage(out, from: base.extent) {
                let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                DispatchQueue.main.async { preview = ns }
            }
        }
    }

    private func save() {
        let vals = values, files = urls
        close()
        Dispatcher.job("Saving edited copy…", light: true) { _ in
            try await Task.detached {
                try files.map { url in
                    let (cg, props) = try ImageEngine.load(url)
                    let out = PhotoAdjuster.apply(vals, to: CIImage(cgImage: cg))
                    guard let res = PhotoAdjuster.context.createCGImage(out, from: CIImage(cgImage: cg).extent) else { throw MandarineError("Rendu impossible.") }
                    let dest = OutputNaming.sibling(of: url, suffix: " edited")
                    try ImageEngine.write(res, properties: props, to: dest, ext: url.pathExtension, quality: 0.95)
                    return dest
                }
            }.value
        }
    }
}
