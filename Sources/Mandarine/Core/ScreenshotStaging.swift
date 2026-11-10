import Foundation

/// La miniature d'une capture d'écran (en bas de l'écran juste après la capture) est un fichier TEMPORAIRE : macOS l'enregistre
/// seulement quand la miniature disparaît, et le supprime une fois le glisser terminé. On le recopie donc au dépôt, dans le dossier
/// où macOS enregistre les captures, pour que le travail (qui est asynchrone) ne perde pas son fichier et que le résultat atterrisse
/// à côté d'une vraie capture.
enum ScreenshotStaging {
    static func isTemporary(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let p = url.path
        return p.contains("/TemporaryItems/") || p.contains("screencaptureui") || p.contains("NSIRD_")
    }

    /// Dossier d'enregistrement des captures (réglage macOS), sinon le Bureau.
    static var captureFolder: URL {
        let fm = FileManager.default
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let path = (loc as NSString).expandingTildeInPath
            var dir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &dir), dir.boolValue { return URL(fileURLWithPath: path, isDirectory: true) }
        }
        return fm.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Remplace chaque fichier temporaire par une copie stable (les autres fichiers passent tels quels).
    static func stabilize(_ urls: [URL], into folder: URL = captureFolder) -> [URL] {
        urls.map { u in
            guard isTemporary(u), FileManager.default.fileExists(atPath: u.path) else { return u }
            let dest = OutputNaming.unique(folder: folder, base: u.deletingPathExtension().lastPathComponent, ext: u.pathExtension)
            do { try FileManager.default.copyItem(at: u, to: dest); return dest }
            catch {
                if DragMonitor.debugLog { DragMonitor.log("STAGE copy failed: \(error)") }
                return u
            }
        }
    }

    /// Pour MANDARINE_DRAGLOG : l'état de chaque fichier au dépôt (existe, lisible) et ce qu'il est devenu.
    static func describe(_ dropped: [URL], _ staged: [URL]) -> String {
        let fm = FileManager.default
        var parts: [String] = []
        for u in dropped {
            var r = "read ok"
            do { _ = try Data(contentsOf: u) } catch { r = "read ERROR \(error)" }
            parts.append("\(u.path) exists=\(fm.fileExists(atPath: u.path)) \(r)")
        }
        return parts.joined(separator: " | ") + " → " + staged.map(\.path).joined(separator: " | ")
    }

    /// Où recevoir la capture : le dossier des captures si on peut y écrire, sinon un dossier temporaire à nous.
    static func promiseFolder() -> URL {
        let fm = FileManager.default
        let probe = captureFolder.appendingPathComponent(".mandarine-\(UUID().uuidString)")
        if (try? Data().write(to: probe)) != nil { try? fm.removeItem(at: probe); return captureFolder }
        let tmp = fm.temporaryDirectory.appendingPathComponent("Mandarine captures", isDirectory: true)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }
}
