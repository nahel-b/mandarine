import SwiftUI
import AppKit
import ImageIO
import QuickLookUI

// MARK: Resize
struct ResizeImageTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var src: ImageSource

    private enum Mode: Hashable { case dimensions, percent, multiple, upscale }
    private enum Fit: Hashable { case fit, fill, stretch }
    @State private var mode = Mode.dimensions
    @State private var w = 0
    @State private var h = 0
    @State private var lock = true
    @State private var percent = 50.0
    @State private var fit = Fit.fit
    @State private var sizes: Set<Int> = [1080]
    @State private var noEnlarge = true
    @State private var useAI = Upscaler.aiAvailable
    @State private var previewAfter: NSImage?
    @State private var previewBefore: NSImage?          // upscale : zoom sur l'original
    @State private var previewInfo = ""
    @State private var previewBusy = false
    @State private var upFactor = Upscaler.aiAvailable ? 4 : 2
    private let presets = [320, 640, 1080, 1920, 2560, 3840]

    private struct PreviewKey: Hashable {
        var mode: Int, w: Int, h: Int, fit: Int, percent: Double, sizes: [Int], noEnlarge: Bool, useAI: Bool, factor: Int
    }
    private var modeInt: Int { switch mode { case .dimensions: return 0; case .percent: return 1; case .multiple: return 2; case .upscale: return 3 } }
    private var fitInt: Int { fit == .fit ? 0 : (fit == .fill ? 1 : 2) }
    private var key: PreviewKey {
        PreviewKey(mode: modeInt, w: w, h: h, fit: fitInt, percent: percent, sizes: sizes.sorted(), noEnlarge: noEnlarge, useAI: useAI, factor: upFactor)
    }

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _src = StateObject(wrappedValue: ImageSource(urls[0]))
    }

    private var ratio: Double { src.pixelSize.height > 0 ? Double(src.pixelSize.width / src.pixelSize.height) : 1 }

    var body: some View {
        ToolShell(title: "Resize", close: close) {
            VStack(alignment: .leading, spacing: 12) {
                Text(urls.count == 1 ? "\(urls[0].lastPathComponent) · \(Int(src.pixelSize.width)) × \(Int(src.pixelSize.height)) px" : "\(urls.count) images")
                    .sectionLabel().lineLimit(1).truncationMode(.middle)
                previewBox
                PillPicker(options: [(Mode.dimensions, "Dimensions"), (.percent, "Percent"), (.multiple, "Sizes"), (.upscale, "Upscale")], selection: $mode)
                switch mode {
                case .dimensions:
                    HStack(spacing: 8) {
                        field("W", $w) { if lock { h = Int((Double($0) / ratio).rounded()) } }
                        Button { lock.toggle(); if lock { h = Int((Double(w) / ratio).rounded()) } } label: {
                            Image(systemName: lock ? "link" : "link.badge.plus").foregroundStyle(lock ? Theme.orange : Theme.muted)
                        }.buttonStyle(.plain).help("Keep proportions")
                        field("H", $h) { if lock { w = Int((Double($0) * ratio).rounded()) } }
                        Text("px").sectionLabel()
                    }
                    if urls.count > 1 || !lock {
                        HStack { Text("Mode").sectionLabel(); Spacer()
                            Picker("", selection: $fit) { Text("Fit inside").tag(Fit.fit); Text("Fill and crop").tag(Fit.fill); Text("Stretch").tag(Fit.stretch) }
                                .labelsHidden().frame(width: 150) }
                    }
                case .percent:
                    HStack {
                        Slider(value: $percent, in: 5...400, step: 1)
                        TextField("", value: $percent, format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width: 56).multilineTextAlignment(.trailing)
                        Text("%").sectionLabel()
                    }
                    HStack(spacing: 6) { ForEach([25, 50, 75, 150, 200], id: \.self) { p in
                        Button("\(p)%") { percent = Double(p) }.buttonStyle(PillButtonStyle()) } }
                case .multiple:
                    Text("Longest side — one copy per size").sectionLabel()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(presets, id: \.self) { s in
                            Text("\(s) px").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, minHeight: 28)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(sizes.contains(s) ? Theme.orange : Color.black.opacity(0.07)))
                                .foregroundStyle(sizes.contains(s) ? .white : Theme.text)
                                .onTapGesture { if sizes.contains(s) { sizes.remove(s) } else { sizes.insert(s) } }
                        }
                    }
                    Text("\(sizes.count) size\(sizes.count == 1 ? "" : "s") × \(urls.count) image\(urls.count == 1 ? "" : "s") = \(sizes.count * urls.count) files").sectionLabel()
                case .upscale:
                    HStack { Text("Method").sectionLabel(); Spacer()
                        Picker("", selection: $useAI) {
                            Text("AI (Apple)").tag(true).disabled(!Upscaler.aiAvailable)
                            Text("Smooth (Lanczos)").tag(false)
                        }.labelsHidden().frame(width: 170)
                            .onChange(of: useAI) { ai in upFactor = ai ? (Upscaler.aiFactors.first ?? 4) : max(upFactor, 2) } }
                    HStack { Text("Scale").sectionLabel(); Spacer()
                        PillPicker(options: (useAI ? Upscaler.aiFactors : [2, 3, 4]).map { ($0, "×\($0)") }, selection: $upFactor) }
                    Text(useAI ? (Int(max(src.pixelSize.width, src.pixelSize.height)) > Upscaler.aiMaxInput
                                  ? "This image is larger than \(Upscaler.aiMaxInput) px: it will be enlarged with Lanczos instead of AI."
                                  : "Apple's on-device model rebuilds fine detail. The first use may download the model.")
                               : "Classic smooth enlargement (Core Image Lanczos). It does not add detail.")
                        .sectionLabel().fixedSize(horizontal: false, vertical: true)
                    if !Upscaler.aiAvailable { Text("AI upscaling needs macOS 26 or later.").sectionLabel() }
                }
                if mode == .dimensions || mode == .multiple {
                    Toggle("Don't enlarge images", isOn: $noEnlarge).font(.system(size: 12))
                }
            }.frame(width: 360, alignment: .leading)
        } footer: {
            Button { let f = urls; close(); ToolWindowController.present(.editImage, urls: f) } label: { Label("Edit…", systemImage: "slider.horizontal.3") }
                .buttonStyle(PillButtonStyle()).help("Open Edit Photo for the same image")
            Spacer()
            Button(mode == .upscale ? "Upscale" : "Resize") { mode == .upscale ? upscale() : apply() }.buttonStyle(PillButtonStyle()).disabled(mode == .multiple && sizes.isEmpty)
        }
        .onAppear { w = Int(src.pixelSize.width); h = Int(src.pixelSize.height) }
        .task(id: key) {
            try? await Task.sleep(nanoseconds: 250_000_000)             // on attend la fin de la saisie
            if Task.isCancelled || src.pixelSize.width == 0 { return }
            previewBusy = true
            let k = key, url = urls[0], orig = src.pixelSize
            let r = await Self.makePreview(k, url: url, original: orig)
            if Task.isCancelled { return }
            previewAfter = r.after; previewBefore = r.before; previewInfo = r.info; previewBusy = false
        }
    }

    @ViewBuilder private var previewBox: some View {
        VStack(spacing: 6) {
            ZStack {
                Theme.previewBG
                if mode == .upscale, let before = previewBefore, let after = previewAfter {
                    HStack(spacing: 6) {
                        labeled("Before", before, smooth: false)
                        labeled("After", after, smooth: true)
                    }.padding(6)
                } else if let after = previewAfter {
                    Image(nsImage: after).resizable().scaledToFit().padding(6)
                }
                if previewBusy { ProgressView().controlSize(.small).padding(8).background(Circle().fill(.ultraThinMaterial)) }
            }
            .frame(width: 360, height: 220).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(previewInfo).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
        }
    }

    private func labeled(_ title: String, _ img: NSImage, smooth: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: img).resizable().interpolation(smooth ? .high : .medium).scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.6))).padding(6)
        }.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Calcule l'aperçu réel (mêmes fonctions que l'export) sur une copie de travail.
    private static func makePreview(_ k: PreviewKey, url: URL, original o: CGSize) async -> (after: NSImage?, before: NSImage?, info: String) {
        await Task.detached(priority: .userInitiated) {
            let origBytes = url.fileSize.humanSize
            let ns = { (c: CGImage) in NSImage(cgImage: c, size: NSSize(width: c.width, height: c.height)) }
            do {
                if k.mode == 3 {
                    // Upscale : zoom 100 % sur le centre de l'image (l'IA travaille sur une petite zone, donc c'est rapide)
                    let (full, _) = try ImageEngine.load(url)
                    let side = min(160, min(full.width, full.height))
                    let rect = CGRect(x: (full.width - side) / 2, y: (full.height - side) / 2, width: side, height: side)
                    guard let crop = full.cropping(to: rect) else { return (nil, nil, "") }
                    let tooBig = max(full.width, full.height) > Upscaler.aiMaxInput
                    let (up, usedAI) = try await Upscaler.upscale(crop, factor: k.factor, preferAI: k.useAI && !tooBig)
                    let method = usedAI ? "Apple AI" : "Lanczos" + (k.useAI && tooBig ? " (too large for AI)" : "")
                    return (ns(up), ns(crop), "\(full.width * k.factor) × \(full.height * k.factor) px · ×\(k.factor) · \(method) · zoom 100% on the center")
                }
                let t = ResizeImageTool.targets(mode: k.mode, w: k.w, h: k.h, fit: k.fit, percent: k.percent, sizes: k.sizes, noEnlarge: k.noEnlarge, original: o).first
                guard let t = t else { return (nil, nil, "") }
                let (img, _) = try ImageEngine.load(url, maxSide: max(t.w, t.h, 1))
                var out: CGImage
                if t.crop {
                    let s = max(Double(t.w) / Double(img.width), Double(t.h) / Double(img.height))
                    let scaled = ImageEngine.resize(img, width: Int((Double(img.width) * s).rounded()), height: Int((Double(img.height) * s).rounded()))
                    out = scaled.cropping(to: CGRect(x: (scaled.width - t.w) / 2, y: (scaled.height - t.h) / 2, width: t.w, height: t.h)) ?? scaled
                } else { out = ImageEngine.resize(img, width: t.w, height: t.h) }
                let ext = ["png", "heic", "avif"].contains(Catalog.normalized(url.pathExtension)) ? Catalog.normalized(url.pathExtension) : "jpg"
                let bytes = Int64(ImageEngine.data(out, ext: ext, quality: 0.92)?.count ?? 0)
                let more = k.mode == 2 && k.sizes.count > 1 ? " · first of \(k.sizes.count) sizes" : ""
                return (ns(out), nil, "\(t.w) × \(t.h) px · ≈ \(bytes.humanSize)  (original \(Int(o.width)) × \(Int(o.height)) · \(origBytes))\(more)")
            } catch { return (nil, nil, error.localizedDescription) }
        }.value
    }

    private func upscale() {
        let (factor, ai, files) = (upFactor, useAI, urls)
        close()
        Dispatcher.job(ai ? "Upscaling with AI…" : "Upscaling…") { progress in
            var outs: [URL] = []
            for (i, url) in files.enumerated() {
                let (img, props) = try ImageEngine.load(url)
                let (out, usedAI) = try await Upscaler.upscale(img, factor: factor, preferAI: ai)
                var ext = url.pathExtension.lowercased()
                if !ImageEngine.canWrite(Catalog.normalized(ext)) || ext == "svg" || ext == "gif" { ext = "png" }
                let dest = OutputNaming.sibling(of: url, suffix: " x\(factor)\(usedAI ? " ai" : "")", ext: ext)
                try ImageEngine.write(out, properties: props, to: dest, ext: ext, quality: 0.95)
                outs.append(dest)
                progress(Double(i + 1) / Double(files.count))
            }
            return outs
        }
    }

    private func field(_ label: String, _ v: Binding<Int>, _ changed: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).sectionLabel()
            TextField("", value: Binding(get: { v.wrappedValue }, set: { v.wrappedValue = max(1, $0); changed(max(1, $0)) }), format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).frame(width: 74).multilineTextAlignment(.trailing)
        }
    }

    private func result(for s: CGSize) -> String {
        let t = Self.targets(mode: mode == .dimensions ? 0 : 1, w: w, h: h, fit: fit == .fit ? 0 : (fit == .fill ? 1 : 2), percent: percent, sizes: [], noEnlarge: noEnlarge, original: s)
        return t.first.map { "→ \($0.w) × \($0.h) px" } ?? ""
    }

    struct Target { var w: Int; var h: Int; var crop: Bool; var suffix: String }

    /// Calcule les tailles de sortie pour une image d'origine.
    nonisolated static func targets(mode: Int, w: Int, h: Int, fit: Int, percent: Double, sizes: [Int], noEnlarge: Bool, original o: CGSize) -> [Target] {
        let W = Double(o.width), H = Double(o.height)
        guard W > 0, H > 0 else { return [] }
        switch mode {
        case 0:   // dimensions exactes
            let tw = Double(w), th = Double(h)
            switch fit {
            case 0:
                var s = min(tw / W, th / H)
                if noEnlarge { s = min(s, 1) }
                return [Target(w: max(1, Int((W * s).rounded())), h: max(1, Int((H * s).rounded())), crop: false, suffix: " \(Int((W * s).rounded()))x\(Int((H * s).rounded()))")]
            case 1:
                var s = max(tw / W, th / H)
                if noEnlarge { s = min(s, 1) }
                let ow = min(Int(tw), Int((W * s).rounded())), oh = min(Int(th), Int((H * s).rounded()))
                return [Target(w: ow, h: oh, crop: true, suffix: " \(ow)x\(oh)")]
            default:
                let ow = noEnlarge ? min(w, Int(W)) : w, oh = noEnlarge ? min(h, Int(H)) : h
                return [Target(w: ow, h: oh, crop: false, suffix: " \(ow)x\(oh)")]
            }
        case 1:   // pourcentage
            var s = percent / 100
            if noEnlarge { s = min(s, 1) }
            return [Target(w: max(1, Int((W * s).rounded())), h: max(1, Int((H * s).rounded())), crop: false, suffix: " \(Int(percent))pct")]
        default:  // plusieurs tailles (plus grand côté)
            return sizes.sorted().compactMap { L in
                var s = Double(L) / max(W, H)
                if noEnlarge && s > 1 { if L == sizes.sorted().first { s = 1 } else { return nil } }
                return Target(w: max(1, Int((W * s).rounded())), h: max(1, Int((H * s).rounded())), crop: false, suffix: " \(L)px")
            }
        }
    }

    private func apply() {
        let (m, w, h, f, p, sz, ne) = (mode == .dimensions ? 0 : (mode == .percent ? 1 : 2), self.w, self.h, fit == .fit ? 0 : (fit == .fill ? 1 : 2), percent, Array(sizes), noEnlarge)
        let files = urls
        close()
        Dispatcher.job("Resizing…") { progress in
            try await Task.detached {
                var outs: [URL] = []
                var folder: URL?
                if m == 2 && (sz.count > 1 || files.count > 1) { folder = OutputNaming.folder(of: files[0], suffix: "resized") }
                for (i, url) in files.enumerated() {
                    let (img, props) = try ImageEngine.load(url)
                    let size = CGSize(width: img.width, height: img.height)
                    var ext = url.pathExtension.lowercased()
                    if !ImageEngine.canWrite(Catalog.normalized(ext)) || ext == "svg" || ext == "gif" { ext = "png" }
                    for t in Self.targets(mode: m, w: w, h: h, fit: f, percent: p, sizes: sz, noEnlarge: ne, original: size) {
                        var out: CGImage
                        if t.crop {
                            let s = max(Double(t.w) / Double(img.width), Double(t.h) / Double(img.height))
                            let scaled = ImageEngine.resize(img, width: Int((Double(img.width) * s).rounded()), height: Int((Double(img.height) * s).rounded()))
                            let rect = CGRect(x: (scaled.width - t.w) / 2, y: (scaled.height - t.h) / 2, width: t.w, height: t.h)
                            out = scaled.cropping(to: rect) ?? scaled
                        } else {
                            out = ImageEngine.resize(img, width: t.w, height: t.h)
                        }
                        let dest = OutputNaming.sibling(of: url, suffix: t.suffix, ext: ext, in: folder)
                        try ImageEngine.write(out, properties: props, to: dest, ext: ext, quality: 0.92)
                        outs.append(dest)
                    }
                    progress(Double(i + 1) / Double(files.count))
                }
                return folder.map { [$0] } ?? outs
            }.value
        }
    }
}

