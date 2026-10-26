import SwiftUI
import AVFoundation

enum AudioExport {
    static func ext(for url: URL) -> String {
        let e = Catalog.normalized(url.pathExtension)
        return ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"].contains(e) ? e : "m4a"
    }
    static func codec(for url: URL) -> [String] { FFmpeg.audioArgs(for: ext(for: url)) }

    /// Exécute ffmpeg avec un niveau de log « info » et renvoie stderr (mesures loudnorm).
    static func capture(_ args: [String]) async throws -> String {
        guard let ff = FFmpeg.ffmpeg else { throw MandarineError("ffmpeg est introuvable.") }
        return try await Task.detached {
            let p = Process(); p.executableURL = ff
            p.arguments = ["-nostdin", "-hide_banner", "-nostats"] + args
            let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
            try p.run()
            let d = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(data: d, encoding: .utf8) ?? ""
        }.value
    }

    static func loudness(_ url: URL, I: Double = -16, LRA: Double = 11, TP: Double = -1.5) async -> [String: String] {
        guard let out = try? await capture(["-i", url.path, "-af", "loudnorm=I=\(I):LRA=\(LRA):TP=\(TP):print_format=json", "-f", "null", "-"]),
              let s = out.range(of: "{", options: .backwards), let e = out.range(of: "}", options: .backwards), s.lowerBound < e.upperBound,
              let data = String(out[s.lowerBound..<e.upperBound]).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return j
    }
}

/// Carte de forme d'onde commune.
struct WaveCard: View {
    let peaks: [Float]
    var height: CGFloat = 120
    var body: some View {
        WaveformView(peaks: peaks).padding(.horizontal, 10).frame(height: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.04)))
    }
}

// MARK: Normalize
struct NormalizeTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var peaks: [Float] = []
    @State private var target = -16.0
    @State private var range = 11.0
    @State private var peak = -1.5
    @State private var measured: [String: String] = [:]

    var body: some View {
        ToolShell(title: "Normalize Volume", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(urls[0].lastPathComponent).sectionLabel(); Spacer(); Text(timecode(player.duration, centis: false)).sectionLabel() }
                ZStack {
                    WaveCard(peaks: peaks, height: 130)
                    GeometryReader { g in Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2).offset(x: g.size.width * CGFloat(player.time / max(player.duration, 0.01))) }
                }
                HStack {
                    Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                    Spacer()
                    Text("\(timecode(player.time)) / \(timecode(player.duration))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                param("Target loudness", $target, -30 ... -5, "%.0f LUFS")
                param("Loudness range", $range, 1 ... 20, "%.0f LU")
                param("True peak limit", $peak, -9 ... 0, "%.1f dBTP")
                if let i = measured["input_i"], let tp = measured["input_tp"] {
                    Text("Input: \(i) LUFS · peak \(tp) dBTP  →  Output: \(String(format: "%.0f", target)) LUFS · peak ≤ \(String(format: "%.1f", peak)) dBTP")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.text.opacity(0.8))
                }
                Text("−16 LUFS is a balanced default for spoken audio and music. The true peak limit helps prevent clipping after encoding.")
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 440)
        } footer: { Button("Normalize Audio") { apply() }.buttonStyle(PillButtonStyle()) }
        .task {
            await player.load(urls[0])
            peaks = await WaveformLoader.peaks(urls[0], count: 140).peaks
            measured = await AudioExport.loudness(urls[0])
        }
    }

    private func param(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ f: String) -> some View {
        HStack { Text(t).font(.system(size: 12)).frame(width: 110, alignment: .leading); Slider(value: v, in: r).controlSize(.small)
            Text(String(format: f, v.wrappedValue)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 84, alignment: .trailing) }
    }

    private func apply() {
        let (I, L, T, files) = (target, range, peak, urls)
        close()
        Dispatcher.job("Normalizing…") { progress in
            var outs: [URL] = []
            for f in files {
                let m = await AudioExport.loudness(f, I: I, LRA: L, TP: T)
                let info = await FFmpeg.probe(f)
                var filter = "loudnorm=I=\(I):LRA=\(L):TP=\(T)"
                if let a = m["input_i"], let b = m["input_lra"], let c = m["input_tp"], let d = m["input_thresh"], let e = m["target_offset"] {
                    filter += ":measured_I=\(a):measured_LRA=\(b):measured_TP=\(c):measured_thresh=\(d):offset=\(e):linear=true"
                }
                let ext = AudioExport.ext(for: f)
                let out = OutputNaming.sibling(of: f, suffix: " normalized", ext: ext)
                try await FFmpeg.run(["-i", f.path, "-vn", "-af", filter, "-ar", "48000"] + FFmpeg.audioArgs(for: ext) + [out.path], duration: info.duration, progress: progress)
                outs.append(out)
            }
            return outs
        }
    }
}

