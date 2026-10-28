import SwiftUI
import AppKit

private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 12
            for y in 0..<Int(size.height / s) + 1 { for x in 0..<Int(size.width / s) + 1 where (x + y) % 2 == 0 {
                ctx.fill(Path(CGRect(x: CGFloat(x) * s, y: CGFloat(y) * s, width: s, height: s)), with: .color(Color.white.opacity(0.10)))
            } }
        }
    }
}

struct RemoveBGTool: View {
    let urls: [URL]
    let close: () -> Void

    @State private var o = BGOptions()
    @State private var fillColor = Color.white
    @State private var outlineColor = Color.white
    @State private var format = "png"
    @State private var chosen: Set<Int> = []
    @State private var ids: [Int] = []
    @State private var preview: NSImage?
    @State private var status = "Detecting the subject…"
    @State private var busy = true
    @State private var failed = false
    @State private var session: AnyObject?          // BGSession (macOS 14+)
    @State private var baseCG: CGImage?

    var body: some View {
        ToolShell(title: "Remove Background", close: close) {
            VStack(alignment: .leading, spacing: 11) {
                ZStack {
                    Theme.previewBG
                    Checkerboard()
                    if let p = preview { Image(nsImage: p).resizable().scaledToFit().padding(8) }
                    if busy { VStack(spacing: 6) { ProgressView().controlSize(.small); Text(status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)) }
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45))) }
                    if failed { Text(status).font(.system(size: 12)).foregroundStyle(.white).padding() }
                }
                .frame(width: 380, height: 270).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if ids.count > 1 && urls.count == 1 {
                    HStack(spacing: 6) {
                        Text("Subjects").sectionLabel()
                        ForEach(ids, id: \.self) { id in
                            Text("\(id)").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 24)
                                .background(RoundedRectangle(cornerRadius: 7).fill(chosen.contains(id) ? Theme.orange : Color.black.opacity(0.08)))
                                .foregroundStyle(chosen.contains(id) ? .white : Theme.text)
                                .onTapGesture { toggle(id) }
                        }
                        Spacer()
                    }
                }
                row("Background") { PillPicker(options: [(BGFill.transparent, "Transparent"), (.color, "Color"), (.blur, "Blur")], selection: $o.fill) }
                if o.fill == .color { row("Color") { ColorPicker("", selection: $fillColor).labelsHidden() } }
                if o.fill == .blur { slider("Blur", $o.blur, 4...50, "%.0f") }
                slider("Soften edges", $o.soften, 0...14, "%.0f")
                slider("Edge shift", $o.shift, -10...10, "%+.0f")
                HStack {
                    Toggle("Sticker outline", isOn: $o.outline).font(.system(size: 12))
                    if o.outline { ColorPicker("", selection: $outlineColor).labelsHidden(); Slider(value: $o.outlineWidth, in: 2...30).controlSize(.small) }
                }
                Toggle("Crop to subject", isOn: $o.cropToSubject).font(.system(size: 12))
                row("Format") {
                    PillPicker(options: [("png", "PNG"), ("webp", "WebP"), ("heic", "HEIC"), ("jpg", "JPG")], selection: $format)
                }
                if format == "jpg" && o.fill == .transparent { Text("JPG has no transparency: the background will be white.").sectionLabel() }
            }.frame(width: 380, alignment: .leading)
        } footer: {
            Button("Reset") { o = BGOptions(); chosen = Set(ids) }.buttonStyle(PillButtonStyle())
            Button("Remove Background") { save() }.buttonStyle(PillButtonStyle()).disabled(failed || busy)
        }
        .task { await start() }
        .task(id: renderKey) { await rerender() }
    }

    private struct Key: Hashable { var fill: BGFill; var blur, soften, shift, ow: Double; var outline, crop: Bool; var c1, c2: String; var inst: [Int] }
    private var renderKey: Key {
        Key(fill: o.fill, blur: o.blur, soften: o.soften, shift: o.shift, ow: o.outlineWidth, outline: o.outline, crop: o.cropToSubject,
            c1: "\(NSColor(fillColor).description)", c2: "\(NSColor(outlineColor).description)", inst: chosen.sorted())
    }

    private func row<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View { HStack { Text(t).sectionLabel(); Spacer(); v() } }
    private func slider(_ t: String, _ b: Binding<Double>, _ r: ClosedRange<Double>, _ f: String) -> some View {
        HStack { Text(t).sectionLabel().frame(width: 90, alignment: .leading); Slider(value: b, in: r).controlSize(.small)
            Text(String(format: f, b.wrappedValue)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 34, alignment: .trailing) }
    }

    private func toggle(_ id: Int) {
        if chosen.contains(id) { if chosen.count > 1 { chosen.remove(id) } } else { chosen.insert(id) }
    }

    /// Détection du sujet sur une version réduite (rapide) ; le rendu final se fait en pleine résolution.
    private func start() async {
        guard #available(macOS 14.0, *) else { status = "Remove Background needs macOS 14 or later."; failed = true; busy = false; return }
        guard let (cg, _) = try? ImageEngine.load(urls[0], maxSide: 1000) else { status = "Couldn't read the image."; failed = true; busy = false; return }
        baseCG = cg
        do {
            let s = try await Task.detached { try BGSession(cg) }.value
            session = s
            ids = s.instanceIDs
            chosen = Set(ids)
            busy = false
        } catch {
            status = "No subject found in this image."; failed = true; busy = false
        }
    }

    private func rerender() async {
        guard #available(macOS 14.0, *), let s = session as? BGSession, !chosen.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
        var opts = o
        opts.color = NSColor(fillColor); opts.outlineColor = NSColor(outlineColor)
        opts.instances = chosen.count == ids.count ? nil : chosen
        let img = await Task.detached { try? s.render(opts) }.value
        if Task.isCancelled { return }
        if let img = img { preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)) }
    }

    private func save() {
        var opts = o
        opts.color = NSColor(fillColor); opts.outlineColor = NSColor(outlineColor)
        opts.instances = (chosen.count == ids.count || urls.count > 1) ? nil : chosen
        let (files, fmt, final) = (urls, format, opts)
        close()
        Dispatcher.job("Removing background…") { progress in
            guard #available(macOS 14.0, *) else { throw MandarineError("Remove Background nécessite macOS 14 ou plus récent.") }
            var outs: [URL] = []
            for (i, f) in files.enumerated() {
                let out = try await Task.detached { () -> URL in
                    let (cg, props) = try ImageEngine.load(f)
                    let img = try BGSession(cg).render(final)
                    let dest = OutputNaming.sibling(of: f, suffix: " no background", ext: fmt)
                    var p = props; p[kCGImagePropertyOrientation as String] = 1
                    try ImageEngine.write(img, properties: [:], to: dest, ext: fmt, quality: 0.95)
                    _ = p
                    return dest
                }.value
                outs.append(out)
                progress(Double(i + 1) / Double(files.count))
            }
            return outs
        }
    }
}
