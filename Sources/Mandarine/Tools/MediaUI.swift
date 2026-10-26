import SwiftUI
import AVFoundation
import AVKit

func timecode(_ t: Double, centis: Bool = true) -> String {
    let t = max(0, t)
    let m = Int(t) / 60, s = Int(t) % 60, c = Int((t - floor(t)) * 100)
    return centis ? String(format: "%d:%02d.%02d", m, s, c) : String(format: "%d:%02d", m, s)
}

func parseTimecode(_ s: String) -> Double? {
    let parts = s.split(separator: ":").map(String.init)
    guard !parts.isEmpty, parts.count <= 3 else { return nil }
    var t = 0.0
    for p in parts { guard let v = Double(p) else { return nil }; t = t * 60 + v }
    return t
}

/// Lecteur (vidéo ou audio) avec position, lecture, saut image par image et boucle sur une plage.
final class PlayerController: ObservableObject {
    let player = AVPlayer()
    @Published var duration: Double = 0
    @Published var time: Double = 0
    @Published var isPlaying = false
    @Published var fps: Double = 30
    @Published var size: CGSize = .zero
    var loopRange: ClosedRange<Double>?
    var rate: Float = 1
    private var observer: Any?
    private(set) var url: URL?

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            guard let self = self else { return }
            self.time = t.seconds
            if let r = self.loopRange, self.isPlaying, t.seconds >= r.upperBound { self.pause(); self.seek(r.upperBound) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(ended), name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    deinit { if let o = observer { player.removeTimeObserver(o) } }

    @objc private func ended() { isPlaying = false }

    /// `exact` : transcode en WAV pour que la position de lecture suive la même échelle de temps que ffmpeg (durées AVFoundation parfois fausses sur MP3/VBR).
    func load(_ url: URL, exact: Bool = false) async {
        self.url = url
        var playable = url
        let asset = AVURLAsset(url: url)
        if exact, FFmpeg.isAvailable, !["wav", "aiff", "aif", "flac"].contains(url.pathExtension.lowercased()) {
            let tmp = OutputNaming.tempURL(ext: "wav")
            if (try? await FFmpeg.run(["-i", url.path, "-vn", "-c:a", "pcm_s16le", tmp.path])) != nil { playable = tmp }
        } else if !((try? await asset.load(.isPlayable)) ?? false), FFmpeg.isAvailable {
            let tmp = OutputNaming.tempURL(ext: FileKind.detect(url) == .audio ? "m4a" : "mp4")
            _ = try? await FFmpeg.run(["-i", url.path] + (FileKind.detect(url) == .audio ? ["-vn", "-c:a", "aac"] : ["-c:v", "libx264", "-c:a", "aac"]) + [tmp.path])
            playable = tmp
        }
        let a = AVURLAsset(url: playable)
        let d = (try? await a.load(.duration).seconds) ?? 0
        var f = 30.0, s = CGSize.zero
        if let v = try? await a.loadTracks(withMediaType: .video).first {
            f = Double((try? await v.load(.nominalFrameRate)) ?? 30); if f < 1 { f = 30 }
            let n = (try? await v.load(.naturalSize)) ?? .zero
            let t = (try? await v.load(.preferredTransform)) ?? .identity
            let r = n.applying(t); s = CGSize(width: abs(r.width), height: abs(r.height))
        }
        await MainActor.run {
            duration = d; fps = f; size = s
            player.replaceCurrentItem(with: AVPlayerItem(asset: a))
        }
    }

    func play() {
        if let r = loopRange, time < r.lowerBound || time >= r.upperBound - 0.02 { seek(r.lowerBound) }
        else if duration > 0, time >= duration - 0.02 { seek(0) }
        player.rate = rate; player.play(); isPlaying = true
    }
    func pause() { player.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }
    func seek(_ t: Double) {
        let c = min(max(0, t), duration)
        time = c
        player.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func step(_ frames: Int) { pause(); seek(time + Double(frames) / fps) }
}

struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class PlayerLayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer = playerLayer }
        required init?(coder: NSCoder) { fatalError() }
    }
}