// MARK: Rotate / flip
enum ImageTransform {
    static func apply(_ img: CGImage, turns: Int, flipH: Bool, flipV: Bool) -> CGImage {
        let t = ((turns % 4) + 4) % 4
        if t == 0 && !flipH && !flipV { return img }
        let W = img.width, H = img.height
        let (ow, oh) = t % 2 == 1 ? (H, W) : (W, H)
        guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(ow) / 2, y: CGFloat(oh) / 2)
        ctx.rotate(by: -CGFloat(t) * .pi / 2)                    // sens horaire (CG a l'axe Y vers le haut)
        ctx.scaleBy(x: flipH ? -1 : 1, y: flipV ? -1 : 1)
        ctx.draw(img, in: CGRect(x: -CGFloat(W) / 2, y: -CGFloat(H) / 2, width: CGFloat(W), height: CGFloat(H)))
        return ctx.makeImage() ?? img
    }

    static func exifOrientation(_ url: URL) -> Int {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any] else { return 1 }
        return p[kCGImagePropertyOrientation as String] as? Int ?? 1
    }
}

struct RotateImageTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var base: CGImage?
    @State private var turns = 0
    @State private var flipH = false
    @State private var flipV = false
    @State private var preview: NSImage?
    @State private var exif = 1

    private var exifText: String {
        switch exif {
        case 1: return "Orientation EXIF : normale"
        case 3: return "Orientation EXIF : retournée à 180° — corrigée automatiquement"
        case 6: return "Orientation EXIF : tournée de 90° — corrigée automatiquement"
        case 8: return "Orientation EXIF : tournée de 270° — corrigée automatiquement"
        default: return "Orientation EXIF : miroir — corrigée automatiquement"
        }
    }
    private var changed: Bool { turns % 4 != 0 || flipH || flipV }

    var body: some View {
        ToolShell(title: "Rotate & Flip", close: close) {
            VStack(spacing: 12) {
                ZStack {
                    Theme.previewBG
                    if let p = preview { Image(nsImage: p).resizable().scaledToFit().padding(6) }
                }.frame(width: 380, height: 280).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 6) {
                    tile("rotate.left", "Left") { turns -= 1; update() }
                    tile("rotate.right", "Right") { turns += 1; update() }
                    tile("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip H") { flipH.toggle(); update() }
                    tile("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip V") { flipV.toggle(); update() }
                }
                Text(exifText).sectionLabel().frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 380)
        } footer: {
            Button("Reset") { turns = 0; flipH = false; flipV = false; update() }.buttonStyle(PillButtonStyle()).disabled(!changed)
            Spacer()
            Button(changed ? "Save Rotated Copy" : "Straighten (EXIF)") { save() }.buttonStyle(PillButtonStyle()).disabled(!changed && exif == 1)
        }
        .task {
            exif = ImageTransform.exifOrientation(urls[0])
            if let (cg, _) = try? ImageEngine.load(urls[0], maxSide: 1000) { base = cg; update() }
        }
    }

    private func tile(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: symbol).font(.system(size: 16, weight: .medium)); Text(title).font(.system(size: 10)) }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.07)))
        }.buttonStyle(.plain)
    }

    private func update() {
        guard let b = base else { return }
        let t = ImageTransform.apply(b, turns: turns, flipH: flipH, flipV: flipV)
        preview = NSImage(cgImage: t, size: NSSize(width: t.width, height: t.height))
    }

    private func save() {
        let (t, h, v, files) = (turns, flipH, flipV, urls)
        close()
        Dispatcher.job("Rotating…") { progress in
            try await Task.detached {
                var outs: [URL] = []
                for (i, url) in files.enumerated() {
                    let (img, props) = try ImageEngine.load(url)          // l'orientation EXIF est déjà appliquée aux pixels
                    var p = props; p[kCGImagePropertyOrientation as String] = 1
                    let out = ImageTransform.apply(img, turns: t, flipH: h, flipV: v)
                    var ext = url.pathExtension.lowercased()
                    if !ImageEngine.canWrite(Catalog.normalized(ext)) || ext == "svg" { ext = "png" }
                    let dest = OutputNaming.sibling(of: url, suffix: " rotated", ext: ext)
                    try ImageEngine.write(out, properties: p, to: dest, ext: ext, quality: 0.95)
                    outs.append(dest)
                    progress(Double(i + 1) / Double(files.count))
                }
                return outs
            }.value
        }
    }
}

