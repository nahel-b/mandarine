import AppKit

enum OutputNaming {
    /// URL libre à côté de l'original : « photo.png », puis « photo 2.png »…  Ne remplace jamais un fichier existant.
    static func sibling(of source: URL, suffix: String = "", ext: String? = nil, in dir: URL? = nil) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        let e = ext ?? (source.pathExtension.lowercased() == "m3u8" ? "mp4" : source.pathExtension)      // un flux HLS ressort en MP4
        let folder = dir ?? writableFolder(for: source)
        return unique(folder: folder, base: base, ext: e)
    }

    /// Le dossier de l'original, sauf s'il est en lecture seule (un DVD, un volume protégé) : le résultat va alors dans Films (vidéos) ou sur le Bureau.
    static func writableFolder(for source: URL) -> URL {
        let dir = source.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: dir.path) { return dir }
        if let chosen = OutputChoice.folder(for: dir) { return chosen }          // l'utilisateur a choisi où enregistrer
        let fm = FileManager.default
        let kind = FileKind.detect(source)
        let movies = fm.urls(for: .moviesDirectory, in: .userDomainMask).first, desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        return ((kind == .video || kind == .audio) ? movies : desktop) ?? fm.temporaryDirectory
    }

    static func unique(folder: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        func make(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return ext.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while fm.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }

    /// Dossier de sortie « photo clips », « report pages »… pour les opérations qui produisent plusieurs fichiers.
    static func folder(of source: URL, suffix: String) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + " " + suffix
        let dir = unique(folder: source.deletingLastPathComponent(), base: base, ext: "")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func tempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }
}

/// Quand l'original est sur un disque en lecture seule (DVD…), on laisse choisir le dossier où enregistrer le résultat.
enum OutputChoice {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var chosen: [String: URL] = [:]

    static func folder(for dir: URL) -> URL? { lock.lock(); defer { lock.unlock() }; return chosen[dir.standardizedFileURL.path] }
    private static func set(_ out: URL, for dirs: [URL]) { lock.lock(); defer { lock.unlock() }; for d in dirs { chosen[d.standardizedFileURL.path] = out } }

    /// Demande le dossier de sortie si l'un des fichiers est dans un dossier en lecture seule. Rend faux si on annule (rien ne démarre).
    /// `MANDARINE_OUTDIR` (essais) répond à la place de la fenêtre.
    @MainActor static func askIfNeeded(for urls: [URL]) -> Bool {
        let fm = FileManager.default
        let readOnly = Set(urls.filter(\.isFileURL).map { $0.deletingLastPathComponent() }.filter { !fm.isWritableFile(atPath: $0.path) })
        guard !readOnly.isEmpty else { return true }
        if let forced = ProcessInfo.processInfo.environment["MANDARINE_OUTDIR"] { set(URL(fileURLWithPath: forced, isDirectory: true), for: Array(readOnly)); return true }
        let defaults = UserDefaults.standard
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.message = L("This disc or folder is read-only. Choose where to save the result.")
        panel.prompt = L("Save here")
        let last = defaults.string(forKey: "lastReadOnlyOutput").map { URL(fileURLWithPath: $0, isDirectory: true) }
        panel.directoryURL = last ?? fm.urls(for: .moviesDirectory, in: .userDomainMask).first
        // pour une vidéo de caméscope, le choix de l'entrelacement est proposé là, au moment de convertir
        var popup: NSPopUpButton?
        if urls.contains(where: { FileKind.interlacedExts.contains($0.pathExtension.lowercased()) }) {
            let menu = NSPopUpButton(frame: .zero, pullsDown: false)
            menu.addItems(withTitles: InterlaceMode.allCases.map(\.title))
            menu.selectItem(at: InterlaceMode.allCases.firstIndex(of: AppSettings.shared.interlaceMode) ?? 0)
            let row = NSStackView(views: [NSTextField(labelWithString: L("Interlacing:")), menu])
            row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            row.frame = NSRect(origin: .zero, size: row.fittingSize)
            panel.accessoryView = row; panel.isAccessoryViewDisclosed = true
            popup = menu
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return false }
        if let m = popup, InterlaceMode.allCases.indices.contains(m.indexOfSelectedItem) { AppSettings.shared.interlaceMode = InterlaceMode.allCases[m.indexOfSelectedItem] }
        defaults.set(dir.path, forKey: "lastReadOnlyOutput")
        set(dir, for: Array(readOnly))
        return true
    }
}

struct MandarineError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

extension Int64 {
    var humanSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension URL {
    var fileSize: Int64 {
        if pathExtension.lowercased() == "m3u8", HLS.isStream(self) { return HLS.totalSize(self) }      // playlist + segments
        let v = try? resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if v?.isDirectory == true {
            let en = FileManager.default.enumerator(at: self, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let u = en?.nextObject() as? URL { total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return total
        }
        return Int64(v?.fileSize ?? 0)
    }
}
