import Foundation

/// Téléchargement de vidéos YouTube en MP3 / MP4 avec yt-dlp (outil externe, à installer comme ffmpeg).
enum YtDlp {
    static var url: URL? {
        let candidates = [FFmpeg.enginesFolder.appendingPathComponent("yt-dlp").path, "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func isYouTube(_ u: URL) -> Bool {
        guard u.scheme == "http" || u.scheme == "https", let h = u.host?.lowercased() else { return false }
        return h == "youtu.be" || h.hasSuffix("youtube.com") || h.hasSuffix("youtube-nocookie.com")
    }

    /// Tout lien web peut être tenté : yt-dlp sait lire plus d'un millier de sites.
    static func isWebLink(_ u: URL) -> Bool { (u.scheme == "http" || u.scheme == "https") && (u.host ?? "").contains(".") }

    /// Sites que l'on sait gérer : leurs liens portent un libellé affirmatif. Les autres sont « tentés ».
    private static let knownHosts = ["youtube.com", "youtu.be", "youtube-nocookie.com", "vimeo.com", "twitter.com", "x.com", "tiktok.com", "reddit.com",
                                     "facebook.com", "fb.watch", "instagram.com", "dailymotion.com", "twitch.tv", "soundcloud.com", "bandcamp.com",
                                     "arte.tv", "france.tv", "mixcloud.com", "bilibili.com", "ted.com", "streamable.com", "imgur.com"]
    static func isKnownSite(_ u: URL) -> Bool {
        guard isWebLink(u), let h = u.host?.lowercased() else { return false }
        return knownHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    /// Le lien désigne-t-il peut-être une liste (playlist, album, chaîne) ? Sinon, inutile de la sonder.
    static func mayBePlaylist(_ u: URL) -> Bool {
        guard isWebLink(u) else { return false }
        if isYouTube(u) {
            let p = u.path.lowercased()
            let hasList = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "list" } == true
            return hasList || p.hasPrefix("/playlist") || p.hasPrefix("/@") || p.hasPrefix("/channel") || p.hasPrefix("/c/") || p.hasPrefix("/user/")
        }
        return true      // autres sites : on sonde (une seule requête rapide)
    }

    /// Le lien pointe-t-il aussi vers une vidéo précise (watch?v=… avec list=…) ?
    static func hasSingleVideo(_ u: URL) -> Bool {
        guard isYouTube(u) else { return false }
        if u.host?.lowercased() == "youtu.be" { return u.path.count > 1 }
        return u.path.lowercased().hasPrefix("/watch") && URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "v" } == true
    }

    struct Playlist {
        struct Entry: Identifiable { let id: Int; let url: URL; let title: String; let duration: Double? }
        let title: String
        let entries: [Entry]
    }

    /// Lit la liste (sans rien télécharger). nil si le lien n'est pas une liste de plusieurs éléments, ou en cas d'échec.
    static func playlist(_ link: URL) async -> Playlist? {
        guard let data = try? await capture(["--flat-playlist", "-J", "--no-warnings", "--playlist-end", "500", link.absoluteString]),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              j["_type"] as? String == "playlist", let raw = j["entries"] as? [[String: Any]] else { return nil }
        var entries: [Playlist.Entry] = []
        for e in raw {
            let title = (e["title"] as? String) ?? (e["id"] as? String) ?? "Untitled"
            if title.hasPrefix("[Private") || title.hasPrefix("[Deleted") { continue }
            var u: URL?
            if let s = e["url"] as? String, s.hasPrefix("http") { u = URL(string: s) }
            else if let s = e["webpage_url"] as? String { u = URL(string: s) }
            else if let id = e["id"] as? String, (e["ie_key"] as? String)?.lowercased().hasPrefix("youtube") == true { u = URL(string: "https://www.youtube.com/watch?v=\(id)") }
            guard let url = u else { continue }
            // Certains sites (SoundCloud…) ne donnent pas de titre dans la liste : on le lit dans l'adresse
            let shown = (title == (e["id"] as? String) || Int(title) != nil) ? url.lastPathComponent.replacingOccurrences(of: "-", with: " ").removingPercentEncoding ?? title : title
            entries.append(.init(id: entries.count, url: url, title: shown, duration: e["duration"] as? Double))
        }
        guard entries.count >= 2 else { return nil }
        return Playlist(title: (j["title"] as? String) ?? "Playlist", entries: entries)
    }

