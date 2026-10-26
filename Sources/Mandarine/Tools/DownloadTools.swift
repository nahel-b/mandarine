import SwiftUI

enum DownloadKind {
    case mp4, mp3, wav
    var audio: Bool { self != .mp4 }
    var format: String { self == .wav ? "wav" : "mp3" }
    var label: String { self == .mp4 ? "MP4" : (self == .mp3 ? "MP3" : "WAV") }
}

/// Téléchargement de liens (YouTube et autres sites via yt-dlp) : lien simple, ou liste (playlist, album, chaîne) avec choix.
enum DownloadFlow {
    private static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    static func start(links: [URL], kind: DownloadKind) {
        guard links.count == 1, YtDlp.mayBePlaylist(links[0]) else { links.forEach { single($0, kind: kind) }; return }
        let link = links[0]
        let id = UUID()
        var task: Task<Void, Never>?
        Toast.shared.add(ToastItem(id: id, phase: .running, title: "Checking link…", subtitle: link.host ?? "", progress: -1,
                                   cancel: { task?.cancel(); Toast.shared.remove(id) }))
        task = Task {
            let list = await YtDlp.playlist(link)
            await MainActor.run {
                guard !Task.isCancelled else { return }
                Toast.shared.remove(id)
                if let list = list {
                    ToolWindowController.present { close in AnyView(PlaylistTool(link: link, list: list, kind: kind, close: close)) }
                } else {
                    single(link, kind: kind)
                }
            }
        }
    }

    static func single(_ link: URL, kind: DownloadKind) {
        JobQueue.shared.add("Downloading \(kind.label)…", subtitle: link.host ?? "") { progress in
            [try await YtDlp.download(link, audio: kind.audio, audioFormat: kind.format, to: downloads, progress: progress)]
        }
    }

    /// Une seule ligne dans la pile pour toute la liste : « 3 of 27 — titre ». Un titre en échec n'arrête pas les suivants.
    static func playlist(_ list: YtDlp.Playlist, entries: [YtDlp.Playlist.Entry], kind: DownloadKind, maxHeight: Int?) {
        let name = list.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = OutputNaming.unique(folder: downloads, base: String((name.isEmpty ? "Playlist" : name).prefix(80)), ext: "")
        let n = entries.count, width = String(n).count
        JobQueue.shared.add("Downloading playlist (\(kind.label))…", subtitle: "\(n) items", statusWork: { progress, status in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var failures: [(String, String)] = []
            for (i, e) in entries.enumerated() {
                try Task.checkCancellation()
                status("\(i + 1) of \(n) — \(e.title)")
                do {
                    _ = try await YtDlp.download(e.url, audio: kind.audio, audioFormat: kind.format, to: folder, maxHeight: maxHeight,
                                                 namePrefix: String(format: "%0\(width)d - ", i + 1)) { p in progress((Double(i) + p) / Double(n)) }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append((e.title, error.localizedDescription))
                }
            }
            if failures.count == n { throw MandarineError(failures[0].1) }
            if !failures.isEmpty {
                let lines = failures.prefix(5).map { "• \($0.0): \($0.1.split(separator: "\n").last.map(String.init) ?? "")" }.joined(separator: "\n")
                DispatchQueue.main.async { Toast.shared.fail("\(failures.count) of \(n) downloads failed", subtitle: lines) }
            }
            return [folder]
        })
    }
}

/// Choix des éléments d'une liste avant de la télécharger.
struct PlaylistTool: View {
    let link: URL
    let list: YtDlp.Playlist
    let kind: DownloadKind
    let close: () -> Void
    @State private var selected: Set<Int>
    @State private var quality = 0          // 0 = la meilleure, sinon hauteur maximale

    init(link: URL, list: YtDlp.Playlist, kind: DownloadKind, close: @escaping () -> Void) {
        self.link = link; self.list = list; self.kind = kind; self.close = close
        _selected = State(initialValue: Set(list.entries.map(\.id)))
    }

    private var chosen: [YtDlp.Playlist.Entry] { list.entries.filter { selected.contains($0.id) } }
    private var totalDuration: Double { chosen.compactMap(\.duration).reduce(0, +) }

    var body: some View {
        ToolShell(title: "Download Playlist · \(kind.label)", close: close) {
            VStack(alignment: .leading, spacing: 10) {
                Text(list.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                HStack {
                    Text("\(selected.count) of \(list.entries.count) selected" + (totalDuration > 0 ? " · \(WheelInfo.duration(totalDuration))" : "")).sectionLabel()
                    Spacer()
                    Button("All") { selected = Set(list.entries.map(\.id)) }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.orange)
                    Button("None") { selected = [] }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.orange)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(list.entries) { e in
                            Button {
                                if selected.contains(e.id) { selected.remove(e.id) } else { selected.insert(e.id) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selected.contains(e.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selected.contains(e.id) ? Theme.orange : Theme.muted).font(.system(size: 14))
                                    Text(String(format: "%02d", e.id + 1)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted).frame(width: 24, alignment: .trailing)
                                    Text(e.title).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
                                    Spacer(minLength: 8)
                                    if let d = e.duration { Text(WheelInfo.duration(d)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.muted) }
                                }
                                .padding(.vertical, 5).padding(.horizontal, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 476, height: 280)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.1)))
                if !kind.audio {
                    HStack {
                        Text("Quality").sectionLabel()
                        Spacer()
                        Picker("", selection: $quality) {
                            Text("Best").tag(0); Text("1080p").tag(1080); Text("720p").tag(720); Text("480p").tag(480)
                        }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                    }
                }
                Text("Saved in a new folder in Downloads, numbered in order. A video that can't be downloaded is skipped; the others continue.")
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 476)
        } footer: {
            if YtDlp.hasSingleVideo(link) {
                Button("This video only") { close(); DownloadFlow.single(link, kind: kind) }.buttonStyle(PillButtonStyle())
            }
            Button(selected.count == 1 ? "Download 1 item" : "Download \(selected.count) items") {
                let (l, entries, k, q) = (list, chosen, kind, quality)
                close()
                DownloadFlow.playlist(l, entries: entries, kind: k, maxHeight: q == 0 ? nil : q)
            }.buttonStyle(PillButtonStyle()).disabled(selected.isEmpty)
        }
    }
}
