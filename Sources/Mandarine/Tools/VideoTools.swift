import SwiftUI
import AVFoundation

enum VideoExport {
    static func ext(for url: URL) -> String {
        let e = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv"].contains(e) ? e : "mp4"
    }
    static func codecArgs(for url: URL) -> [String] { FFmpeg.videoArgs(for: ext(for: url)) }
    static func even(_ v: Double) -> Int { max(2, Int(v.rounded()) / 2 * 2) }
}

/// Fenêtre de prévisualisation vidéo commune.
struct VideoPreview: View {
    @ObservedObject var player: PlayerController
    var height: CGFloat = 300
    var body: some View {
        VideoSurface(player: player.player)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Theme.previewBG)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { player.toggle() }
    }
}

// MARK: Trim
struct TrimVideoTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var ready = false

    var body: some View {
        ToolShell(title: "Trim Video", close: close) {
            VStack(spacing: 8) {
                VideoPreview(player: player, height: 300)
                HStack { Text("Drag the ends to trim").sectionLabel(); Spacer(); Text("\(timecode(end - start)) selected").sectionLabel() }
                if ready {
                    TimeRangeSelector(duration: player.duration, start: $start, end: $end, playhead: player.time, onScrub: { player.seek($0) }) {
                        FilmStrip(url: urls[0], duration: player.duration)
                    }.frame(height: 56)
                }
                HStack {
                    timeField("Start", $start, 0, { end })
                    Spacer()
                    timeField("End", $end, nil, { player.duration })
                }
                HStack(spacing: 14) {
                    Button { player.step(-1) } label: { Image(systemName: "backward.frame") }.buttonStyle(.plain)
                    Button { player.loopRange = start...end; player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                    Button { player.step(1) } label: { Image(systemName: "forward.frame") }.buttonStyle(.plain)
                    Spacer()
                    Text("\(timecode(player.time)) / \(timecode(player.duration))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                }
            }.frame(width: 400)
        } footer: {
            Button("Apply") { apply() }.buttonStyle(PillButtonStyle())
        }
        .task {
            await player.load(urls[0]); end = player.duration; ready = true
        }
    }

    private func timeField(_ label: String, _ v: Binding<Double>, _ lo: Double?, _ hi: () -> Double) -> some View {
        HStack(spacing: 4) {
            Text(label).sectionLabel()
            TextField("", text: Binding(get: { timecode(v.wrappedValue) }, set: { if let t = parseTimecode($0) { v.wrappedValue = min(max(t, 0), player.duration) } }))
                .textFieldStyle(.roundedBorder).frame(width: 78).font(.system(size: 11).monospacedDigit())
        }
    }

    private func apply() {
        let s = start, e = end, files = urls
        close()
        Dispatcher.job("Trimming…") { progress in
            var outs: [URL] = []
            for f in files {
                let out = OutputNaming.sibling(of: f, suffix: " trimmed", ext: VideoExport.ext(for: f))
                try await FFmpeg.run(["-ss", String(s), "-i", f.path, "-t", String(e - s)] + VideoExport.codecArgs(for: f) + [out.path], duration: e - s, progress: progress)
                outs.append(out)
            }
            return outs
        }
    }
}

// MARK: Crop
struct CropVideoTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var regions = [Region(rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
    @State private var selected: UUID?
    @State private var ratio = AspectRatioChoice.all[0]
    @State private var pos = 0.0

    var body: some View {
        ToolShell(title: "Crop Video", close: close) {
            VStack(spacing: 10) {
                RegionEditor(contentSize: player.size == .zero ? CGSize(width: 16, height: 9) : player.size, regions: $regions, selected: $selected, lockAspect: ratio.ratio, dimOutside: true) {
                    VideoSurface(player: player.player)
                }.frame(width: 400, height: 380)
                CropControls(pixelSize: player.size == .zero ? CGSize(width: 16, height: 9) : player.size, region: $regions[0], ratio: $ratio)
                Scrubber(value: $pos, range: player.duration) { player.pause(); player.seek($0) }
                FrameStepRow(player: player, showPlay: false)
            }.frame(width: 400)
        } footer: {
            Button("Reset") { regions[0].rect = CGRect(x: 0, y: 0, width: 1, height: 1); ratio = AspectRatioChoice.all[0] }.buttonStyle(PillButtonStyle())
            Button("Apply") { apply() }.buttonStyle(PillButtonStyle())
        }
        .task { await player.load(urls[0]) }
        .onReceive(player.$time) { pos = $0 }
    }

    private func apply() {
        let r = regions[0].rect, files = urls
        close()
        Dispatcher.job("Cropping video…") { progress in
            var outs: [URL] = []
            for f in files {
                let info = await FFmpeg.probe(f)
                let w = VideoExport.even(r.width * Double(info.width)), h = VideoExport.even(r.height * Double(info.height))
                let x = Int(r.minX * Double(info.width)) / 2 * 2, y = Int(r.minY * Double(info.height)) / 2 * 2
                let out = OutputNaming.sibling(of: f, suffix: " cropped", ext: VideoExport.ext(for: f))
                var args = ["-i", f.path, "-vf", "crop=\(w):\(h):\(x):\(y)"] + VideoExport.codecArgs(for: f)
                if let i = args.firstIndex(of: "-c:a"), args.indices.contains(i + 1) { args[i + 1] = "copy"; if args.indices.contains(i + 3), args[i + 2] == "-b:a" { args.removeSubrange((i + 2)...(i + 3)) } }
                try await FFmpeg.run(args + [out.path], duration: info.duration, progress: progress)
                outs.append(out)
            }
            return outs
        }
    }
}

// MARK: Speed
struct SpeedVideoTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var speedIdx = 2.0
    private let speeds: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]
    private var speed: Double { speeds[Int(speedIdx.rounded())] }

    var body: some View {
        ToolShell(title: "Change Video Speed", close: close) {
            VStack(spacing: 10) {
                VideoPreview(player: player, height: 330)
                HStack { Text("Playback speed").sectionLabel(); Spacer(); Text(label(speed)).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                Slider(value: $speedIdx, in: 0...5, step: 1).controlSize(.small)
                HStack { ForEach(speeds, id: \.self) { Text(label($0)).font(.system(size: 10)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity) } }
                HStack {
                    Button { player.rate = Float(speed); player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain)
                    Spacer()
                    Text("\(timecode(player.time)) / \(timecode(player.duration))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
                }
            }.frame(width: 400)
        } footer: { Button("Apply") { apply() }.buttonStyle(PillButtonStyle()) }
        .task { await player.load(urls[0]) }
        .onChange(of: speedIdx) { _ in player.rate = Float(speed); if player.isPlaying { player.player.rate = Float(speed) } }
    }

    private func label(_ s: Double) -> String { s == s.rounded() ? "\(Int(s))×" : String(format: "%g×", s) }

    private func apply() {
        let s = speed, files = urls
        close()
        Dispatcher.job("Changing speed…") { progress in
            var outs: [URL] = []
            for f in files {
                let info = await FFmpeg.probe(f)
                let out = OutputNaming.sibling(of: f, suffix: " \(label(s).replacingOccurrences(of: "×", with: "x"))", ext: VideoExport.ext(for: f))
                var args = ["-i", f.path, "-filter:v", "setpts=PTS/\(s)"]
                if info.hasAudio { args += ["-filter:a", atempoChain(s)] } else { args += ["-an"] }
                args += VideoExport.codecArgs(for: f).filter { _ in true }
                if !info.hasAudio, let i = args.lastIndex(of: "-c:a") { args.removeSubrange(i...(i + 1)); if let j = args.lastIndex(of: "-b:a") { args.removeSubrange(j...(j + 1)) } }
                try await FFmpeg.run(args + [out.path], duration: info.duration / s, progress: progress)
                outs.append(out)
            }
            return outs
        }
    }

    private func atempoChain(_ s: Double) -> String {
        var rest = s, parts: [String] = []
        while rest > 2 { parts.append("atempo=2.0"); rest /= 2 }
        while rest < 0.5 { parts.append("atempo=0.5"); rest /= 0.5 }
        parts.append("atempo=\(rest)")
        return parts.joined(separator: ",")
    }
}

// MARK: Join
struct JoinVideosTool: View {
    @State var urls: [URL]
    let close: () -> Void
    @State private var thumbs: [URL: NSImage] = [:]

    var body: some View {
        ToolShell(title: "Join Videos", close: close) {
            OrderEditor(urls: $urls, thumbs: thumbs, accepts: FileKind.videoExts, noun: "video", types: [.movie])
        } footer: { Button("Join Videos") { apply() }.buttonStyle(PillButtonStyle()).disabled(urls.count < 2) }
        .task(id: urls) {
            for u in urls where thumbs[u] == nil {
                let g = AVAssetImageGenerator(asset: AVURLAsset(url: u)); g.appliesPreferredTrackTransform = true; g.maximumSize = CGSize(width: 120, height: 120)
                if let cg = try? await g.image(at: .zero).image { thumbs[u] = NSImage(cgImage: cg, size: .zero) }
            }
        }
    }

    private func apply() {
        let files = urls
        close()
        Dispatcher.job("Joining videos…") { progress in
            let infos = await withTaskGroup(of: (Int, MediaInfo).self) { g -> [MediaInfo] in
                for (i, f) in files.enumerated() { g.addTask { (i, await FFmpeg.probe(f)) } }
                var r = [MediaInfo?](repeating: nil, count: files.count)
                for await (i, m) in g { r[i] = m }
                return r.compactMap { $0 }
            }
            guard let first = infos.first else { throw MandarineError("Aucun clip.") }
            let w = VideoExport.even(Double(first.width)), h = VideoExport.even(Double(first.height))
            let allAudio = infos.allSatisfy(\.hasAudio)
            var args: [String] = []
            for f in files { args += ["-i", f.path] }
            var filter = ""
            for i in 0..<files.count {
                filter += "[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(i)];"
                if allAudio { filter += "[\(i):a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a\(i)];" }
            }
            filter += (0..<files.count).map { allAudio ? "[v\($0)][a\($0)]" : "[v\($0)]" }.joined()
            filter += "concat=n=\(files.count):v=1:a=\(allAudio ? 1 : 0)[v]" + (allAudio ? "[a]" : "")
            args += ["-filter_complex", filter, "-map", "[v]"] + (allAudio ? ["-map", "[a]"] : [])
            let out = OutputNaming.sibling(of: files[0], suffix: " joined", ext: "mp4")
            args += FFmpeg.videoArgs(for: "mp4")
            try await FFmpeg.run(args + [out.path], duration: infos.reduce(0) { $0 + $1.duration }, progress: progress)
            return [out]
        }
    }
}

// MARK: Snapshots
struct SnapshotsTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var frames: [(t: Double, img: NSImage)] = []
    @State private var pos = 0.0

    var body: some View {
        ToolShell(title: "Video Snapshots", close: close) {
            VStack(spacing: 10) {
                VideoPreview(player: player, height: 300)
                Scrubber(value: $pos, range: player.duration) { player.pause(); player.seek($0) }
                FrameStepRow(player: player, showPlay: false)
                Divider()
                HStack {
                    Text("\(frames.count) selected").sectionLabel()
                    Spacer()
                    Button("Add Frame") { add() }.buttonStyle(PillButtonStyle())
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(frames.enumerated()), id: \.offset) { i, f in
                            ZStack(alignment: .bottomLeading) {
                                Image(nsImage: f.img).resizable().scaledToFill().frame(width: 76, height: 54).clipped()
                                Text(timecode(f.t)).font(.system(size: 9, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                                    .padding(.horizontal, 3).background(Color.black.opacity(0.6)).padding(3)
                                Button { frames.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white).padding(4).background(Circle().fill(.black.opacity(0.6))) }
                                    .buttonStyle(.plain).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(3)
                            }.clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(height: 60)
            }.frame(width: 400)
        } footer: {
            Button(frames.count == 1 ? "Save 1 Frame" : "Save \(frames.count) Frames") { save() }.buttonStyle(PillButtonStyle()).disabled(frames.isEmpty)
        }
        .task { await player.load(urls[0]); add() }
        .onReceive(player.$time) { pos = $0 }
    }

    private func add() {
        let t = player.time
        guard !frames.contains(where: { abs($0.t - t) < 0.001 }) else { return }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: urls[0]))
        gen.appliesPreferredTrackTransform = true; gen.maximumSize = CGSize(width: 240, height: 240)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        Task {
            if let cg = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image {
                await MainActor.run { frames.append((t, NSImage(cgImage: cg, size: .zero))); frames.sort { $0.t < $1.t } }
            }
        }
    }

    private func save() {
        let times = frames.map(\.t), file = urls[0]
        close()
        Dispatcher.job("Saving frames…", light: true) { _ in
            let dir = times.count > 1 ? OutputNaming.folder(of: file, suffix: "frames") : file.deletingLastPathComponent()
            var outs: [URL] = []
            for t in times {
                let name = file.deletingPathExtension().lastPathComponent + " " + timecode(t).replacingOccurrences(of: ":", with: "-")
                let out = OutputNaming.unique(folder: dir, base: name, ext: "png")
                // AVFoundation d'abord (aucun ffmpeg requis, pleine résolution) ; ffmpeg pour les formats qu'il ne lit pas (MKV, WebM…)
                if let cg = await VideoFrames.native(file, at: t) {
                    try ImageEngine.write(cg, to: out, ext: "png")
                } else {
                    try await FFmpeg.run(["-ss", String(t), "-i", file.path, "-frames:v", "1", out.path])
                }
                if out.fileSize == 0 { try? FileManager.default.removeItem(at: out); throw MandarineError("Aucune image à \(timecode(t)) : cet instant est après la fin de la vidéo.") }
                outs.append(out)
            }
            return times.count > 1 ? [dir] : outs
        }
    }
}

// MARK: Split
struct SplitVideoTool: View {
    let urls: [URL]
    let close: () -> Void
    @StateObject private var player = PlayerController()
    @State private var points: [Double] = []
    @State private var equal = 2
    @State private var pos = 0.0

    var body: some View {
        ToolShell(title: "Split Video", close: close) {
            VStack(spacing: 10) {
                VideoPreview(player: player, height: 300)
                HStack {
                    Text("\(points.count) split point\(points.count == 1 ? "" : "s")").sectionLabel()
                    Spacer()
                    Button { let t = player.time; if t > 0.05, t < player.duration - 0.05, !points.contains(where: { abs($0 - t) < 0.05 }) { points.append(t); points.sort() } } label: {
                        Label("Add Split", systemImage: "scissors")
                    }.buttonStyle(PillButtonStyle())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        FilmStrip(url: urls[0], duration: player.duration).clipShape(RoundedRectangle(cornerRadius: 8))
                        ForEach(points, id: \.self) { p in
                            Rectangle().fill(Color.white).frame(width: 2).offset(x: geo.size.width * CGFloat(p / max(player.duration, 0.01)))
                                .onTapGesture { points.removeAll { $0 == p } }
                        }
                        Rectangle().fill(Theme.orange).frame(width: 2).offset(x: geo.size.width * CGFloat(player.time / max(player.duration, 0.01)))
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in player.pause(); player.seek(Double(v.location.x / geo.size.width) * player.duration) })
                }.frame(height: 48)
                FrameStepRow(player: player)
                Divider()
                HStack {
                    Text("Equal clips").sectionLabel(); Spacer()
                    Stepper("\(equal)", value: $equal, in: 2...50).frame(width: 90)
                    Button("Set") { points = (1..<equal).map { player.duration * Double($0) / Double(equal) } }.buttonStyle(PillButtonStyle())
                }
            }.frame(width: 400)
        } footer: {
            Button("Split Video") { apply() }.buttonStyle(PillButtonStyle()).disabled(points.isEmpty)
        }
        .task { await player.load(urls[0]) }
    }

    private func apply() {
        let pts = points, file = urls[0]
        close()
        Dispatcher.job("Splitting video…") { progress in
            let info = await FFmpeg.probe(file)
            let bounds = [0.0] + pts + [info.duration]
            let dir = OutputNaming.folder(of: file, suffix: "clips")
            for i in 0..<(bounds.count - 1) {
                let out = dir.appendingPathComponent("\(file.deletingPathExtension().lastPathComponent) \(i + 1)").appendingPathExtension(VideoExport.ext(for: file))
                try await FFmpeg.run(["-ss", String(bounds[i]), "-i", file.path, "-t", String(bounds[i + 1] - bounds[i])] + VideoExport.codecArgs(for: file) + [out.path])
                progress(Double(i + 1) / Double(bounds.count - 1))
            }
            return [dir]
        }
    }
}
