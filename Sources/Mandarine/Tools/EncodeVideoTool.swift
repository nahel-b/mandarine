import SwiftUI

/// Export vidéo façon HandBrake : préréglages, taille, cadence, qualité (RF) ou débit moyen, préréglage de l'encodeur, audio, couleur préservée.
struct EncodeVideoTool: View {
    let urls: [URL]
    let close: () -> Void

    @State private var o = EncodeOptions()
    @State private var presetID = VideoEncoder.presets[0].id
    @State private var info = MediaInfo()
    @State private var showAdvanced = false
    @State private var resChoice = 1920            // -1 = taille personnalisée
    @State private var customSide = 2560
    @State private var estimate: String = ""
    @State private var estimating = false

    private var duration: Double { info.duration }
    private let resolutions: [(String, Int)] = [("Same as source", 0), ("4K (3840)", 3840), ("1440p (2560)", 2560), ("1080p (1920)", 1920), ("720p (1280)", 1280), ("480p (854)", 854), ("Custom…", -1)]
    private let rates: [(String, Double)] = [("Same as source", 0), ("23.976", 23.976), ("24", 24), ("25", 25), ("29.97", 29.97), ("30", 30), ("50", 50), ("60", 60)]

    var body: some View {
        ToolShell(title: "Export Video", close: close) {
            VStack(alignment: .leading, spacing: 11) {
                sourceCard
                row("Preset") {
                    Picker("", selection: $presetID) {
                        ForEach(VideoEncoder.presets) { Text($0.title).tag($0.id) }
                    }.labelsHidden().frame(width: 270)
                    .onChange(of: presetID) { id in if let p = VideoEncoder.presets.first(where: { $0.id == id }) { var n = o; p.apply(&n); o = n; syncResolution() } }
                }
                Divider()
                row("Format") {
                    PillPicker(options: [("mp4", "MP4"), ("mov", "MOV"), ("mkv", "MKV")], selection: $o.container)
                }
                row("Video codec") {
                    Picker("", selection: $o.encoder) { ForEach(EncoderKind.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 220)
                }
                row("Resolution") {
                    HStack(spacing: 8) {
                        if resChoice == -1 {
                            TextField("", value: $customSide, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
                            Text("px long side").sectionLabel()
                        }
                        Picker("", selection: $resChoice) { ForEach(resolutions, id: \.1) { Text($0.0).tag($0.1) } }.labelsHidden().frame(width: 170)
                    }
                    .onChange(of: resChoice) { c in o.longSide = c == -1 ? customSide : c }
                    .onChange(of: customSide) { v in if resChoice == -1 { o.longSide = max(64, v) } }
                }
                row("Frame rate") {
                    Picker("", selection: $o.fps) { ForEach(rates, id: \.1) { Text($0.0).tag($0.1) } }.labelsHidden().frame(width: 170)
                }
                row("Rate control") {
                    PillPicker(options: [(RateMode.quality, "Constant quality"), (.bitrate, "Average bitrate")], selection: $o.mode)
                }
                if o.mode == .quality {
                    HStack(spacing: 10) {
                        Text("Higher quality").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Slider(value: Binding(get: { Double(o.crf) }, set: { o.crf = Int($0.rounded()) }), in: 10...35, step: 1).controlSize(.small)
                        Text("Smaller file").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Text("RF \(o.crf)").font(.system(size: 12, weight: .semibold).monospacedDigit()).frame(width: 52, alignment: .trailing)
                    }
                    Text(qualityHint).sectionLabel()
                } else {
                    HStack(spacing: 8) {
                        TextField("", value: $o.bitrateKbps, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Text("kb/s").sectionLabel()
                        Toggle("2-pass", isOn: $o.twoPass).font(.system(size: 12)).disabled(o.encoder == .hardware264)
                        Spacer()
                        if duration > 0 { Text("≈ \(Int64(Double(o.bitrateKbps) * 125 * duration + Double(o.audioKbps) * 125 * duration).humanSize)").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                    }
                }
                row("Encoder speed") {
                    HStack {
                        Text("Faster").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Slider(value: Binding(get: { Double(VideoEncoder.x264Presets.firstIndex(of: o.preset) ?? 5) }, set: { o.preset = VideoEncoder.x264Presets[Int($0.rounded())] }),
                               in: 0...Double(VideoEncoder.x264Presets.count - 1), step: 1).controlSize(.small).frame(width: 120)
                        Text("Better").font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Text(o.preset).font(.system(size: 11, weight: .medium)).frame(width: 62, alignment: .trailing)
                    }.disabled(o.encoder == .hardware264)
                }
                Divider()
                HStack {
                    Toggle(isOn: $o.preserveColor) { Label("Keep original colors", systemImage: "paintpalette").font(.system(size: 12, weight: .medium)) }
                    Spacer()
                    Text(colorSummary).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                row("Audio") {
                    HStack {
                        Picker("", selection: $o.audio) { Text("AAC").tag("aac"); Text("Keep original").tag("copy"); Text("None").tag("none") }.labelsHidden().frame(width: 130)
                        if o.audio == "aac" {
                            Picker("", selection: $o.audioKbps) { ForEach([96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0) kb/s").tag($0) } }.labelsHidden().frame(width: 110)
                        }
                    }
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(spacing: 8) {
                        row("Bit depth") { PillPicker(options: [(false, "8-bit (compatible)"), (true, "10-bit")], selection: $o.tenBit) }
                        row("Profile") { Picker("", selection: $o.profile) { ForEach(["auto", "baseline", "main", "high"], id: \.self) { Text($0.capitalized).tag($0) } }.labelsHidden().frame(width: 120) }
                        row("Tune") { Picker("", selection: $o.tune) { ForEach(["none", "film", "animation", "grain"], id: \.self) { Text($0.capitalized).tag($0) } }.labelsHidden().frame(width: 120) }
                        Toggle("Allow upscaling", isOn: $o.allowUpscale).font(.system(size: 12))
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                HStack {
                    Button { Task { await test() } } label: { Label(estimating ? "Testing…" : "Test 10 s", systemImage: "timer") }
                        .buttonStyle(PillButtonStyle()).disabled(estimating)
                    Text(estimate).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                    Spacer()
                }
            }.frame(width: 460, alignment: .leading).font(.system(size: 12))
        } footer: {
            Button("Encode") { run() }.buttonStyle(PillButtonStyle(prominent: true))
        }
        .task {
            info = await FFmpeg.probe(urls[0])
            if let p = VideoEncoder.presets.first { var n = o; p.apply(&n); o = n; syncResolution() }
            if info.hasAudio == false { o.audio = "none" }
        }
    }

    private func syncResolution() {
        resChoice = resolutions.contains(where: { $0.1 == o.longSide && $0.1 != -1 }) ? o.longSide : -1
        if resChoice == -1 { customSide = o.longSide }
    }

    private func row<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack { Text(t).foregroundStyle(Theme.muted); Spacer(); v() }
    }

    private var sourceCard: some View {
        let fps = info.fps > 0 ? String(format: "%.3g", info.fps) : "–"
        return HStack(spacing: 12) {
            Image(systemName: "film").font(.system(size: 20)).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(urls[0].lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text("\(info.width)×\(info.height) · \(fps) fps · \(info.codec.uppercased()) \(info.pixFmt) · \(timecode(info.duration, centis: false)) · \(urls[0].fileSize.humanSize)")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer()
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.05)))
    }

    private var colorSummary: String {
        let t = VideoEncoder.colorTags(info)
        let space = t.space == "smpte170m" ? "BT.601" : (t.space == "bt2020nc" ? "BT.2020" : t.space.uppercased().replacingOccurrences(of: "BT", with: "BT."))
        return o.preserveColor ? "\(space) · \(t.range == "pc" ? "full" : "limited") range" + (info.colorSpace.isEmpty || info.colorSpace == "unknown" ? " (assumed)" : "") : "converted by the encoder"
    }

    private var qualityHint: String {
        switch o.crf {
        case ..<16: return "Near-lossless. Very large files."
        case 16...18: return "Excellent quality, ideal for archiving or re-editing."
        case 19...21: return "High quality — HandBrake's default range (RF 20)."
        case 22...24: return "Good quality, noticeably smaller."
        default: return "Small files, visible compression."
        }
    }

    private func test() async {
        estimating = true; estimate = ""
        defer { estimating = false }
        do {
            let r = try await VideoEncoder.estimate(o, input: urls[0])
            estimate = "≈ \(r.projectedBytes.humanSize) total · \(String(format: "%.1f", r.bytesPerSecond * 8 / 1_000_000)) Mb/s"
            try? FileManager.default.removeItem(at: r.sample)
        } catch { estimate = error.localizedDescription }
    }

    private func run() {
        let (opts, files) = (o, urls)
        close()
        Dispatcher.job("Encoding…", subtitle: files.count == 1 ? files[0].lastPathComponent : "\(files.count) videos") { progress in
            var outs: [URL] = []
            for (i, f) in files.enumerated() {
                let names = [3840: "4K", 2560: "1440p", 1920: "1080p", 1280: "720p", 854: "480p"]
                let suffix = opts.longSide > 0 ? " " + (names[opts.longSide] ?? "\(opts.longSide)px") : " encoded"
                let out = OutputNaming.sibling(of: f, suffix: suffix, ext: opts.container)
                try await VideoEncoder.encode(opts, input: f, output: out) { p in progress((Double(i) + p) / Double(files.count)) }
                outs.append(out)
            }
            return outs
        }
    }
}