/// Frise de vignettes d'une vidéo.
struct FilmStrip: View {
    let url: URL
    let duration: Double
    var count = 10
    @State private var thumbs: [NSImage] = []
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(0..<thumbs.count, id: \.self) { i in
                    Image(nsImage: thumbs[i]).resizable().scaledToFill()
                        .frame(width: geo.size.width / CGFloat(max(thumbs.count, 1)), height: geo.size.height).clipped()
                }
            }
        }
        .background(Color.black.opacity(0.85))
        .task(id: duration) {
            guard duration > 0 else { return }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 200, height: 200)
            var out: [NSImage] = []
            for i in 0..<count {
                let t = duration * (Double(i) + 0.5) / Double(count)
                if let cg = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image { out.append(NSImage(cgImage: cg, size: .zero)) }
            }
            thumbs = out
        }
    }
}

/// Pics d'amplitude (0…1) d'un fichier audio, via ffmpeg (tous formats).
enum WaveformLoader {
    static func peaks(_ url: URL, count: Int = 160) async -> (peaks: [Float], left: [Float], right: [Float], duration: Double) {
        guard let ff = FFmpeg.ffmpeg else { return ([], [], [], 0) }
        func run(_ extra: [String]) -> ([Float], Int) {
            let p = Process(); p.executableURL = ff
            p.arguments = ["-v", "error", "-i", url.path, "-vn"] + extra + ["-ar", "8000", "-f", "f32le", "-"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return ([], 0) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let n = data.count / 4
            guard n > 0 else { return ([], 0) }
            let samples: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return ((0..<count).map { i in
                let s = i * n / count, e = max(s + 1, min(n, (i + 1) * n / count))
                guard s < e, s < n else { return 0 }
                var m: Float = 0
                for k in s..<e { m = max(m, abs(samples[k])) }
                return min(1, m)
            }, n)
        }
        return await Task.detached {
            let a = run(["-ac", "1"])
            return (a.0, run(["-af", "pan=mono|c0=c0"]).0, run(["-af", "pan=mono|c0=c1"]).0, Double(a.1) / 8000)
        }.value
    }
}

struct WaveformView: View {
    let peaks: [Float]
    var color: Color = Theme.orange
    var barWidth: CGFloat = 2
    var body: some View {
        Canvas { ctx, size in
            guard !peaks.isEmpty else { return }
            let step = size.width / CGFloat(peaks.count)
            for (i, p) in peaks.enumerated() {
                let h = max(1.5, CGFloat(p) * size.height * 0.9)
                let r = CGRect(x: CGFloat(i) * step + (step - barWidth) / 2, y: (size.height - h) / 2, width: barWidth, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 0.5), with: .color(p < 0.02 ? color.opacity(0.7) : color))
            }
        }
    }
}

/// Plage Start/End avec barres orange sur un fond arbitraire.
/// Les barres sont **à l'extérieur** de la zone gardée : la coupe se fait au bord intérieur de chaque barre, et le contenu
/// (onde, vignettes) occupe exactement l'espace entre les deux extrémités, sans décalage.
/// Un seul geste couvre toute la zone (repère fixe) : on attrape une barre, ou l'intérieur pour déplacer la plage entière.
struct TimeRangeSelector<Content: View>: View {
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    var playhead: Double? = nil
    var onScrub: ((Double) -> Void)? = nil
    @ViewBuilder var content: () -> Content

