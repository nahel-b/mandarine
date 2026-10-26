import Foundation

enum EncoderKind: String, CaseIterable, Identifiable {
    case x264, x265, hardware264
    var id: String { rawValue }
    var title: String {
        switch self {
        case .x264: return "H.264 (x264)"
        case .x265: return "H.265 (x265)"
        case .hardware264: return "H.264 (VideoToolbox, fast)"
        }
    }
}

enum RateMode: String { case quality, bitrate }

/// Réglages d'export vidéo façon HandBrake.
struct EncodeOptions: Equatable {
    var container = "mp4"                 // mp4 | mov | mkv
    var encoder = EncoderKind.x264
    var longSide = 1920                   // 0 = identique à la source
    var allowUpscale = false
    var fps: Double = 30                  // 0 = identique à la source
    var mode = RateMode.quality
    var crf = 18                          // « RF » : plus bas = meilleure qualité
    var bitrateKbps = 8000
    var twoPass = true
    var preset = "slow"                   // ultrafast … veryslow
    var profile = "auto"                  // auto | baseline | main | high
    var tenBit = false
    var tune = "none"                     // none | film | animation | grain
    var preserveColor = true
    var audio = "aac"                     // aac | copy | none
    var audioKbps = 256
}

struct EncodePreset: Identifiable {
    let id: String
    let title: String
    let apply: (inout EncodeOptions) -> Void
}