// MARK: Visualizer
struct VisualizerTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var peaks: [Float] = []
    @State private var stillStyle = false
    @State private var shape = 0
    @State private var still: URL?
    private let shapes: [(String, CGSize)] = [("Landscape · 16:9", CGSize(width: 1280, height: 720)), ("Portrait · 9:16", CGSize(width: 720, height: 1280)), ("Square · 1:1", CGSize(width: 1080, height: 1080))]

    var body: some View {
        ToolShell(title: "Audio Visualizer", close: close) {
            VStack(spacing: 12) {
                let s = shapes[shape].1, k = min(380 / s.width, 260 / s.height)
                ZStack {
                    Color.black
                    if stillStyle, let u = still, let img = NSImage(contentsOf: u) { Image(nsImage: img).resizable().scaledToFill() }
                    else { WaveformView(peaks: peaks, barWidth: 3).padding(24) }
                }.frame(width: s.width * k, height: s.height * k).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: 400, height: 270)
                HStack { Text("Style").sectionLabel(); Spacer()
                    Picker("", selection: $stillStyle) { Text("Waveform").tag(false); Text("Still image").tag(true) }.labelsHidden().frame(width: 150)
                        .onChange(of: stillStyle) { v in if v && still == nil { pickImage() } } }
                HStack { Text("Shape").sectionLabel(); Spacer()
                    Picker("", selection: $shape) { ForEach(Array(shapes.enumerated()), id: \.offset) { Text($1.0).tag($0) } }.labelsHidden().frame(width: 170) }
            }.frame(width: 400)
        } footer: { Button("Create Visualization") { apply() }.buttonStyle(PillButtonStyle()) }
        .task { peaks = await WaveformLoader.peaks(urls[0], count: 60).peaks }
    }

    private func pickImage() {
        Pickers.image { u in if let u = u { still = u } else { stillStyle = false } }
    }

    private func apply() {
        let f = urls[0], size = shapes[shape].1, img = stillStyle ? still : nil
        close()
        Dispatcher.job("Creating visualization…") { progress in
            let info = await FFmpeg.probe(f)
            let (w, h) = (Int(size.width), Int(size.height))
            let out = OutputNaming.sibling(of: f, suffix: " visualizer", ext: "mp4")
            var args: [String]
            if let img = img {
                args = ["-loop", "1", "-framerate", "30", "-i", img.path, "-i", f.path, "-vf", "scale=\(w):\(h):force_original_aspect_ratio=increase,crop=\(w):\(h),format=yuv420p", "-shortest"]
            } else {
                args = ["-i", f.path, "-filter_complex", "[0:a]showwaves=s=\(w)x\(h):mode=cline:colors=0xf35b28:rate=30:scale=sqrt,format=yuv420p[v]", "-map", "[v]", "-map", "0:a"]
            }
            args += FFmpeg.videoArgs(for: "mp4")
            try await FFmpeg.run(args + [out.path], duration: info.duration, progress: progress)
            return [out]
        }
    }
}

