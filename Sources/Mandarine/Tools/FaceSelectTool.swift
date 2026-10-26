import SwiftUI

/// Face Select : montre un visage par personne repérée dans la sélection ; on coche ceux qu'on veut,
/// puis les fichiers où ils apparaissent sont sélectionnés dans le Finder.
struct FaceSelectTool: View {
    let urls: [URL]
    let close: () -> Void

    private enum Phase { case needModel, downloading(Double), scanning(done: Int, total: Int, faces: Int), ready, failed(String) }
    @State private var phase: Phase = .scanning(done: 0, total: 0, faces: 0)
    @State private var hits: [FaceHit] = []
    @State private var clusters: [FaceCluster] = []
    @State private var chosen: Set<Int> = []
    @State private var strictness: Double = 0.50          // similarité minimale pour regrouper deux visages

    private var files: [URL] {
        var seen = Set<URL>()
        return clusters.filter { chosen.contains($0.id) }.flatMap(\.files).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ToolShell(title: "Face Select", close: close) {
            VStack(spacing: 14) { content }.frame(width: 470)
        } footer: {
            if case .ready = phase {
                Button(files.count == 1 ? "Select 1 file" : "Select \(files.count) files") {
                    let f = files, n = urls.count; close(); TagSelect.select(f, of: n)
                }.buttonStyle(PillButtonStyle()).disabled(files.isEmpty)
            }
        }
        .task { await begin() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .needModel:
            VStack(spacing: 10) {
                Image(systemName: "face.dashed").font(.system(size: 30)).foregroundStyle(Theme.muted)
                Text("Face Select needs a small face-recognition model (\(FaceModel.sizeText)). It is downloaded once from the OpenCV Zoo project and everything then runs on this Mac.")
                    .sectionLabel().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Download model (\(FaceModel.sizeText))") { Task { await download() } }.buttonStyle(PillButtonStyle())
            }.padding(.vertical, 10)
        case .downloading(let p):
            VStack(spacing: 8) {
                ProgressView(value: p).frame(width: 240)
                Text("Downloading the face model… \(Int(p * 100))%").sectionLabel()
            }.padding(.vertical, 24)
        case .scanning(let done, let total, let faces):
            VStack(spacing: 8) {
                ProgressView(value: total == 0 ? 0 : Double(done) / Double(total)).frame(width: 240)
                Text(total == 0 ? "Starting…" : "Looking at file \(min(done + 1, total)) of \(total) — \(faces) face\(faces == 1 ? "" : "s") so far").sectionLabel()
            }.padding(.vertical, 24)
        case .failed(let m):
            Text(m).sectionLabel().foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).padding(.vertical, 10)
        case .ready:
            if clusters.isEmpty {
                Text("No faces found in the selection.").sectionLabel().padding(.vertical, 24)
            } else {
                Text("Pick the people to keep. Files where they appear are selected.").sectionLabel()
                ScrollView(.horizontal, showsIndicators: clusters.count > 6) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(104), spacing: 8), count: clusters.count > 7 ? 2 : 1), spacing: 14) {
                        ForEach(clusters) { c in face(c) }
                    }.padding(.horizontal, 6).padding(.vertical, 6)
                }.frame(height: clusters.count > 7 ? 230 : 120)
                HStack(spacing: 8) {
                    Text("Same person").sectionLabel()
                    Text("loose").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    Slider(value: $strictness, in: 0.38...0.65).controlSize(.small).frame(width: 150)
                        .onChange(of: strictness) { _ in regroup() }
                    Text("strict").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Text("\(files.count) of \(urls.count) files").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                Text("The same person can show up twice (angle, glasses): select both. If two people are mixed up, make it stricter.")
                    .sectionLabel().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Visage rond : sélectionné = bord blanc ; sinon estompé.
    private func face(_ c: FaceCluster) -> some View {
        let on = chosen.contains(c.id)
        return Button {
            if on { chosen.remove(c.id) } else { chosen.insert(c.id) }
        } label: {
            VStack(spacing: 5) {
                Image(decorative: c.thumb, scale: 1).resizable().scaledToFill().frame(width: 68, height: 68).clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: on ? 3.5 : 0))
                    .shadow(color: on ? Color.black.opacity(0.35) : .clear, radius: 2.5, y: 1)
                    .opacity(on ? 1 : 0.7)
                Text(c.files.count == 1 ? "1 file" : "\(c.files.count) files").font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.muted)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: Étapes

    private func begin() async {
        guard FaceModel.isInstalled else { phase = .needModel; return }
        await scan()
    }

    private func download() async {
        phase = .downloading(0)
        do {
            try await FaceModel.download { p in DispatchQueue.main.async { phase = .downloading(p) } }
            await scan()
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func scan() async {
        phase = .scanning(done: 0, total: urls.count, faces: 0)
        do {
            hits = try await FaceScanner.scan(urls) { d, t, f in DispatchQueue.main.async { if case .scanning = phase { phase = .scanning(done: d, total: t, faces: f) } } }
            clusters = FaceScanner.cluster(hits, threshold: Float(strictness))
            phase = .ready
        } catch is CancellationError {
            return
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func regroup() {
        clusters = FaceScanner.cluster(hits, threshold: Float(strictness))
        chosen = []
    }
}
