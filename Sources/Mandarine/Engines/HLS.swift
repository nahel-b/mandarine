import Foundation

/// Playlists HLS locales (.m3u8) : reconnaissance, taille réelle (segments compris) et copie lisible par AVFoundation.
enum HLS {
    private static let lock = NSLock()
    private static var kindCache: [String: (Date, Bool)] = [:]
    private static var proxies: [String: Task<URL, Never>] = [:]

    private static func mtime(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }

    /// Vrai pour une vraie playlist de flux HLS (pas pour une liste de lecture musicale en .m3u8).
    static func isStream(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "m3u8" else { return false }
        let m = mtime(url)
        lock.lock(); let hit = kindCache[url.path]; lock.unlock()
        if let hit = hit, hit.0 == m { return hit.1 }
        var ok = false
        if let h = try? FileHandle(forReadingFrom: url) {
            let d = (try? h.read(upToCount: 16384)) ?? Data()
            try? h.close()
            if let s = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) {
                let t = s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
                ok = t.hasPrefix("#EXTM3U") && (t.contains("#EXT-X-TARGETDURATION") || t.contains("#EXT-X-STREAM-INF"))
            }
        }
        lock.lock(); kindCache[url.path] = (m, ok); lock.unlock()
        return ok
    }

    /// Les adresses (segments, sous-playlists, clés) citées dans la playlist.
    private static func references(_ url: URL) -> [String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [String] = []
        for raw in s.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if let r = line.range(of: "URI=\"") , let e = line[r.upperBound...].firstIndex(of: "\"") { out.append(String(line[r.upperBound..<e])) }
            } else { out.append(line) }
        }
        return out
    }

    private static func isRemote(_ ref: String) -> Bool { ref.lowercased().hasPrefix("http://") || ref.lowercased().hasPrefix("https://") }

    /// La playlist cite-t-elle des segments sur le web ?
    static func hasRemoteSegments(_ url: URL) -> Bool { references(url).contains(where: isRemote) }

    /// Taille de la playlist et de tous les fichiers locaux qu'elle cite.
    static func totalSize(_ url: URL, depth: Int = 0, seen: inout Set<String>) -> Int64 {
        var total = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        seen.insert(url.path)
        let dir = url.deletingLastPathComponent()
        for ref in references(url) where !isRemote(ref) {
            let target = (URL(string: ref, relativeTo: dir)?.absoluteURL).flatMap { $0.isFileURL ? $0 : nil } ?? dir.appendingPathComponent(ref)
            guard !seen.contains(target.path) else { continue }
            if target.pathExtension.lowercased() == "m3u8" {
                if depth < 2 { total += totalSize(target, depth: depth + 1, seen: &seen) }
            } else {
                seen.insert(target.path)
                total += Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    static func totalSize(_ url: URL) -> Int64 { var seen = Set<String>(); return totalSize(url, seen: &seen) }

    private static func proxyTask(_ url: URL) -> Task<URL, Never> {
        let key = url.path + "|\(mtime(url).timeIntervalSince1970)"
        lock.lock(); defer { lock.unlock() }
        if let t = proxies[key] { return t }
        let t = Task<URL, Never> {
            let tmp = OutputNaming.tempURL(ext: "mp4")
            do { try await FFmpeg.run(["-i", url.path, "-c", "copy", tmp.path]); return tmp } catch { return url }
        }
        proxies[key] = t
        return t
    }

    /// Fichier que AVFoundation sait lire : l'URL elle-même, ou pour une playlist HLS une copie MP4 sans réencodage (rapide, gardée en cache).
    static func playable(_ url: URL) async -> URL {
        guard isStream(url) else { return url }
        return await proxyTask(url).value
    }

    /// Message plus clair quand ffmpeg échoue sur une playlist qui pointe vers le web.
    static func explainFailure(args: [String], message: String) -> String? {
        guard let input = args.first(where: { $0.lowercased().hasSuffix(".m3u8") && $0.hasPrefix("/") }) else { return nil }
        let url = URL(fileURLWithPath: input)
        if hasRemoteSegments(url) {
            return L("This playlist points to video segments on the web. They must be reachable (internet connection, no special access needed) for Mandarine to read them.")
        }
        let dir = url.deletingLastPathComponent()
        let missing = references(url).first { !isRemote($0) && !$0.lowercased().hasSuffix(".m3u8") && !FileManager.default.fileExists(atPath: (URL(string: $0, relativeTo: dir)?.path ?? dir.appendingPathComponent($0).path)) }
        if let m = missing { return L("A segment of this playlist is missing: \(m). Keep the .m3u8 file next to its video segments.") }
        return nil
    }
}
