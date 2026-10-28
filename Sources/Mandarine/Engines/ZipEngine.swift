import Foundation

/// Archive ZIP d'une sélection (fichiers et dossiers, même mélangés) avec l'outil `zip` du système.
enum ZipEngine {
    static func make(_ urls: [URL]) async throws -> URL {
        guard let first = urls.first else { throw MandarineError("Nothing to zip.") }
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let out = OutputNaming.unique(folder: first.deletingLastPathComponent(), base: base, ext: "zip")
        // Dossier de travail avec un lien vers chaque élément (noms rendus uniques) : zip y suit les liens et range tout à la racine de l'archive
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("mandarine-zip-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        var used = Set<String>()
        for u in urls {
            var name = u.lastPathComponent, n = 2
            while used.contains(name) { name = u.deletingPathExtension().lastPathComponent + " \(n)" + (u.pathExtension.isEmpty ? "" : "." + u.pathExtension); n += 1 }
            used.insert(name)
            try fm.createSymbolicLink(at: stage.appendingPathComponent(name), withDestinationURL: u)
        }
        let box = ProcessBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    p.arguments = ["-r", "-X", "-q", out.path, ".", "-x", "*.DS_Store"]
                    p.currentDirectoryURL = stage
                    let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
                    guard box.attach(p) else { cont.resume(throwing: CancellationError()); return }
                    do { try p.run() } catch { cont.resume(throwing: error); return }
                    let msg = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                    if box.cancelled { try? FileManager.default.removeItem(at: out); cont.resume(throwing: CancellationError()); return }
                    if p.terminationStatus == 0 || p.terminationStatus == 12 { cont.resume() }      // 12 : « rien à ajouter » (ex. dossiers vides)
                    else { try? FileManager.default.removeItem(at: out); cont.resume(throwing: MandarineError("zip failed: " + String(decoding: msg, as: UTF8.self))) }
                }
            }
        } onCancel: { box.cancel() }
        guard fm.fileExists(atPath: out.path) else { throw MandarineError("Nothing to put in the archive.") }
        return out
    }
}
