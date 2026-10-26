import Foundation

/// Télécharge les moteurs manquants (ffmpeg + ffprobe, cwebp, modèle de visages) depuis les Réglages.
/// Tout est installé dans le dossier des moteurs de Mandarine (~/Library/Application Support/Mandarine), sans droits administrateur et sans Homebrew.
/// Chaque téléchargement est vérifié (empreinte SHA-256), le programme est essayé avant d'être installé.
@MainActor
final class EngineInstaller: ObservableObject {
    static let shared = EngineInstaller()

    enum Engine: String { case ffmpeg, cwebp, faceModel }
    enum State: Equatable { case working(Double), done, failed(String) }
    /// Dossier d'installation ; modifiable pour les tests.
    nonisolated(unsafe) static var destination = FFmpeg.enginesFolder
    @Published private(set) var states: [Engine: State] = [:]

    func state(_ e: Engine) -> State? { states[e] }
    func isWorking(_ e: Engine) -> Bool { if case .working = states[e] { return true }; return false }

    func install(_ e: Engine) {
        guard !isWorking(e) else { return }
        states[e] = .working(0)
        Task {
            do {
                switch e {
                case .ffmpeg: try await Self.installFFmpeg { p in Task { @MainActor in self.states[e] = .working(p) } }
                case .cwebp: try await Self.installCwebp { p in Task { @MainActor in self.states[e] = .working(p) } }
                case .faceModel: try await FaceModel.download { p in Task { @MainActor in self.states[e] = .working(p) } }
                }
                states[e] = .done
            } catch {
                states[e] = .failed(error.localizedDescription)
            }
            objectWillChange.send()
        }
    }

    // MARK: ffmpeg + ffprobe (versions statiques de ffmpeg.martin-riedl.de, Apple Silicon ou Intel)

    nonisolated private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    nonisolated static func installFFmpeg(progress: @escaping (Double) -> Void) async throws {
        let tools = ["ffmpeg", "ffprobe"]
        for (i, tool) in tools.enumerated() {
            let latest = URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/release/\(tool).zip")!
            let (tmp, resp) = try await Downloader.fetch(latest) { p in progress((Double(i) + p) / Double(tools.count)) }
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let final = resp.url else { throw MandarineError("The ffmpeg server answered with an error.") }
            // Empreinte publiée à côté de la version précise téléchargée
            var req = URLRequest(url: final.appendingPathExtension("sha256")); req.setValue("Mandarine", forHTTPHeaderField: "User-Agent")
            let (sumData, sumResp) = try await URLSession.shared.data(for: req)
            guard (sumResp as? HTTPURLResponse)?.statusCode == 200,
                  let expected = String(data: sumData, encoding: .utf8)?.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)?.lowercased()
            else { throw MandarineError("The published checksum for \(tool) wasn't found.") }
            guard try Downloader.sha256(of: tmp) == expected else { throw MandarineError("\(tool) doesn't match its published checksum — nothing was installed.") }
            try install(binary: tool, fromArchive: tmp, kind: .zip, pathInArchive: tool, versionArgument: "-version")
        }
        progress(1)
    }

    // MARK: cwebp (version officielle de libwebp publiée par Google)

    nonisolated static func installCwebp(progress: @escaping (Double) -> Void) async throws {
        #if arch(arm64)
        let (name, pinned) = ("mac-arm64", "bc6bf84cc70f3f8574fba797d1e4a7dea4feebe9fa4be919f202413ea2b3b8f2")
        #else
        let (name, pinned) = ("mac-x86-64", "f112dd83b420ab2a4b27d46610d9827ddf4200216023281de378647ecca31c2a")
        #endif
        let url = URL(string: "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0-\(name).tar.gz")!
        let (tmp, resp) = try await Downloader.fetch(url, progress: progress)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MandarineError("The WebP server answered with an error.") }
        guard try Downloader.sha256(of: tmp) == pinned else { throw MandarineError("cwebp doesn't match its expected checksum — nothing was installed.") }
        try install(binary: "cwebp", fromArchive: tmp, kind: .tar, pathInArchive: "libwebp-1.6.0-\(name)/bin/cwebp", versionArgument: "-version")
        progress(1)
    }

    // MARK: Installation d'un programme

    private enum Archive { case zip, tar }

    nonisolated private static func run(_ exe: String, _ args: [String]) throws -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run()
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(data: d, encoding: .utf8) ?? "")
    }

    /// Décompresse, essaie le programme (`--version`) — avec une signature locale si macOS refuse de le lancer —, puis le place dans le dossier des moteurs.
    nonisolated private static func install(binary name: String, fromArchive archive: URL, kind: Archive, pathInArchive: String, versionArgument: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("mandarine-install-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let (code, log) = kind == .zip ? try run("/usr/bin/unzip", ["-o", "-q", archive.path, "-d", work.path]) : try run("/usr/bin/tar", ["-xzf", archive.path, "-C", work.path])
        guard code == 0 else { throw MandarineError("Couldn't unpack \(name): \(log)") }
        let extracted = work.appendingPathComponent(pathInArchive)
        guard fm.fileExists(atPath: extracted.path) else { throw MandarineError("\(name) wasn't found in the downloaded archive.") }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: extracted.path)
        _ = try? run("/usr/bin/xattr", ["-cr", extracted.path])
        var (status, _) = (try? run(extracted.path, [versionArgument])) ?? (-1, "")
        if status != 0 {            // sur Apple Silicon, un programme non signé est refusé : signature locale (ad hoc)
            _ = try? run("/usr/bin/codesign", ["--force", "--sign", "-", extracted.path])
            (status, _) = (try? run(extracted.path, [versionArgument])) ?? (-1, "")
        }
        guard status == 0 else { throw MandarineError("The downloaded \(name) doesn't start on this Mac.") }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let dest = destination.appendingPathComponent(name)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: extracted, to: dest)
    }
}
