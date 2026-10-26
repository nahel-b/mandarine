import Foundation
import AppKit

struct CompressOptions {
    var strong = false
    var maxSide: Int? = nil          // redimensionnement des images (côté max, en px)
    var scale: Double? = nil         // ou pourcentage
    var targetBytes: Int64? = nil    // taille cible
}

enum Compressor {
    static func run(_ url: URL, options o: CompressOptions, progress: @escaping (Double) -> Void) async throws -> URL {
        switch FileKind.detect(url) {
        case .image: return try await Task.detached { try image(url, o) }.value
        case .video: return try await video(url, o, progress)
        case .audio: return try await audio(url, o, progress)
        case .pdf: return try await Task.detached { try PDFEngine.compress(url, strong: o.strong) }.value
        default: return try await Task.detached { try ArchiveEngine.compress(url) }.value
        }
    }

    // MARK: Images
    private static func image(_ url: URL, _ o: CompressOptions) throws -> URL {
        let ext = Catalog.normalized(url.pathExtension)
        let (src, props) = try ImageEngine.load(url)
        var img = src
        if let s = o.scale, s < 1 { img = ImageEngine.resize(img, width: Int(Double(img.width) * s), height: Int(Double(img.height) * s)) }
        if let m = o.maxSide { img = ImageEngine.resize(img, maxSide: m) }
        let out = OutputNaming.sibling(of: url, suffix: " compressed", ext: ext == "jpeg" ? "jpg" : url.pathExtension)

        if ext == "png" {
            try ImageEngine.write(img, properties: props, to: out, ext: "png")
            if o.strong || o.targetBytes != nil, FFmpeg.isAvailable { try quantizePNG(out) }
            return out
        }
        let lossy = ["jpg", "heic", "avif", "webp"].contains(ext)
        guard lossy else {
            try ImageEngine.write(img, properties: props, to: out, ext: ext == "tiff" ? "tiff" : ext)
            return out
        }
        if let target = o.targetBytes {
            var lo = 0.05, hi = 0.98, best: Double = 0.05
            for _ in 0..<9 {
                let mid = (lo + hi) / 2
                let size = ImageEngine.data(img, ext: ext == "webp" ? "jpg" : ext, quality: mid)?.count ?? Int.max
                if Int64(size) <= target { best = mid; lo = mid } else { hi = mid }
            }
            try ImageEngine.write(img, properties: props, to: out, ext: ext, quality: best)
        } else {
            try ImageEngine.write(img, properties: props, to: out, ext: ext, quality: o.strong ? 0.45 : 0.72)
        }
        return out
    }

    private static func quantizePNG(_ file: URL) throws {
        let tmp = OutputNaming.tempURL(ext: "png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let sem = DispatchSemaphore(value: 0)
        var failure: Error?
        Task.detached {
            do {
                try await FFmpeg.run(["-i", file.path, "-vf", "split[a][b];[a]palettegen=max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a", tmp.path])
            } catch { failure = error }
            sem.signal()
        }
        sem.wait()
        if failure != nil { return }
        let old = file.fileSize, new = tmp.fileSize
        if new > 0, new < old { try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: tmp, to: file) }
    }

    // MARK: Vidéo
    private static func video(_ url: URL, _ o: CompressOptions, _ progress: @escaping (Double) -> Void) async throws -> URL {
        let info = await FFmpeg.probe(url)
        let ext = ["mp4", "mov", "m4v", "mkv"].contains(url.pathExtension.lowercased()) ? url.pathExtension : "mp4"
        let out = OutputNaming.sibling(of: url, suffix: " compressed", ext: ext)
        var args = ["-i", url.path]
        var vf = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        if let s = o.scale, s < 1 { vf = "scale=trunc(iw*\(s)/2)*2:trunc(ih*\(s)/2)*2" }
        if let m = o.maxSide { vf = "scale='if(gt(iw,ih),min(\(m),iw),-2)':'if(gt(iw,ih),-2,min(\(m),ih))'" }
        args += ["-vf", vf]
        if let target = o.targetBytes, info.duration > 0 {
            let audioBps = info.hasAudio ? 128_000.0 : 0
            let total = Double(target) * 8 / info.duration
            let vb = max(100_000, (total - audioBps) * 0.95)
            let enc = FFmpeg.hasEncoder("libx264") ? ["-c:v", "libx264", "-b:v", String(Int(vb)), "-maxrate", String(Int(vb * 1.5)), "-bufsize", String(Int(vb * 2))]
                                                   : ["-c:v", "h264_videotoolbox", "-b:v", String(Int(vb))]
            args += enc + ["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k"]
        } else if FFmpeg.hasEncoder("libx265") {
            args += ["-c:v", "libx265", "-crf", o.strong ? "32" : "27", "-preset", "medium", "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", o.strong ? "96k" : "128k"]
        } else {
            args += ["-c:v", "libx264", "-crf", o.strong ? "30" : "25", "-preset", "medium", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", o.strong ? "96k" : "128k"]
        }
        if ext != "mkv" { args += ["-movflags", "+faststart"] }
        try await FFmpeg.run(args + [out.path], duration: info.duration, progress: progress)
        return out
    }

    // MARK: Audio
    private static func audio(_ url: URL, _ o: CompressOptions, _ progress: @escaping (Double) -> Void) async throws -> URL {
        let info = await FFmpeg.probe(url)
        let ext = Catalog.normalized(url.pathExtension)
        let out = OutputNaming.sibling(of: url, suffix: " compressed", ext: url.pathExtension)
        var kbps = o.strong ? 64 : 128
        if let t = o.targetBytes, info.duration > 0 { kbps = max(16, Int(Double(t) * 8 / info.duration / 1000 * 0.95)) }
        var args = ["-i", url.path, "-vn"]
        switch ext {
        case "mp3": args += ["-c:a", "libmp3lame", "-b:a", "\(kbps)k"]
        case "m4a": args += ["-c:a", "aac", "-b:a", "\(kbps)k"]
        case "ogg": args += FFmpeg.hasEncoder("libvorbis") ? ["-c:a", "libvorbis", "-b:a", "\(kbps)k"] : ["-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-b:a", "\(kbps)k"]
        case "opus": args += ["-c:a", "libopus", "-b:a", "\(kbps)k"]
        case "wma": args += ["-c:a", "wmav2", "-b:a", "\(kbps)k"]
        case "flac": args += ["-c:a", "flac", "-compression_level", "12"] + (o.strong ? ["-ar", "32000"] : [])
        case "wav", "aiff": args += (o.strong ? ["-ar", "22050", "-ac", "1"] : ["-ar", "44100"]) + FFmpeg.audioArgs(for: ext)
        default: args += ["-b:a", "\(kbps)k"]
        }
        try await FFmpeg.run(args + [out.path], duration: info.duration, progress: progress)
        return out
    }
}
