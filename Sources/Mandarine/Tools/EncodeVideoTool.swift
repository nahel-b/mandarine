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
        ToolShell(title: L("Export Video"), close: close) {
            VStack(alignment: .leading, spacing: 11) {
                sourceCard
                if VideoEncoder.isHDR(info) && o.preserveColor {
                    Label(L("HDR video: it is exported as 10-bit HEVC so the colors stay right (8-bit H.264 would look gray and washed out)."), systemImage: "sun.max")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                row(L("Preset")) {
                    Picker("", selection: $presetID) {
                        ForEach(VideoEncoder.presets) { Text(L($0.title)).tag($0.id) }
                    }.labelsHidden().frame(width: 270)
                    .onChange(of: presetID) { id in if let p = VideoEncoder.presets.first(where: { $0.id == id }) { var n = o; p.apply(&n); o = n; syncResolution() } }
                }
                Divider()
                row(L("Format")) {
                    PillPicker(options: o.encoder == .proRes ? [("mov", "MOV"), ("mkv", "MKV")] : [("mp4", "MP4"), ("mov", "MOV"), ("mkv", "MKV")], selection: $o.container)
                }
                row(L("Video codec")) {
                    Picker("", selection: $o.encoder) { ForEach(EncoderKind.allCases) { Text(L($0.title)).tag($0) } }.labelsHidden().frame(width: 220)
                        .onChange(of: o.encoder) { e in if e == .proRes { o.container = "mov" } }
                }
                if o.encoder == .proRes {
                    row(L("ProRes profile")) {
                        Picker("", selection: $o.proResProfile) { ForEach(ProResProfile.all, id: \.id) { Text($0.name).tag($0.id) } }.labelsHidden().frame(width: 120)
                    }
                    Text(L("Editing codec: large files (about \(ProResProfile.all.first { $0.id == o.proResProfile }?.mbps ?? 0) Mb/s in 1080p), smooth to edit. Audio is saved as uncompressed PCM.")).sectionLabel().fixedSize(horizontal: false, vertical: true)
                }
                row(L("Resolution")) {
                    HStack(spacing: 8) {
                        if resChoice == -1 {
                            TextField("", value: $customSide, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 70).multilineTextAlignment(.trailing)
                            Text(L("px long side")).sectionLabel()
                        }
                        Picker("", selection: $resChoice) { ForEach(resolutions, id: \.1) { Text(L($0.0)).tag($0.1) } }.labelsHidden().frame(width: 170)
                    }
                    .onChange(of: resChoice) { c in o.longSide = c == -1 ? customSide : c }
                    .onChange(of: customSide) { v in if resChoice == -1 { o.longSide = max(64, v) } }
                }
                row(L("Frame rate")) {
                    Picker("", selection: $o.fps) { ForEach(rates, id: \.1) { Text(L($0.0)).tag($0.1) } }.labelsHidden().frame(width: 170)
                }
                if o.encoder != .proRes {
                row(L("Rate control")) {
                    PillPicker(options: [(RateMode.quality, "Constant quality"), (.bitrate, "Average bitrate")], selection: $o.mode)
                }
                if o.mode == .quality {
                    HStack(spacing: 10) {
                        Text(L("Higher quality")).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Slider(value: Binding(get: { Double(o.crf) }, set: { o.crf = Int($0.rounded()) }), in: 10...35, step: 1).controlSize(.small)
                        Text(L("Smaller file")).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Text(L("RF \(o.crf)")).font(.system(size: 12, weight: .semibold).monospacedDigit()).frame(width: 52, alignment: .trailing)
                    }
                    Text(L(qualityHint)).sectionLabel()
                } else {
                    HStack(spacing: 8) {
                        TextField("", value: $o.bitrateKbps, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        Text(L("kb/s")).sectionLabel()
                        Toggle(L("2-pass"), isOn: $o.twoPass).font(.system(size: 12)).disabled(o.encoder == .hardware264)
                        Spacer()
                        if duration > 0 { Text(L("≈ \(Int64(Double(o.bitrateKbps) * 125 * duration + Double(o.audioKbps) * 125 * duration).humanSize)")).font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                    }
                }
                row(L("Encoder speed")) {
                    HStack {
                        Text(L("Faster")).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Slider(value: Binding(get: { Double(VideoEncoder.x264Presets.firstIndex(of: o.preset) ?? 5) }, set: { o.preset = VideoEncoder.x264Presets[Int($0.rounded())] }),
                               in: 0...Double(VideoEncoder.x264Presets.count - 1), step: 1).controlSize(.small).frame(width: 120)
                        Text(L("Better")).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Text(L(o.preset)).font(.system(size: 11, weight: .medium)).frame(width: 62, alignment: .trailing)
                    }.disabled(o.encoder == .hardware264)
                }
                }
                Divider()
                HStack {
                    Toggle(isOn: $o.preserveColor) { Label(L("Keep original colors"), systemImage: "paintpalette").font(.system(size: 12, weight: .medium)) }
                    Spacer()
                    Text(L(colorSummary)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                if o.encoder != .proRes {
                row(L("Audio")) {
                    HStack {
                        Picker("", selection: $o.audio) { Text(L("AAC")).tag("aac"); Text(L("Keep original")).tag("copy"); Text(L("None")).tag("none") }.labelsHidden().frame(width: 130)
                        if o.audio == "aac" {
                            Picker("", selection: $o.audioKbps) { ForEach([96, 128, 160, 192, 256, 320], id: \.self) { Text(L("\($0) kb/s")).tag($0) } }.labelsHidden().frame(width: 110)
                        }
                    }
                }
                }
                if o.encoder != .proRes {
                DisclosureGroup(L("Advanced"), isExpanded: $showAdvanced) {
                    VStack(spacing: 8) {
                        row(L("Bit depth")) { PillPicker(options: [(false, "8-bit (compatible)"), (true, "10-bit (HEVC)")], selection: $o.tenBit) }
                        row(L("Profile")) { Picker("", selection: $o.profile) { ForEach(["auto", "baseline", "main", "high"], id: \.self) { Text(L($0.capitalized)).tag($0) } }.labelsHidden().frame(width: 120) }
                        row(L("Tune")) { Picker("", selection: $o.tune) { ForEach(["none", "film", "animation", "grain"], id: \.self) { Text(L($0.capitalized)).tag($0) } }.labelsHidden().frame(width: 120) }
                        Toggle(L("Allow upscaling"), isOn: $o.allowUpscale).font(.system(size: 12))
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                }
                HStack {
                    Button { Task { await test() } } label: { Label(estimating ? L("Testing…") : L("Test 10 s"), systemImage: L("timer")) }
                        .buttonStyle(PillButtonStyle()).disabled(estimating)
                    Text(L(estimate)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                    Spacer()
                }
            }.frame(width: 460, alignment: .leading).font(.system(size: 12))
        } footer: {
            ReplaceButton(L("Encode"), prominent: true) { run() }
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
        HStack { Text(L(t)).foregroundStyle(Theme.muted); Spacer(); v() }
    }

    private var sourceCard: some View {
        let fps = info.fps > 0 ? String(format: "%.3g", info.fps) : "–"
        return HStack(spacing: 12) {
            Image(systemName: "film").font(.system(size: 20)).foregroundStyle(Theme.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(urls[0].lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(L("\(info.width)×\(info.height) · \(fps) fps · \(info.codec.uppercased()) \(info.pixFmt) · \(timecode(info.duration, centis: false)) · \(urls[0].fileSize.humanSize)"))
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
        Dispatcher.job(L("Encoding…"), subtitle: files.count == 1 ? files[0].lastPathComponent : L("\(files.count) videos"), count: files.count, replaces: files) { progress in
            let batch = Batch(total: files.count)
            for (i, f) in files.enumerated() {
                try await batch.run(f) {
                let names = [3840: "4K", 2560: "1440p", 1920: "1080p", 1280: "720p", 854: "480p"]
                let suffix = opts.longSide > 0 ? " " + (names[opts.longSide] ?? "\(opts.longSide)px") : " encoded"
                let out = OutputNaming.sibling(of: f, suffix: suffix, ext: opts.container)
                try await VideoEncoder.encode(opts, input: f, output: out) { p in progress((Double(i) + p) / Double(files.count)) }
                return [out]
                }
            }
            return try batch.finish()
        }
    }
}
