import Foundation

enum OutputNaming {
    /// URL libre à côté de l'original : « photo.png », puis « photo 2.png »…  Ne remplace jamais un fichier existant.
    static func sibling(of source: URL, suffix: String = "", ext: String? = nil, in dir: URL? = nil) -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        let e = ext ?? source.pathExtension
        let folder = dir ?? source.deletingLastPathComponent()
        return unique(folder: folder, base: base, ext: e)
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
