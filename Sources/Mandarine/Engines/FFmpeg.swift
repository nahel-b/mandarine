import Foundation
import AVFoundation

struct MediaInfo {
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 30
    var hasVideo = false
    var hasAudio = false
    var audioChannels = 2
    var tags: [String: String] = [:]
    // détails du flux vidéo (export type HandBrake)
    var codec = ""
    var profile = ""
    var pixFmt = ""
    var colorSpace = ""
    var colorPrimaries = ""
    var colorTransfer = ""
    var colorRange = ""
    var bitRate: Double = 0
    var fileSize: Int64 = 0
    var audioCodec = ""
}

/// Enveloppe autour des binaires `ffmpeg` / `ffprobe` (embarqués dans Resources/bin, sinon Homebrew).
enum FFmpeg {
    /// Dossier où déposer ffmpeg / ffprobe / cwebp à la main : ~/Library/Application Support/Mandarine/bin
    static var enginesFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mandarine/bin", isDirectory: true)
    }

    static func locate(_ name: String) -> URL? {
        var candidates: [String] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("bin/\(name)").path) }
        candidates.append(enginesFolder.appendingPathComponent(name).path)          // installation manuelle, sans Homebrew
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    static var ffmpeg: URL? { locate("ffmpeg") }
    static var ffprobe: URL? { locate("ffprobe") }
    static var isAvailable: Bool { ffmpeg != nil }

    private static var encoderCache: String?
    static func hasEncoder(_ name: String) -> Bool {
        guard let ff = ffmpeg else { return false }
        if encoderCache == nil {
            let p = Process(); p.executableURL = ff; p.arguments = ["-hide_banner", "-encoders"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            try? p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            encoderCache = String(data: data, encoding: .utf8) ?? ""
        }
        return encoderCache?.contains(" \(name) ") ?? false
    }

    static func probe(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        // Résultat rapide via AVFoundation, complété par ffprobe si disponible.
        if let ffprobe = ffprobe {
            let p = Process(); p.executableURL = ffprobe
            p.arguments = ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let fmt = json["format"] as? [String: Any] {
                        info.duration = Double(fmt["duration"] as? String ?? "") ?? 0
                        info.fileSize = Int64(fmt["size"] as? String ?? "") ?? 0
                        if info.bitRate == 0 { info.bitRate = Double(fmt["bit_rate"] as? String ?? "") ?? 0 }
                        info.tags = (fmt["tags"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:]
                    }
                    for s in (json["streams"] as? [[String: Any]]) ?? [] {
                        switch s["codec_type"] as? String {
                        case "video":
                            if (s["disposition"] as? [String: Any])?["attached_pic"] as? Int == 1 { continue }
                            info.hasVideo = true
                            info.codec = s["codec_name"] as? String ?? ""
                            info.profile = s["profile"] as? String ?? ""
                            info.pixFmt = s["pix_fmt"] as? String ?? ""
                            info.colorSpace = s["color_space"] as? String ?? ""
                            info.colorPrimaries = s["color_primaries"] as? String ?? ""
                            info.colorTransfer = s["color_transfer"] as? String ?? ""
                            info.colorRange = s["color_range"] as? String ?? ""
                            if let br = Double(s["bit_rate"] as? String ?? ""), br > 0 { info.bitRate = br }
                            info.width = s["width"] as? Int ?? 0
                            info.height = s["height"] as? Int ?? 0
                            if let r = s["avg_frame_rate"] as? String, let v = parseRate(r), v > 0 { info.fps = v }
                            if info.duration == 0 { info.duration = Double(s["duration"] as? String ?? "") ?? 0 }
                            // rotation éventuelle
                            if let sd = s["side_data_list"] as? [[String: Any]],
                               let rot = sd.compactMap({ $0["rotation"] as? Double }).first, abs(Int(rot)) % 180 == 90 {
                                swap(&info.width, &info.height)
                            }
                        case "audio":
                            info.hasAudio = true
                            info.audioCodec = s["codec_name"] as? String ?? ""
                            info.audioChannels = s["channels"] as? Int ?? 2
                            if info.duration == 0 { info.duration = Double(s["duration"] as? String ?? "") ?? 0 }
                        default: break
                        }
                    }
                    return info
                }
            } catch {}
        }
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) { info.duration = d.seconds }
        if let v = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await v.load(.naturalSize) {
            info.hasVideo = true; info.width = Int(size.width); info.height = Int(size.height)
        }
        info.hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        return info
    }

    private static func parseRate(_ s: String) -> Double? {
        let parts = s.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return Double(s)
    }

    /// Lance ffmpeg. `duration` (en secondes) sert à calculer la progression.
    @discardableResult
    static func run(_ args: [String], duration: Double? = nil, progress: ((Double) -> Void)? = nil) async throws -> String {
        guard let ff = ffmpeg else {
            throw MandarineError("ffmpeg est introuvable. Installez-le (brew install ffmpeg) ou placez-le dans Resources/bin.")
        }
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = ff
                p.arguments = ["-nostdin", "-y", "-hide_banner", "-loglevel", "error", "-progress", "pipe:1", "-nostats"] + args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                var errData = Data()
                err.fileHandleForReading.readabilityHandler = { h in errData.append(h.availableData) }
                out.fileHandleForReading.readabilityHandler = { h in
                    let d = h.availableData
                    guard let s = String(data: d, encoding: .utf8), let dur = duration, dur > 0 else { return }
                    for line in s.split(separator: "\n") where line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                        if let v = Double(line.split(separator: "=")[1]) {
                            progress?(min(1, max(0, v / 1_000_000 / dur)))
                        }
                    }
                }
                guard box.attach(p) else { cont.resume(throwing: CancellationError()); return }
                do { try p.run() } catch { cont.resume(throwing: error); return }
                p.waitUntilExit()
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if box.cancelled {      // annulé par l'utilisateur : on retire le fichier à moitié écrit
                    if let last = args.last, last.hasPrefix("/") { try? FileManager.default.removeItem(atPath: last) }
                    cont.resume(throwing: CancellationError()); return
                }
                let msg = String(data: errData, encoding: .utf8) ?? ""
                if p.terminationStatus == 0 { cont.resume(returning: msg) }
                else {
                    let cmd = "ffmpeg " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
                    let body = msg.isEmpty ? "ffmpeg a échoué (code \(p.terminationStatus))." : String(msg.suffix(900))
                    cont.resume(throwing: MandarineError(body + "\n› " + String(cmd.suffix(500))))
                }
            }
          }
        } onCancel: { box.cancel() }
    }

    // MARK: Codecs par format de sortie
    static func videoArgs(for ext: String) -> [String] {
        let h264 = hasEncoder("libx264") ? ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"]
                                          : ["-c:v", "h264_videotoolbox", "-b:v", "8M", "-pix_fmt", "yuv420p"]
        switch ext {
        case "mp4", "mov", "m4v": return h264 + ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case "mkv": return h264 + ["-c:a", "aac", "-b:a", "192k"]
        case "webm": return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k"]
        case "avi": return ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-q:a", "3"]
        case "wmv": return ["-c:v", "wmv2", "-b:v", "6M", "-c:a", "wmav2", "-b:a", "192k"]
        default: return []
        }
    }

    static func audioArgs(for ext: String) -> [String] {
        switch ext {
        case "mp3": return ["-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a", "aac": return ["-c:a", "aac", "-b:a", "256k"]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "aiff", "aif": return ["-c:a", "pcm_s16be"]
        case "flac": return ["-c:a", "flac"]
        case "ogg", "oga": return hasEncoder("libvorbis") ? ["-c:a", "libvorbis", "-q:a", "6"] : ["-c:a", "vorbis", "-strict", "-2", "-ac", "2", "-b:a", "192k"]
        case "opus": return ["-c:a", "libopus", "-b:a", "160k"]
        case "wma": return ["-c:a", "wmav2", "-b:a", "192k"]
        default: return []
        }
    }
}

/// Permet d'arrêter un processus lancé dans une file d'arrière-plan quand la tâche Swift qui l'attend est annulée.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var _cancelled = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    /// Faux si l'annulation a déjà eu lieu (le processus ne doit alors pas démarrer).
    func attach(_ p: Process) -> Bool { lock.lock(); defer { lock.unlock() }; if _cancelled { return false }; process = p; return true }
    func cancel() { lock.lock(); _cancelled = true; let p = process; lock.unlock(); if p?.isRunning == true { p?.terminate() } }
}
