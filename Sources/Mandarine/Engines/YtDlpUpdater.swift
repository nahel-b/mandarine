import Foundation
import CryptoKit

/// Vérifie et installe la dernière version de yt-dlp. Les sites changent souvent ; sans mise à jour, les téléchargements finissent par échouer.
/// La version officielle (exécutable universel du projet yt-dlp sur GitHub) est vérifiée avec son empreinte SHA-256 publiée,
/// essayée avant remplacement, puis placée dans le dossier des moteurs de Mandarine, qui est prioritaire (Homebrew n'est pas modifié).
@MainActor
final class YtDlpUpdater: ObservableObject {
    static let shared = YtDlpUpdater()

    enum State: Equatable { case idle, checking, upToDate, available(String), installing, installed(String), failed(String) }
    @Published var state: State = .idle
    @Published var current = ""

    private static let releases = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/"
    private static let api = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

    var installedPath: String? { YtDlp.url?.path }

    /// Dossier de destination ; modifiable pour les tests.
    nonisolated(unsafe) static var destination = FFmpeg.enginesFolder

    /// Le numéro de version est noté à côté du programme au moment de l'installation : lancer `yt-dlp --version` peut prendre plusieurs secondes
    /// (premier lancement vérifié par macOS), et l'affichage ne doit pas dépendre de cette attente.
    nonisolated private static var versionNote: URL { destination.appendingPathComponent("yt-dlp.version") }

    private func noted() -> String? {
        guard let bin = YtDlp.url, bin.deletingLastPathComponent().path == Self.destination.path,
              let v = try? String(contentsOf: Self.versionNote, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty,
              let binDate = try? bin.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let noteDate = try? Self.versionNote.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              noteDate >= binDate.addingTimeInterval(-120) else { return nil }          // programme remplacé à la main depuis : la note est périmée
        return v
    }

    func refreshCurrent() async {
        if let v = noted() { current = v; return }
        guard YtDlp.url != nil, let d = try? await YtDlp.capture(["--version"], timeout: 90) else { current = ""; return }
        current = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func check() async {
        state = .checking
        await refreshCurrent()
        do {
            let latest = try await Self.latestVersion()
            if YtDlp.url == nil || current.isEmpty || Self.isNewer(latest, than: current) { state = .available(latest) } else { state = .upToDate }
        } catch {
            state = .failed("Couldn't check: \(error.localizedDescription)")
        }
    }

    func install() async {
        state = .installing
        do {
            let version = try await Task.detached { try await Self.downloadAndInstall() }.value
            if !version.isEmpty { current = version } else { await refreshCurrent() }
            state = .installed(version.isEmpty ? current : version)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Réseau

    nonisolated private static func fetch(_ s: String) async throws -> (Data, URL?) {
        var req = URLRequest(url: URL(string: s)!)
        req.setValue("Mandarine", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MandarineError("The server answered with an error (\((resp as? HTTPURLResponse)?.statusCode ?? 0)).") }
        return (data, resp.url)
    }

    nonisolated static func latestVersion() async throws -> String {
        let (data, _) = try await fetch(api)
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String else { throw MandarineError("Unexpected answer from GitHub.") }
        return tag
    }

    /// Compare des versions datées « 2026.08.19 » ou « 2026.08.19.1 ».
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p > q }
        }
        return false
    }

    nonisolated static func downloadAndInstall() async throws -> String {
        let name = "yt-dlp_macos"
        let (binary, _) = try await fetch(releases + name)
        let (sums, _) = try await fetch(releases + "SHA2-256SUMS")
        let line = String(data: sums, encoding: .utf8)?.split(separator: "\n").first { $0.split(separator: " ").last.map(String.init) == name }
        guard let expected = line?.split(separator: " ").first.map(String.init) else { throw MandarineError("The published checksum for yt-dlp wasn't found.") }
        let actual = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw MandarineError("The download doesn't match its published checksum — nothing was installed.") }

        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let staging = destination.appendingPathComponent("yt-dlp.new")
        try? fm.removeItem(at: staging)
        try binary.write(to: staging)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)

        // On l'essaie avant de remplacer l'ancien
        let version = try await Task.detached { () throws -> String in
            let p = Process(); p.executableURL = staging; p.arguments = ["--version"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            try p.run()
            let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw MandarineError("The downloaded yt-dlp doesn't start on this Mac.") }
            return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }.value
        let final = destination.appendingPathComponent("yt-dlp")
        try? fm.removeItem(at: final)
        try fm.moveItem(at: staging, to: final)
        try? version.write(to: versionNote, atomically: true, encoding: .utf8)
        return version
    }
}