// MARK: Extract audio (vidéo → audio)
struct ExtractAudioTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var choice = "original"
    @State private var codec = ""

    var body: some View {
        ToolShell(title: "Extract Audio", close: close) {
            VStack(alignment: .leading, spacing: 12) {
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) videos").sectionLabel().lineLimit(1).truncationMode(.middle)
                Text("Format").font(.system(size: 15, weight: .semibold))
                PillPicker(options: [("original", "Original"), ("mp3", "MP3"), ("m4a", "M4A"), ("wav", "WAV"), ("flac", "FLAC")], selection: $choice)
                Text(choice == "original" ? (codec.isEmpty ? "Copies the audio track without re-encoding." : "Copies the \(codec.uppercased()) track without re-encoding — no quality loss.")
                                          : "Re-encodes the audio track as \(choice.uppercased()).")
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 380, alignment: .leading)
        } footer: { Button("Extract Audio") { apply() }.buttonStyle(PillButtonStyle()) }
        .task { codec = await ExtractAudioTool.codecName(urls[0]) ?? "" }
    }

    static func codecName(_ url: URL) async -> String? {
        guard let ff = FFmpeg.ffprobe else { return nil }
        return await Task.detached {
            let p = Process(); p.executableURL = ff
            p.arguments = ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "default=nw=1:nk=1", url.path]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return nil }
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        }.value
    }

    static func containerExt(for codec: String) -> String? {
        switch codec {
        case "aac", "alac": return "m4a"
        case "mp3": return "mp3"
        case "opus": return "opus"
        case "vorbis": return "ogg"
        case "flac": return "flac"
        case "ac3": return "ac3"
        case let c where c.hasPrefix("pcm"): return "wav"
        default: return nil
        }
    }

    private func apply() {
        let (c, files) = (choice, urls)
        close()
        Dispatcher.job("Extracting audio…") { progress in
            var outs: [URL] = []
            for (i, f) in files.enumerated() {
                let info = await FFmpeg.probe(f)
                guard info.hasAudio else { throw MandarineError("\(f.lastPathComponent) n'a pas de piste audio.") }
                var args = ["-i", f.path, "-vn"]
                var ext = c
                if c == "original" {
                    if let codec = await ExtractAudioTool.codecName(f), let e = ExtractAudioTool.containerExt(for: codec) { ext = e; args += ["-c:a", "copy"] }
                    else { ext = "m4a"; args += FFmpeg.audioArgs(for: "m4a") }
                } else { args += FFmpeg.audioArgs(for: c) }
                let out = OutputNaming.sibling(of: f, ext: ext)
                try await FFmpeg.run(args + [out.path], duration: info.duration) { p in progress((Double(i) + p) / Double(files.count)) }
                outs.append(out)
            }
            return outs
        }
    }
}

