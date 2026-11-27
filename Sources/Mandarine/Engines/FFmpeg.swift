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

    /// ffmpeg note « tb » ou « bt » dans un .mov ProRes entrelacé (une demi-image stockée d'abord, l'autre affichée d'abord), ce que des logiciels de montage lisent
    /// à l'envers. On recopie le fichier (sans réencoder) avec l'ordre correct : « tt » ou « bb ».
    static func fixFieldOrder(_ file: URL) async throws {
        guard file.pathExtension.lowercased() == "mov", let probe = ffprobe else { return }
        let p = Process(); p.executableURL = probe
        p.arguments = ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=field_order", "-of", "csv=p=0", file.path]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let order = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard order == "tb" || order == "bt" else { return }
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mov")
        do {
            try await run(["-i", file.path, "-map", "0", "-c", "copy", "-field_order", order == "tb" ? "tt" : "bb", "-map_metadata", "0", tmp.path], duration: 0) { _ in }
            _ = try FileManager.default.replaceItemAt(file, withItemAt: tmp)
        } catch { try? FileManager.default.removeItem(at: tmp); throw error }
    }

    /// Un caméscope DVD remet son horloge à zéro à chaque prise de vue. ffmpeg ne recale par défaut que les sauts de plus de 10 s : après une prise plus courte,
    /// l'image se fige et le son se décale. On abaisse ce seuil à 1 s, et le son suit les horodatages ainsi recalés.
    static func repairDVDTimestamps(_ args: [String]) -> [String] {
        let dvd = args.indices.dropLast().contains { args[$0] == "-i" && FileKind.dvdExts.contains((args[$0 + 1] as NSString).pathExtension.lowercased()) }
        guard dvd else { return args }
        var a = ["-dts_delta_threshold", "1"] + args
        // un son recopié ou passé par un graphe de filtres ne peut pas recevoir de filtre en plus
        let copiesAudio = a.indices.dropLast().contains { ["-c", "-c:a", "-codec:a", "-acodec"].contains(a[$0]) && a[$0 + 1] == "copy" }
        guard !copiesAudio, !a.contains("-an"), !a.contains("-filter_complex"), !a.contains("-lavfi") else { return a }
        if let i = a.firstIndex(where: { $0 == "-af" || $0 == "-filter:a" }), i + 1 < a.count { a[i + 1] = "aresample=async=1," + a[i + 1] }
        else { a.insert(contentsOf: ["-af", "aresample=async=1"], at: a.count - 1) }
        return a
    }

    /// La durée annoncée d'un VOB est fausse (12 s pour 15 min) à cause de ces remises à zéro. On compte les images de trois extraits et on rapporte à la taille.
    private static func estimatedDVDDuration(_ url: URL) -> Double? {
        guard let probe = ffprobe, let file = try? FileHandle(forReadingFrom: url), let size = try? file.seekToEnd(), size > 0 else { return nil }
        defer { try? file.close() }
        let chunk: UInt64 = 8 << 20
        let offsets: [UInt64] = size <= chunk * 3 ? [0] : [0, (size - chunk) / 2, size - chunk].map { $0 / 2048 * 2048 }          // secteurs de 2 048 octets
        var frames = 0.0, bytes = 0.0, fps = 0.0
        for offset in offsets {
            let sample = OutputNaming.tempURL(ext: "vob")
            defer { try? FileManager.default.removeItem(at: sample) }
            guard (try? file.seek(toOffset: offset)) != nil, let data = try? file.read(upToCount: Int(offsets.count == 1 ? size : chunk)), (try? data.write(to: sample)) != nil else { return nil }
            let p = Process(); p.executableURL = probe
            p.arguments = ["-v", "quiet", "-select_streams", "v:0", "-count_packets", "-show_entries", "stream=r_frame_rate,nb_read_packets", "-of", "default=nw=1", sample.path]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return nil }
            let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
            for line in text.split(separator: "\n") {
                let kv = line.split(separator: "=").map(String.init)
                guard kv.count == 2 else { continue }
                if kv[0] == "nb_read_packets", let n = Double(kv[1]) { frames += n; bytes += Double(data.count) }
                if kv[0] == "r_frame_rate", let r = parseRate(kv[1]), r > 0 { fps = r }
            }
        }
        guard frames > 0, bytes > 0, fps > 0 else { return nil }
        return frames / fps * Double(size) / bytes
    }

    static func probe(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        // Résultat rapide via AVFoundation, complété par ffprobe si disponible.
        if let ffprobe = ffprobe {
            let p = Process(); p.executableURL = ffprobe
            p.arguments = ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", HLS.resolveInputs([url.path])[0]]
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
                    if info.hasVideo, FileKind.dvdExts.contains(url.pathExtension.lowercased()), let d = estimatedDVDDuration(url) { info.duration = d }
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
    static func run(_ originalArgs: [String], duration: Double? = nil, progress: ((Double) -> Void)? = nil) async throws -> String {
        let args = repairDVDTimestamps(HLS.resolveInputs(originalArgs))
        guard let ff = ffmpeg else {
            throw MandarineError(L("ffmpeg est introuvable. Téléchargez-le dans Réglages → Engines (ou brew install ffmpeg)."))
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
                    let body = HLS.explainFailure(args: originalArgs, message: msg) ?? (msg.isEmpty ? "ffmpeg a échoué (code \(p.terminationStatus))." : String(msg.suffix(900)))
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
