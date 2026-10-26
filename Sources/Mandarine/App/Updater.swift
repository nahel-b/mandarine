import AppKit
import CryptoKit

/// Mises à jour par GitHub : l'app lit la dernière « release » du dépôt, télécharge Mandarine.zip,
/// vérifie sa signature (Ed25519, clé publique intégrée à l'app) puis remplace l'app et la relance.
/// Sans signature valide, rien n'est installé : même si le dépôt était piraté, on ne peut pas pousser une fausse version.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release { let version: String; let zip: URL; let signature: URL; let notes: String }
    enum State: Equatable { case idle, checking, upToDate, available(String), downloading(Double), installing, failed(String) }

    @Published var state: State = .idle
    private var release: Release?
    private var timer: Timer?
    private var toastID: UUID?
    private var busy = false

    // MARK: Configuration (Info.plist, réglée par Scripts/update.conf ; variables d'environnement pour les tests)

    private var env: [String: String] { ProcessInfo.processInfo.environment }
    var currentVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0" }
    private var repo: String? {
        let r = (Bundle.main.object(forInfoDictionaryKey: "MandarineUpdateRepo") as? String) ?? ""
        return r.contains("/") ? r : nil
    }
    private var feedURL: URL? {
        if let t = env["MANDARINE_UPDATE_API"] { return URL(string: t) }
        return repo.flatMap { URL(string: "https://api.github.com/repos/\($0)/releases/latest") }
    }
    private var publicKey: Curve25519.Signing.PublicKey? {
        let b64 = env["MANDARINE_UPDATE_PUBKEY"] ?? (Bundle.main.object(forInfoDictionaryKey: "MandarineUpdatePublicKey") as? String) ?? ""
        return Data(base64Encoded: b64).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }
    var isConfigured: Bool { feedURL != nil && publicKey != nil }
    private var targetApp: URL { env["MANDARINE_UPDATE_TARGET"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.bundleURL }

    // MARK: Vérification

    /// À appeler au lancement : première vérification peu après, puis toutes les 6 heures.
    func start() {
        guard isConfigured else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, AppSettings.shared.autoCheckUpdates else { return }
            Task { await self.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            guard let self = self, AppSettings.shared.autoCheckUpdates else { return }
            Task { @MainActor in await self.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) async {
        guard !busy else { return }
        guard let feed = feedURL, publicKey != nil else {
            if userInitiated { Toast.shared.fail("Updates aren't set up", subtitle: "This build has no update source. Set GITHUB_REPO in Scripts/update.conf and rebuild.") }
            return
        }
        state = .checking
        do {
            var req = URLRequest(url: feed); req.setValue("Mandarine", forHTTPHeaderField: "User-Agent"); req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
                throw MandarineError(h.statusCode == 404 ? "No published release found in the repository." : "GitHub answered with an error (\(h.statusCode)).")
            }
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String,
                  let assets = j["assets"] as? [[String: Any]] else { throw MandarineError("Unexpected answer from GitHub.") }
            func asset(_ name: String) -> URL? { assets.first { $0["name"] as? String == name }.flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:)) }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard YtDlpUpdater.isNewer(version, than: currentVersion) else {
                state = .upToDate
                if userInitiated { Toast.shared.done("Mandarine is up to date", subtitle: "Version \(currentVersion)") }
                return
            }
            guard let zip = asset("Mandarine.zip"), let sig = asset("Mandarine.zip.sig") else { throw MandarineError("Release \(tag) has no signed Mandarine.zip.") }
            let notes = ((j["body"] as? String) ?? "").split(separator: "\n").first.map(String.init) ?? ""
            release = Release(version: version, zip: zip, signature: sig, notes: notes)
            state = .available(version)
            if AppSettings.shared.autoInstallUpdates && !userInitiated { await installWhenIdle() } else { announce() }
        } catch {
            state = .failed(error.localizedDescription)
            if userInitiated { Toast.shared.fail("Couldn't check for updates", subtitle: error.localizedDescription) }
        }
    }

    private func announce() {
        guard let r = release else { return }
        if let id = toastID { Toast.shared.remove(id) }
        toastID = Toast.shared.add(ToastItem(id: UUID(), phase: .done, title: "Mandarine \(r.version) is available", subtitle: r.notes.isEmpty ? "You have \(currentVersion)." : r.notes,
                                              action: ("Update", { [weak self] in Task { @MainActor in await self?.install() } }), sticky: true))
    }

    /// Installation automatique : seulement quand l'app ne travaille pas (aucun travail en cours, aucune fenêtre d'outil ouverte).
    private func installWhenIdle() async {
        if JobQueue.shared.isIdle && !ToolWindowController.hasOpenWindows { await install(); return }
        announce()
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self = self, case .available = self.state, AppSettings.shared.autoInstallUpdates else { return }
            Task { await self.installWhenIdle() }
        }
    }

    // MARK: Installation

    func install() async {
        guard !busy, let r = release, let key = publicKey else { return }
        busy = true; defer { busy = false }
        if let id = toastID { Toast.shared.remove(id) }
        let id = Toast.shared.add(ToastItem(id: UUID(), phase: .running, title: "Updating to Mandarine \(r.version)…", subtitle: "Downloading", progress: 0))
        toastID = id
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-update-" + UUID().uuidString)
        do {
            state = .downloading(0)
            let (zipFile, resp) = try await Downloader.fetch(r.zip) { p in DispatchQueue.main.async { Toast.shared.update(id) { $0.progress = p } } }
            defer { try? FileManager.default.removeItem(at: zipFile) }
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw MandarineError("The download failed (\(h.statusCode)).") }
            let (sigData, _) = try await URLSession.shared.data(from: r.signature)
            guard let sig = Data(base64Encoded: String(decoding: sigData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { throw MandarineError("The update signature is unreadable.") }
            let zipData = try Data(contentsOf: zipFile, options: .mappedIfSafe)
            guard key.isValidSignature(sig, for: zipData) else { throw MandarineError("The update's signature is invalid — it was NOT installed.") }

            state = .installing
            Toast.shared.update(id) { $0.subtitle = "Installing"; $0.progress = -1 }
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let unzip = try Self.run("/usr/bin/ditto", ["-x", "-k", zipFile.path, work.path])
            guard unzip.status == 0 else { throw MandarineError("Couldn't unpack the update.") }
            let newApp = work.appendingPathComponent("Mandarine.app")
            guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier ?? "com.mandarine.app",
                  info["CFBundleShortVersionString"] as? String == r.version else { throw MandarineError("The downloaded app isn't the expected version.") }
            let dest = targetApp
            guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
                throw MandarineError("Mandarine can't replace itself in \(dest.deletingLastPathComponent().path). Move it to your Applications folder, or reinstall it from the latest DMG.")
            }
            try Self.swapAndRelaunch(newApp: newApp, dest: dest, work: work, relaunch: env["MANDARINE_UPDATE_NORELAUNCH"] == nil)
            Toast.shared.update(id) { $0.phase = .done; $0.title = "Mandarine \(r.version) installed"; $0.subtitle = "Restarting…"; $0.progress = nil }
            if env["MANDARINE_UPDATE_NORELAUNCH"] == nil { NSApp.terminate(nil) }
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed(error.localizedDescription)
            Toast.shared.update(id) { $0.phase = .failed; $0.title = "Update failed"; $0.subtitle = error.localizedDescription; $0.detail = error.localizedDescription; $0.progress = nil }
        }
    }

    nonisolated private static func run(_ exe: String, _ args: [String]) throws -> (status: Int32, output: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self))
    }

    /// Un petit script attend la fermeture de l'app, remplace le dossier .app (l'ancien est gardé jusqu'au succès, puis restauré en cas d'échec) et la relance.
    private static func swapAndRelaunch(newApp: URL, dest: URL, work: URL, relaunch: Bool) throws {
        let script = work.appendingPathComponent("swap.sh")
        try """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"; OPEN="$5"
        if [ "$PID" != "-" ]; then while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done; fi
        BACKUP="$DEST.previous"
        rm -rf "$BACKUP"
        mv "$DEST" "$BACKUP" || exit 1
        if /usr/bin/ditto "$NEW" "$DEST"; then
          /usr/bin/xattr -cr "$DEST" 2>/dev/null
          rm -rf "$BACKUP"
        else
          rm -rf "$DEST"; mv "$BACKUP" "$DEST"
        fi
        rm -rf "$WORK"
        if [ "$OPEN" = "1" ]; then /usr/bin/open "$DEST"; fi
        """.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, relaunch ? String(ProcessInfo.processInfo.processIdentifier) : "-", newApp.path, dest.path, work.path, relaunch ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        try p.run()
        if !relaunch { p.waitUntilExit(); if p.terminationStatus != 0 { throw MandarineError("The new version couldn't be put in place.") } }
    }
}