// MARK: Extract images (PDF)
enum PDFImageExtractor {
    private final class Box { var images: [(name: String, stream: CGPDFStreamRef)] = [] }

    static func extract(_ url: URL, into dir: URL) throws -> Int {
        guard let doc = CGPDFDocument(url as CFURL) else { throw MandarineError("PDF illisible.") }
        var n = 0
        var seen = Set<String>()
        for p in 1...max(doc.numberOfPages, 1) {
            guard let page = doc.page(at: p), let dict = page.dictionary else { continue }
            var res: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dict, "Resources", &res), let resources = res else { continue }
            var xo: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xo), let xobjects = xo else { continue }
            let box = Box()
            CGPDFDictionaryApplyBlock(xobjects, { key, obj, info in
                guard let info = info else { return true }
                let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(obj, .stream, &stream), let s = stream, let sd = CGPDFStreamGetDictionary(s) else { return true }
                var subtype: UnsafePointer<CChar>?
                if CGPDFDictionaryGetName(sd, "Subtype", &subtype), let st = subtype, String(cString: st) == "Image" {
                    box.images.append((String(cString: key), s))
                }
                return true
            }, Unmanaged.passUnretained(box).toOpaque())
            for (name, stream) in box.images {
                let id = "\(p)-\(name)"
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                if try write(stream, to: dir, base: "\(url.deletingPathExtension().lastPathComponent) image \(n + 1)") { n += 1 }
            }
        }
        return n
    }

    private static func write(_ stream: CGPDFStreamRef, to dir: URL, base: String) throws -> Bool {
        guard let sd = CGPDFStreamGetDictionary(stream) else { return false }
        var fmt = CGPDFDataFormat.raw
        guard let cf = CGPDFStreamCopyData(stream, &fmt) else { return false }
        let data = cf as Data
        switch fmt {
        case .jpegEncoded:
            try data.write(to: dir.appendingPathComponent(base).appendingPathExtension("jpg")); return true
        case .JPEG2000:
            try data.write(to: dir.appendingPathComponent(base).appendingPathExtension("jp2")); return true
        default:
            var w: CGPDFInteger = 0, h: CGPDFInteger = 0, bpc: CGPDFInteger = 8
            guard CGPDFDictionaryGetInteger(sd, "Width", &w), CGPDFDictionaryGetInteger(sd, "Height", &h), w > 0, h > 0 else { return false }
            _ = CGPDFDictionaryGetInteger(sd, "BitsPerComponent", &bpc)
            guard bpc == 8 else { return false }
            let comps = data.count / Int(w * h)
            let space: CGColorSpace
            switch comps {
            case 1: space = CGColorSpaceCreateDeviceGray()
            case 3: space = CGColorSpaceCreateDeviceRGB()
            default: return false                       // CMYK / indexé : non pris en charge
            }
            guard let provider = CGDataProvider(data: data as CFData),
                  let img = CGImage(width: Int(w), height: Int(h), bitsPerComponent: 8, bitsPerPixel: 8 * comps, bytesPerRow: Int(w) * comps,
                                    space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                                    decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return false }
            try ImageEngine.write(img, to: dir.appendingPathComponent(base).appendingPathExtension("png"), ext: "png")
            return true
        }
    }
}

// MARK: Quick Look
struct QLPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.previewItem = url as QLPreviewItem
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? URL) != url { v.previewItem = url as QLPreviewItem }
    }
}

struct QuickLookTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var index = 0

    var body: some View {
        ToolShell(title: urls[index].lastPathComponent, close: close) {
            VStack(spacing: 10) {
                if urls.count > 1 {
                    Picker("", selection: $index) { ForEach(Array(urls.enumerated()), id: \.offset) { Text($1.lastPathComponent).tag($0) } }
                        .labelsHidden().frame(maxWidth: .infinity)
                }
                QLPreview(url: urls[index]).frame(width: 560, height: 400).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(urls[index].fileSize.humanSize + " · " + urls[index].deletingLastPathComponent().path).sectionLabel().lineLimit(1).truncationMode(.middle)
            }.frame(width: 560)
        } footer: {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([urls[index]]) }.buttonStyle(PillButtonStyle())
            Button("Open") { NSWorkspace.shared.open(urls[index]) }.buttonStyle(PillButtonStyle())
        }
    }
}