// MARK: Trim audio
struct TrimAudioTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var peaks: [Float] = []
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var trimSilence = false
    @State private var dur = 0.0            // durée réelle (décodage ffmpeg) = échelle commune affichage / lecture / coupe

    var body: some View {
        ToolShell(title: "Trim Audio", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Drag the ends to trim").sectionLabel(); Spacer(); Text("\(timecode(end - start)) selected").sectionLabel() }
                if dur > 0 {
                    TimeRangeSelector(duration: dur, start: $start, end: $end, playhead: player.isPlaying ? player.time : nil, onScrub: { player.seek($0) }) {
                        ZStack { Theme.orange.opacity(0.08); WaveformView(peaks: peaks) }
                    }.frame(height: 100)
                } else { Color.clear.frame(height: 100) }
                HStack {
                    Text("Start \(timecode(start))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("End \(timecode(end))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                }
                Toggle("Trim silent ends automatically", isOn: $trimSilence).onChange(of: trimSilence) { _ in autoTrim() }
                Button { player.loopRange = start...end; player.toggle() } label: {
                    Label(player.isPlaying ? "Pause" : "Play Selected Range", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                }.buttonStyle(PillButtonStyle()).frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(width: 420)
        } footer: { Button("Apply") { apply() }.buttonStyle(PillButtonStyle()) }
        .task {
            let w = await WaveformLoader.peaks(urls[0], count: 90)
            peaks = w.peaks
            dur = w.duration > 0 ? w.duration : (await FFmpeg.probe(urls[0])).duration
            start = 0; end = dur                      // la plage est prête tout de suite ; le lecteur se charge ensuite (transcodage éventuel)
            await player.load(urls[0], exact: true)
        }
    }

    private func autoTrim() {
        guard trimSilence, !peaks.isEmpty, let first = peaks.firstIndex(where: { $0 > 0.04 }), let last = peaks.lastIndex(where: { $0 > 0.04 }) else {
            if !trimSilence { start = 0; end = dur }; return
        }
        let d = dur / Double(peaks.count)
        start = Double(first) * d; end = min(dur, Double(last + 1) * d)
    }

    private func apply() {
        let (s, e, files) = (start, min(end, dur), urls)
        close()
        Dispatcher.job("Trimming audio…") { progress in
            var outs: [URL] = []
            for f in files {
                let ext = AudioExport.ext(for: f)
                let out = OutputNaming.sibling(of: f, suffix: " trimmed", ext: ext)
                try await FFmpeg.run(["-ss", String(s), "-i", f.path, "-t", String(e - s), "-vn"] + FFmpeg.audioArgs(for: ext) + [out.path], duration: e - s, progress: progress)
                outs.append(out)
            }
            return outs
        }
    }
}

// MARK: Channels
struct ChannelsTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var left: [Float] = []
    @State private var right: [Float] = []
    @State private var stereo = true
    @State private var lv = 1.0
    @State private var rv = 1.0
    @State private var rendering = false

    var body: some View {
        ToolShell(title: "Convert Audio Channels", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Output channel preview").sectionLabel()
                channel("L", left, lv)
                channel("R", right, rv)
                Divider()
                HStack { Text("Output").sectionLabel(); Spacer(); PillPicker(options: [(false, "Mono"), (true, "Stereo")], selection: $stereo) }
                volume("Left volume", $lv)
                volume("Right volume", $rv)
                HStack { Text("Preview").sectionLabel(); Spacer()
                    Button { Task { await preview() } } label: { Label(rendering ? "Rendering…" : "Play Output", systemImage: "play.fill") }.buttonStyle(PillButtonStyle()).disabled(rendering) }
            }.frame(width: 440)
        } footer: { Button("Apply") { apply() }.buttonStyle(PillButtonStyle()) }
        .task {
            let p = await WaveformLoader.peaks(urls[0], count: 70)
            left = p.left; right = p.right
        }
    }

    private func channel(_ name: String, _ peaks: [Float], _ vol: Double) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26).background(Circle().fill(Theme.orange.opacity(0.18)))
            WaveformView(peaks: peaks.map { min(1, $0 * Float(vol)) }, color: Theme.text.opacity(0.55), barWidth: 2).frame(height: 44)
                .padding(.horizontal, 8).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
        }
    }

    private func volume(_ t: String, _ v: Binding<Double>) -> some View {
        HStack { Text(t).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 90, alignment: .leading)
            Slider(value: v, in: 0...3).controlSize(.small)
            Text("\(Int(v.wrappedValue * 100))%").font(.system(size: 11).monospacedDigit()).frame(width: 48, alignment: .trailing) }
    }

    private func filter() -> String {
        let pan = stereo ? "pan=stereo|c0=\(lv)*c0|c1=\(rv)*c1" : "pan=mono|c0=\(lv / 2)*c0+\(rv / 2)*c1"
        // au-delà de 100 % le signal peut dépasser 0 dBFS : un limiteur évite l'écrêtage brutal
        return max(lv, rv) > 1 ? pan + ",alimiter=limit=0.97:level=disabled" : pan
    }

    private func preview() async {
        rendering = true
        defer { rendering = false }
        let tmp = OutputNaming.tempURL(ext: "wav")
        if (try? await FFmpeg.run(["-i", urls[0].path, "-vn", "-af", filter(), tmp.path])) != nil {
            await player.load(tmp); player.loopRange = nil; await MainActor.run { player.seek(0); player.play() }
        }
    }

    private func apply() {
        let (f, flt) = (urls[0], filter())
        close()
        Dispatcher.job("Converting channels…") { progress in
            let info = await FFmpeg.probe(f)
            let ext = AudioExport.ext(for: f)
            let out = OutputNaming.sibling(of: f, suffix: stereo ? " stereo" : " mono", ext: ext)
            try await FFmpeg.run(["-i", f.path, "-vn", "-af", flt] + FFmpeg.audioArgs(for: ext) + [out.path], duration: info.duration, progress: progress)
            return [out]
        }
    }
}

