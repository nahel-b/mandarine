import SwiftUI
import AppKit

/// Les versions publiées sur GitHub (lues sans identifiant, le dépôt est public) : de quoi retélécharger l'app ou revenir à une version précédente.
@MainActor
final class ReleaseList: ObservableObject {
    static let shared = ReleaseList()

    struct Release: Identifiable {
        let tag: String, version: String, date: Date?, page: URL, prerelease: Bool
        let dmg: (url: URL, size: Int64)?
        let dmgCount: Int, zipCount: Int          // téléchargements du .dmg (à la main) et du .zip (mises à jour automatiques)
        var total: Int { dmgCount + zipCount }
        var id: String { tag }
    }
    enum State { case idle, loading, loaded, failed(String) }

    @Published var state: State = .idle
    @Published var releases: [Release] = []
    @Published var progress: [String: Double] = [:]        // tag → avancement du téléchargement en cours
    private var loadedAt: Date?

    var repo: String? { Updater.shared.repoSlug }
    var repoURL: URL? { repo.flatMap { URL(string: "https://github.com/\($0)") } }
    var releasesURL: URL? { repoURL?.appendingPathComponent("releases") }

    func load(force: Bool = false) async {
        guard let repo = repo, let api = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=50") else { return }
        if !force, let t = loadedAt, Date().timeIntervalSince(t) < 300, !releases.isEmpty { return }
        state = .loading
        do {
            var req = URLRequest(url: api); req.setValue("Mandarine", forHTTPHeaderField: "User-Agent"); req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); req.timeoutInterval = 20
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw MandarineError(h.statusCode == 403 ? "GitHub is limiting requests for now. Try again in a few minutes." : "GitHub answered with an error (\(h.statusCode)).") }
            guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MandarineError("Unexpected answer from GitHub.") }
            let iso = ISO8601DateFormatter()
            releases = list.compactMap { j in
                guard (j["draft"] as? Bool) != true, let tag = j["tag_name"] as? String, let page = (j["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
                let assets = (j["assets"] as? [[String: Any]]) ?? []
                let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }.flatMap { a -> (URL, Int64)? in
                    guard let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
                    return (u, (a["size"] as? Int64) ?? Int64((a["size"] as? Int) ?? 0))
                }
                func count(_ suffix: String) -> Int { assets.first { ($0["name"] as? String)?.hasSuffix(suffix) == true }.flatMap { $0["download_count"] as? Int } ?? 0 }
                return Release(tag: tag, version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, date: (j["published_at"] as? String).flatMap { iso.date(from: $0) },
                               page: page, prerelease: (j["prerelease"] as? Bool) == true, dmg: dmg, dmgCount: count(".dmg"), zipCount: count(".zip"))
            }
            loadedAt = Date()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Télécharge le .dmg dans le dossier Téléchargements, puis le montre dans le Finder.
    func download(_ r: Release) async {
        guard let dmg = r.dmg, progress[r.tag] == nil else { return }
        progress[r.tag] = 0
        defer { progress[r.tag] = nil }
        do {
            let (tmp, resp) = try await Downloader.fetch(dmg.url) { p in DispatchQueue.main.async { ReleaseList.shared.progress[r.tag] = p } }
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { try? FileManager.default.removeItem(at: tmp); throw MandarineError("The download failed (\(h.statusCode)).") }
            let dest = OutputNaming.unique(folder: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0], base: "Mandarine-\(r.version)", ext: "dmg")
            try FileManager.default.moveItem(at: tmp, to: dest)
            Toast.shared.done("Downloaded", subtitle: "\(dest.lastPathComponent)\nin Downloads", reveal: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            Toast.shared.fail("Download failed", subtitle: error.localizedDescription)
        }
    }
}

/// Onglet « Download » des Réglages.
struct DownloadTab: View {
    @ObservedObject var list = ReleaseList.shared
    @ObservedObject var updater = Updater.shared

    private static let dateFormat: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; return f }()

    var body: some View {
        Group {
            Section("Mandarine on GitHub") {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.82)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.repo ?? "No repository set").font(.system(size: 13, weight: .semibold))
                        Text("Open source · every version is published here").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let u = list.repoURL { Link("Repository", destination: u) }
                    if let u = list.releasesURL { Link("All releases", destination: u) }
                }
            }
            switch list.state {
            case _ where list.repo == nil:
                Section("Versions") { Text("This build has no GitHub repository set (GITHUB_REPO in Scripts/update.conf).").font(.caption).foregroundStyle(.secondary) }
            case .idle, .loading where list.releases.isEmpty:
                Section("Versions") { HStack { ProgressView().controlSize(.small); Text("Reading the releases…").foregroundStyle(.secondary) } }
            case .failed(let m) where list.releases.isEmpty:
                Section("Versions") {
                    Text(m).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await list.load(force: true) } }
                }
            default:
                Section("Downloads") { stats }
                if let latest = list.releases.first(where: { !$0.prerelease }) ?? list.releases.first {
                    Section("Latest version") { row(latest, latest: true) }
                    let older = list.releases.filter { $0.id != latest.id }
                    if !older.isEmpty { Section("Earlier versions") { ForEach(older) { row($0, latest: false) } } }
                }
                Section {
                    HStack {
                        Text("The disk image (.dmg) goes to your Downloads folder. Installed copies keep themselves up to date from the Updates tab.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Refresh") { Task { await list.load(force: true) } }
                    }
                }
            }
        }
        .task { await list.load() }
    }

    private var stats: some View {
        let all = list.releases
        let peak = max(all.map(\.total).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                tile("\(all.reduce(0) { $0 + $1.total })", "downloads in all", Theme.orange)
                tile("\(all.reduce(0) { $0 + $1.dmgCount })", "disk images (.dmg)", .blue)
                tile("\(all.reduce(0) { $0 + $1.zipCount })", "updates (.zip)", .green)
            }
            if all.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Per version").font(.caption).foregroundStyle(.secondary)
                    ForEach(all.prefix(12)) { r in
                        HStack(spacing: 8) {
                            Text(r.version).font(.system(size: 11).monospacedDigit()).frame(width: 44, alignment: .leading)
                            GeometryReader { g in
                                HStack(spacing: 0) {
                                    Rectangle().fill(Color.blue.opacity(0.75)).frame(width: g.size.width * CGFloat(r.dmgCount) / CGFloat(peak))
                                    Rectangle().fill(Color.green.opacity(0.75)).frame(width: g.size.width * CGFloat(r.zipCount) / CGFloat(peak))
                                    Spacer(minLength: 0)
                                }.clipShape(Capsule())
                            }.frame(height: 7)
                            Text("\(r.total)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
            Text("The .zip is what installed copies fetch when they update, so it also counts those updates.").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.1)))
    }

    private func row(_ r: ReleaseList.Release, latest: Bool) -> some View {
        let installed = r.version == updater.currentVersion
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Mandarine \(r.version)").font(.system(size: 13, weight: latest ? .semibold : .regular))
                    if latest { badge("Latest", Theme.orange) }
                    if installed { badge("Installed", .green) }
                    if r.prerelease { badge("Pre-release", .gray) }
                }
                Text([r.date.map { Self.dateFormat.string(from: $0) }, "\(r.total) download\(r.total == 1 ? "" : "s")", r.dmg.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) }]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Link("Notes", destination: r.page).font(.caption)
            if let p = list.progress[r.tag] {
                ProgressView(value: p).frame(width: 70)
            } else if r.dmg != nil {
                Button(latest ? "Download" : "Get") { Task { await list.download(r) } }
            }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5).background(Capsule().fill(color.opacity(0.14)))
    }
}