    private enum Mode { case start, end, move }
    @State private var mode: Mode?
    @State private var initial = (start: 0.0, end: 0.0)
    @State private var grabOffset: CGFloat = 0
    @State private var lastStart = CGPoint(x: -1, y: -1)       // détecte un nouveau glissement même si « onEnded » n'a pas été appelé
    @State private var lastEvent = Date.distantPast
    private let space = "timeRangeSelector"
    private let minLen = 0.05
    private let hw: CGFloat = 14           // largeur d'une barre

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1), track = max(w - 2 * hw, 1)
            let x0 = hw + track * CGFloat(start / max(duration, 0.001)), x1 = hw + track * CGFloat(end / max(duration, 0.001))
            ZStack(alignment: .leading) {
                content().padding(.horizontal, hw).allowsHitTesting(false)
                // zones hors sélection
                Color.black.opacity(0.35).frame(width: max(0, x0 - hw - hw)).offset(x: hw).allowsHitTesting(false)
                Color.black.opacity(0.35).frame(width: max(0, w - hw - (x1 + hw))).offset(x: x1 + hw).allowsHitTesting(false)
                // cadre englobant les deux barres
                RoundedRectangle(cornerRadius: 8).stroke(Theme.orange, lineWidth: 3)
                    .frame(width: max(2, x1 - x0 + 2 * hw)).offset(x: x0 - hw).allowsHitTesting(false)
                bar(left: true).frame(width: hw).offset(x: x0 - hw).allowsHitTesting(false)
                bar(left: false).frame(width: hw).offset(x: x1).allowsHitTesting(false)
                if let p = playhead, duration > 0 {
                    Rectangle().fill(Color.white).frame(width: 2).shadow(radius: 1)
                        .offset(x: hw + track * CGFloat(p / duration) - 1).allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .coordinateSpace(name: space)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                .onChanged { v in drag(v, track: track, x0: x0, x1: x1) }
                .onEnded { _ in mode = nil })
        }
    }

    private func drag(_ v: DragGesture.Value, track: CGFloat, x0: CGFloat, x1: CGFloat) {
        let t = { (x: CGFloat) in min(max(0, Double((x - hw) / track) * duration), duration) }
        // Nouveau glissement (autre point de départ, ou longue pause depuis le dernier évènement) : on repart de zéro.
        if v.startLocation != lastStart || Date().timeIntervalSince(lastEvent) > 0.4 { mode = nil }
        lastStart = v.startLocation; lastEvent = Date()
        if mode == nil {
            let sx = v.startLocation.x, grab: CGFloat = hw + 10
            let dStart = abs(sx - (x0 - hw / 2)), dEnd = abs(sx - (x1 + hw / 2))
            if sx >= x0 - grab && sx <= x0 + 2 && dStart <= dEnd { mode = .start }
            else if sx >= x1 - 2 && sx <= x1 + grab { mode = .end }
            else if sx > x0 && sx < x1 { mode = .move }
            else { mode = dStart < dEnd ? .start : .end }
            // on garde l'écart entre le clic et le bord intérieur de la barre : la barre ne « saute » pas sous la souris
            grabOffset = mode == .start ? sx - x0 : (mode == .end ? sx - x1 : 0)
            initial = (start, end)
        }
        switch mode {
        case .start:
            start = min(t(v.location.x - grabOffset), end - minLen); onScrub?(start)
        case .end:
            end = max(t(v.location.x - grabOffset), start + minLen); onScrub?(end)
        case .move:
            let len = initial.end - initial.start
            let dt = Double(v.translation.width / track) * duration
            let s = min(max(0, initial.start + dt), duration - len)
            start = s; end = s + len; onScrub?(start)
        case nil: break
        }
    }

    private func bar(left: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: left ? 8 : 0, bottomLeadingRadius: left ? 8 : 0,
                                   bottomTrailingRadius: left ? 0 : 8, topTrailingRadius: left ? 0 : 8).fill(Theme.orange)
            Capsule().fill(Color.white).frame(width: 3, height: 22)
        }
    }
}

/// Scrubber simple (barre + pastille) pour naviguer dans une vidéo.
struct Scrubber: View {
    @Binding var value: Double
    let range: Double
    var onChange: (Double) -> Void
    var body: some View {
        Slider(value: Binding(get: { value }, set: { value = $0; onChange($0) }), in: 0...max(range, 0.01)).controlSize(.small)
    }
}

struct FrameStepRow: View {
    @ObservedObject var player: PlayerController
    var showPlay = true
    var body: some View {
        HStack(spacing: 14) {
            Button { player.step(-1) } label: { Image(systemName: "backward.frame") }.buttonStyle(.plain)
            if showPlay { Button { player.toggle() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.plain) }
            Button { player.step(1) } label: { Image(systemName: "forward.frame") }.buttonStyle(.plain)
            Spacer()
            Text("\(timecode(player.time)) / \(timecode(player.duration))").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted)
        }.foregroundStyle(Theme.text.opacity(0.8))
    }
}