// MARK: Bleep
struct BleepTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var peaks: [Float] = []
    @State private var bleeps: [Region] = []
    @State private var drag: (id: UUID?, mode: Int, s: Double, e: Double)?
    @State private var rendering = false

    var body: some View {
        ToolShell(title: "Bleep Audio", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Bleeps").font(.system(size: 12, weight: .semibold)); Text("\(bleeps.count)").sectionLabel(); Spacer() }
                GeometryReader { geo in
                    let W = geo.size.width - 56, D = max(player.duration, 0.01)
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text("Bleep").sectionLabel().frame(width: 48, alignment: .leading)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05))
                                ForEach(bleeps) { b in
                                    let x0 = W * CGFloat(b.start / D), x1 = W * CGFloat(b.end / D)
                                    RoundedRectangle(cornerRadius: 7).fill(Theme.orange.opacity(0.8)).overlay(Text("Bleep").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
                                        .frame(width: max(24, x1 - x0), height: 34).offset(x: x0)
                                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("bleepLanes")).onChanged { v in adjust(b, v, W, D, 2) }.onEnded { _ in drag = nil })
                                        .contextMenu { Button("Delete") { bleeps.removeAll { $0.id == b.id } } }
                                    grip().offset(x: x0 + 3).gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("bleepLanes")).onChanged { v in adjust(b, v, W, D, 0) }.onEnded { _ in drag = nil })
                                    grip().offset(x: x1 - 7).gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("bleepLanes")).onChanged { v in adjust(b, v, W, D, 1) }.onEnded { _ in drag = nil })
                                }
                            }.frame(width: W, height: 38)
                            .gesture(DragGesture(minimumDistance: 4).onChanged { v in create(v, W, D) }.onEnded { _ in drag = nil })
                        }
                        HStack(spacing: 8) {
                            Text("Audio").sectionLabel().frame(width: 48, alignment: .leading)
                            WaveformView(peaks: peaks).frame(width: W, height: 70).background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
                        }
                        HStack { Spacer().frame(width: 56); Text(timecode(0, centis: false)).sectionLabel(); Spacer(); Text(timecode(player.duration)).sectionLabel() }
                    }
                }.frame(height: 160).coordinateSpace(name: "bleepLanes")
                Text("Drag across the Bleep layer to add a section, then drag a clip or either edge to adjust it. Right-click a clip to delete it.")
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack { Text("Preview").sectionLabel(); Spacer()
                    Button("Original") { Task { await player.load(urls[0]); await MainActor.run { player.loopRange = nil; player.seek(0); player.play() } } }.buttonStyle(PillButtonStyle())
                    Button { Task { await previewBleeps() } } label: { Label(rendering ? "Rendering…" : "With Bleeps", systemImage: "play.fill") }.buttonStyle(PillButtonStyle()).disabled(rendering || bleeps.isEmpty) }
            }.frame(width: 460)
        } footer: { Button("Save Bleeped Copy") { apply() }.buttonStyle(PillButtonStyle()).disabled(bleeps.isEmpty) }
        .task {
            await player.load(urls[0])
            peaks = await WaveformLoader.peaks(urls[0], count: 120).peaks
        }
    }

    private func grip() -> some View { Capsule().fill(Color.white).frame(width: 3, height: 18).frame(width: 14, height: 34) }

    private func create(_ v: DragGesture.Value, _ W: CGFloat, _ D: Double) {
        if drag == nil {
            let s = Double(v.startLocation.x / W) * D
            let r = Region(rect: .zero, start: s, end: s + 0.1)
            bleeps.append(r); drag = (r.id, 1, s, s)
        }
        guard let d = drag, let id = d.id, let i = bleeps.firstIndex(where: { $0.id == id }) else { return }
        let t = min(max(0, Double(v.location.x / W) * D), D)
        bleeps[i].start = min(d.s, t); bleeps[i].end = max(d.s, t, d.s + 0.1)
    }

    private func adjust(_ b: Region, _ v: DragGesture.Value, _ W: CGFloat, _ D: Double, _ mode: Int) {
        if drag?.id != b.id { drag = (b.id, mode, b.start, b.end) }
        guard let d = drag, let i = bleeps.firstIndex(where: { $0.id == b.id }) else { return }
        let dt = Double(v.translation.width / W) * D
        switch mode {
        case 0: bleeps[i].start = min(max(0, d.s + dt), bleeps[i].end - 0.1)
        case 1: bleeps[i].end = max(min(D, d.e + dt), bleeps[i].start + 0.1)
        default:
            let len = d.e - d.s, s = min(max(0, d.s + dt), D - len)
            bleeps[i].start = s; bleeps[i].end = s + len
        }
    }

    private static func filter(_ rs: [Region]) -> (String, Int) {
        let en = rs.map { "between(t,\($0.start),\($0.end))" }.joined(separator: "+")
        var f = "[0:a]volume=enable='\(en)':volume=0[m];"
        for (i, r) in rs.enumerated() { f += "[\(i + 1):a]adelay=\(Int(r.start * 1000)):all=1,volume=0.4[b\(i)];" }
        f += "[m]" + rs.indices.map { "[b\($0)]" }.joined() + "amix=inputs=\(rs.count + 1):normalize=0:duration=first[out]"
        return (f, rs.count)
    }

    private static func args(_ file: URL, _ rs: [Region]) -> [String] {
        var a = ["-i", file.path]
        for r in rs { a += ["-f", "lavfi", "-t", String(r.end - r.start), "-i", "sine=frequency=1000:sample_rate=44100"] }
        return a + ["-filter_complex", filter(rs).0, "-map", "[out]"]
    }

    private func previewBleeps() async {
        rendering = true; defer { rendering = false }
        let tmp = OutputNaming.tempURL(ext: "wav")
        if (try? await FFmpeg.run(Self.args(urls[0], bleeps) + [tmp.path])) != nil {
            await player.load(tmp); await MainActor.run { player.loopRange = nil; player.seek(0); player.play() }
        }
    }

    private func apply() {
        let (f, rs) = (urls[0], bleeps)
        close()
        Dispatcher.job("Saving bleeped copy…") { progress in
            let info = await FFmpeg.probe(f)
            let ext = AudioExport.ext(for: f)
            let out = OutputNaming.sibling(of: f, suffix: " bleeped", ext: ext)
            try await FFmpeg.run(Self.args(f, rs) + FFmpeg.audioArgs(for: ext) + [out.path], duration: info.duration, progress: progress)
            return [out]
        }
    }
}