enum VideoEncoder {
    static let presets: [EncodePreset] = [
        .init(id: "prores-1080", title: "ProRes / 4K → 1080p30 (high quality)") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 1920; o.fps = 30; o.mode = .quality; o.crf = 18; o.preset = "slow"; o.tenBit = false; o.audioKbps = 256; o.preserveColor = true },
        .init(id: "prores-4k", title: "ProRes / 4K → 4K H.264 (high quality)") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 3840; o.fps = 0; o.mode = .quality; o.crf = 18; o.preset = "slow"; o.tenBit = false; o.audioKbps = 256; o.preserveColor = true },
        .init(id: "super-hq", title: "Super HQ 1080p30") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 1920; o.fps = 30; o.mode = .quality; o.crf = 16; o.preset = "slower"; o.audioKbps = 256 },
        .init(id: "fast-1080", title: "Fast 1080p30") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 1920; o.fps = 30; o.mode = .quality; o.crf = 22; o.preset = "veryfast"; o.audioKbps = 160 },
        .init(id: "fast-720", title: "Very Fast 720p30 (small)") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 1280; o.fps = 30; o.mode = .quality; o.crf = 24; o.preset = "veryfast"; o.audioKbps = 128 },
        .init(id: "keep-4k", title: "4K H.264, keep frame rate") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 0; o.fps = 0; o.mode = .quality; o.crf = 19; o.preset = "medium"; o.audioKbps = 256 },
        .init(id: "web-bitrate", title: "1080p30 at 8 Mb/s (2-pass)") { o in
            o.container = "mp4"; o.encoder = .x264; o.longSide = 1920; o.fps = 30; o.mode = .bitrate; o.bitrateKbps = 8000; o.twoPass = true; o.preset = "slow"; o.audioKbps = 192 }
    ]

    static let x264Presets = ["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"]

    // MARK: Couleur
    /// Étiquettes couleur à reporter sur la sortie. Si la source n'en a pas, on suppose l'usage courant : BT.709 pour le HD, BT.601 en SD ; limité (tv).
    struct ColorTags { var space: String, primaries: String, transfer: String, range: String, matrix: String }

    static func colorTags(_ i: MediaInfo) -> ColorTags {
        func known(_ s: String) -> String? { (s.isEmpty || s == "unknown" || s == "reserved") ? nil : s }
        let hd = max(i.width, i.height) >= 1280
        let space = known(i.colorSpace) ?? (hd ? "bt709" : "smpte170m")
        let primaries = known(i.colorPrimaries) ?? (hd ? "bt709" : "smpte170m")
        let transfer = known(i.colorTransfer) ?? (hd ? "bt709" : "smpte170m")
        let range = known(i.colorRange) ?? "tv"
        // nom attendu par le filtre « scale » pour la matrice
        let matrix: String
        switch space {
        case "bt2020nc", "bt2020c": matrix = "bt2020"
        case "bt470bg": matrix = "bt470"
        case "smpte170m": matrix = "smpte170m"
        case "smpte240m": matrix = "smpte240m"
        case "fcc": matrix = "fcc"
        default: matrix = "bt709"
        }
        return ColorTags(space: space, primaries: primaries, transfer: transfer, range: range, matrix: matrix)
    }

    // MARK: Arguments ffmpeg
    /// `pass` : nil = une seule passe ; 1 ou 2 pour le mode débit moyen en deux passes.
    static func arguments(_ o: EncodeOptions, info: MediaInfo, input: URL, output: URL, pass: Int? = nil, passLog: String = "", clip: (start: Double, length: Double)? = nil) -> [String] {
        var a: [String] = []
        if let c = clip { a += ["-ss", String(c.start)] }
        a += ["-i", input.path]
        if let c = clip { a += ["-t", String(c.length)] }
        a += ["-map", "0:v:0"]
        if o.audio != "none" && info.hasAudio && pass != 1 { a += ["-map", "0:a:0?"] }

        let tags = colorTags(info)
        var vf: [String] = []
        // 1) redimensionnement : Lanczos, matrices explicites (aucun décalage de teinte lors du passage 4:2:2 10 bits → 4:2:0)
        var scale = "scale="
        if o.longSide > 0 {
            let L = o.longSide
            let cap = o.allowUpscale ? "\(L)" : "min(\(L),iw)"
            let capH = o.allowUpscale ? "\(L)" : "min(\(L),ih)"
            scale += "w='if(gte(iw,ih),\(cap),-2)':h='if(gte(iw,ih),-2,\(capH))':"
        }
        scale += "flags=lanczos+accurate_rnd+full_chroma_int"
        if o.preserveColor { scale += ":in_color_matrix=\(tags.matrix):out_color_matrix=\(tags.matrix):in_range=\(tags.range):out_range=\(tags.range)" }
        vf.append(scale)
        // 2) cadence
        if o.fps > 0 { vf.append("fps=\(o.fps == 29.97 ? "30000/1001" : (o.fps == 23.976 ? "24000/1001" : String(o.fps)))") }
        // 3) format de pixels
        vf.append("format=\(o.tenBit ? "yuv420p10le" : "yuv420p")")
        a += ["-vf", vf.joined(separator: ",")]

        // encodeur
        switch o.encoder {
        case .x264, .x265:
            a += ["-c:v", o.encoder == .x264 ? "libx264" : "libx265", "-preset", o.preset]
            if o.encoder == .x264 {
                let profile = o.profile == "auto" ? (o.tenBit ? "high10" : "high") : o.profile
                a += ["-profile:v", profile]
                if o.tune != "none" { a += ["-tune", o.tune] }
            } else {
                a += ["-tag:v", "hvc1"]
            }
        case .hardware264:
            a += ["-c:v", "h264_videotoolbox", "-allow_sw", "1", "-profile:v", o.profile == "auto" ? "high" : o.profile]
        }
        // débit / qualité
        switch o.mode {
        case .quality:
            if o.encoder == .hardware264 { a += ["-q:v", String(max(1, min(100, 100 - o.crf * 2)))] }   // approximation : RF bas → q élevé
            else { a += ["-crf", String(o.crf)] }
        case .bitrate:
            a += ["-b:v", "\(o.bitrateKbps)k", "-maxrate", "\(Int(Double(o.bitrateKbps) * 1.5))k", "-bufsize", "\(o.bitrateKbps * 2)k"]
            if let p = pass, o.encoder != .hardware264 { a += ["-pass", String(p), "-passlogfile", passLog] }
        }
        // étiquettes couleur de la sortie (identiques à la source)
        if o.preserveColor {
            a += ["-colorspace", tags.space, "-color_primaries", tags.primaries, "-color_trc", tags.transfer, "-color_range", tags.range]
        }
        // audio
        if pass == 1 || o.audio == "none" || !info.hasAudio { a += ["-an"] }
        else if o.audio == "copy" { a += ["-c:a", "copy"] }
        else { a += ["-c:a", "aac", "-b:a", "\(o.audioKbps)k"] }

        if o.container != "mkv" { a += ["-movflags", "+faststart"] }
        a += ["-map_metadata", "0"]
        if pass == 1 { a += ["-f", "null", "/dev/null"] } else { a += [output.path] }
        return a
    }

    // MARK: Exécution
    static func encode(_ o: EncodeOptions, input: URL, output: URL, progress: @escaping (Double) -> Void) async throws {
        let info = await FFmpeg.probe(input)
        if o.mode == .bitrate && o.twoPass && o.encoder != .hardware264 {
            let log = OutputNaming.tempURL(ext: "").path
            defer { for ext in ["-0.log", "-0.log.mbtree", ".log", ".log.mbtree"] { try? FileManager.default.removeItem(atPath: log + ext) } }
            try await FFmpeg.run(arguments(o, info: info, input: input, output: output, pass: 1, passLog: log), duration: info.duration) { progress($0 * 0.45) }
            try await FFmpeg.run(arguments(o, info: info, input: input, output: output, pass: 2, passLog: log), duration: info.duration) { progress(0.45 + $0 * 0.55) }
        } else {
            try await FFmpeg.run(arguments(o, info: info, input: input, output: output), duration: info.duration, progress: progress)
        }
    }

    /// Encode 10 s au milieu de la vidéo avec les mêmes réglages, pour estimer la taille finale.
    static func estimate(_ o: EncodeOptions, input: URL) async throws -> (bytesPerSecond: Double, projectedBytes: Int64, sample: URL) {
        let info = await FFmpeg.probe(input)
        let length = min(10, max(2, info.duration))
        let start = max(0, info.duration / 2 - length / 2)
        let out = OutputNaming.tempURL(ext: o.container)
        var single = o; single.twoPass = false                     // l'estimation se fait en une passe
        try await FFmpeg.run(arguments(single, info: info, input: input, output: out, clip: (start, length)), duration: length)
        let size = out.fileSize
        let bps = Double(size) / length
        return (bps, Int64(bps * info.duration), out)
    }
}