    /// Lance yt-dlp et retourne sa sortie standard (annulable, 90 s maximum).
    static func capture(_ args: [String], timeout: TimeInterval = 90) async throws -> Data {
        guard let exe = url else { throw MandarineError(installHelp) }
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = exe; p.arguments = args
                    let out = Pipe(), err = Pipe()
                    p.standardOutput = out; p.standardError = err
                    err.fileHandleForReading.readabilityHandler = { _ = $0.availableData }
                    guard box.attach(p) else { cont.resume(throwing: CancellationError()); return }
                    do { try p.run() } catch { cont.resume(throwing: error); return }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    err.fileHandleForReading.readabilityHandler = nil
                    if box.cancelled { cont.resume(throwing: CancellationError()); return }
                    if p.terminationStatus == 0 { cont.resume(returning: data) }
                    else { cont.resume(throwing: MandarineError("yt-dlp a échoué (code \(p.terminationStatus)).")) }
                }
            }
        } onCancel: { box.cancel() }
    }

    static let installHelp = """
    yt-dlp est introuvable. Installez-le :
    • avec Homebrew : brew install yt-dlp
    • sans Homebrew : voir la page « First, set up the engines » du guide (onglet YouTube).
    """

    /// Titre et chaîne via l'API publique oEmbed (aucune clé nécessaire).
    static func info(_ link: URL) async -> (title: String, author: String)? {
        var c = URLComponents(string: "https://www.youtube.com/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: link.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let u = c.url, let (data, _) = try? await URLSession.shared.data(from: u),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = j["title"] as? String else { return nil }
        return (t, j["author_name"] as? String ?? "")
    }

    static func arguments(link: URL, audio: Bool, audioFormat: String = "mp3", dir: URL, videoFormat: String = "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4]/bv*+ba/b", namePrefix: String = "") -> [String] {
        var a = ["--no-playlist", "--newline", "--progress", "--no-warnings", "-P", dir.path, "-o", namePrefix.replacingOccurrences(of: "%", with: "%%") + "%(title).150B.%(ext)s",
                 "--print", "after_move:filepath", "--no-simulate"]
        if let ff = FFmpeg.ffmpeg { a += ["--ffmpeg-location", ff.deletingLastPathComponent().path] }
        if audio {
            if audioFormat == "wav" {      // WAV : sans perte à partir de la source, ni pochette ni étiquettes (le format ne les porte pas)
                a += ["-x", "--audio-format", "wav"]
            } else {
                a += ["-x", "--audio-format", "mp3", "--audio-quality", "0", "--embed-metadata", "--embed-thumbnail", "--convert-thumbnails", "jpg"]
            }
        } else {
            // H.264 + AAC dans un MP4 lisible partout ; à défaut, la meilleure combinaison disponible
            a += ["-f", videoFormat, "--merge-output-format", "mp4", "--embed-metadata"]
        }
        return a + [link.absoluteString]
    }

    /// Télécharge et retourne le fichier final. En MP4 : on essaie H.264+AAC d'abord, puis la sélection par défaut de yt-dlp
    /// (YouTube refuse parfois certains formats avec une erreur 403) ; si le résultat n'est pas en H.264/AAC (AV1, VP9, Opus…),
    /// il est converti pour être lisible partout (QuickTime, iPhone, montage).
    /// `maxHeight` : hauteur maximale en pixels (nil = la meilleure). `namePrefix` : par ex. « 03 - » pour numéroter une liste.
    static func download(_ link: URL, audio: Bool, audioFormat: String = "mp3", to dir: URL, maxHeight: Int? = nil, namePrefix: String = "", progress: @escaping (Double) -> Void) async throws -> URL {
        if audio { return try await run(link, audio: true, audioFormat: audioFormat, dir: dir, format: "", namePrefix: namePrefix, progress: progress) }
        var lastError: Error = MandarineError("Téléchargement impossible.")
        let cap = maxHeight.map { "[height<=\($0)]" } ?? ""
        for format in ["bv*\(cap)[vcodec^=avc1]+ba[acodec^=mp4a]/b\(cap)[ext=mp4]", "bv*\(cap)+ba/b\(cap)"] {
            do {
                let f = try await run(link, audio: false, dir: dir, format: format, namePrefix: namePrefix) { progress($0 * 0.85) }
                return try await makeCompatible(f) { progress(0.85 + $0 * 0.15) }
            } catch let e as MandarineError where e.message.contains("403") || e.message.contains("format") { lastError = e; continue }
        }
        throw lastError
    }

    /// Convertit en H.264 + AAC si nécessaire (remplace le fichier).
    private static func makeCompatible(_ file: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let i = await FFmpeg.probe(file)
        if ["h264", "hevc"].contains(i.codec) && (i.audioCodec == "aac" || i.audioCodec.isEmpty) { return file }
        guard FFmpeg.isAvailable else { return file }
        let tmp = file.deletingLastPathComponent().appendingPathComponent(".converting-" + file.lastPathComponent)
        try await FFmpeg.run(["-i", file.path, "-map", "0:v:0", "-map", "0:a:0?", "-vf", "format=yuv420p"] + FFmpeg.videoArgs(for: "mp4") + ["-f", "mp4", tmp.path], duration: i.duration, progress: progress)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        return file
    }

    private static func run(_ link: URL, audio: Bool, audioFormat: String = "mp3", dir: URL, format: String, namePrefix: String = "", progress: @escaping (Double) -> Void) async throws -> URL {
        guard let exe = url else { throw MandarineError(installHelp) }
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = exe
                p.arguments = format.isEmpty ? arguments(link: link, audio: audio, audioFormat: audioFormat, dir: dir, namePrefix: namePrefix) : arguments(link: link, audio: audio, dir: dir, videoFormat: format, namePrefix: namePrefix)
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                var finalPath: String?
                var errText = ""
                var buffer = ""
                out.fileHandleForReading.readabilityHandler = { h in
                    guard let s = String(data: h.availableData, encoding: .utf8), !s.isEmpty else { return }
                    buffer += s
                    while let nl = buffer.firstIndex(of: "\n") {
                        let line = String(buffer[..<nl]); buffer.removeSubrange(...nl)
                        if line.hasPrefix("/") { finalPath = line }
                        else if line.contains("[download]"), let r = line.range(of: #"(\d+(\.\d+)?)%"#, options: .regularExpression),
                                let v = Double(line[r].dropLast()) { progress(v / 100) }
                    }
                }
                err.fileHandleForReading.readabilityHandler = { h in errText += String(data: h.availableData, encoding: .utf8) ?? "" }
                guard box.attach(p) else { cont.resume(throwing: CancellationError()); return }
                do { try p.run() } catch { cont.resume(throwing: error); return }
                p.waitUntilExit()
                out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
                if box.cancelled { cont.resume(throwing: CancellationError()); return }
                if p.terminationStatus == 0, let f = finalPath, FileManager.default.fileExists(atPath: f) { cont.resume(returning: URL(fileURLWithPath: f)) }
                else {
                    let msg = errText.split(separator: "\n").suffix(3).joined(separator: "\n")
                    cont.resume(throwing: MandarineError((msg.isEmpty ? "yt-dlp a échoué (code \(p.terminationStatus))." : msg) + "\nIf it keeps failing, update yt-dlp in Settings → Engines."))
                }
            }
          }
        } onCancel: { box.cancel() }
    }
}
