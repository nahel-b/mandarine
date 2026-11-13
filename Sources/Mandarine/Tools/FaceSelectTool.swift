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
    @State private var rest: [FaceHit] = []                // visages inconnus (les numéros des groupes inconnus renvoient ici)
    @ObservedObject private var people = FacePeople.shared
    @State private var chosen: Set<Int> = []
    @State private var strictness: Double = 0.50          // similarité minimale pour regrouper deux visages

    private var files: [URL] {
        var seen = Set<URL>()
        return clusters.filter { chosen.contains($0.id) }.flatMap(\.files).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ToolShell(title: L("Face Select"), close: close) {
            VStack(spacing: 14) { content }.frame(width: 470)
        } footer: {
            if case .ready = phase {
                Button(files.count == 1 ? L("Select 1 file") : L("Select \(files.count) files")) {
                    let f = files, n = urls.count; close(); TagSelect.select(f, of: n)
                }.buttonStyle(PillButtonStyle()).disabled(files.isEmpty).keyboardShortcut(.defaultAction)
            }
        }
        .task { await begin() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .needModel:
            VStack(spacing: 10) {
                Image(systemName: "face.dashed").font(.system(size: 30)).foregroundStyle(Theme.muted)
                Text(L("Face Select needs a small face-recognition model (\(FaceModel.sizeText)). It is downloaded once from the OpenCV Zoo project and everything then runs on this Mac."))
                    .sectionLabel().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button(L("Download model (\(FaceModel.sizeText))")) { Task { await download() } }.buttonStyle(PillButtonStyle())
            }.padding(.vertical, 10)
        case .downloading(let p):
            VStack(spacing: 8) {
                ProgressView(value: p).frame(width: 240)
                Text(L("Downloading the face model… \(Int(p * 100))%")).sectionLabel()
            }.padding(.vertical, 24)
        case .scanning(let done, let total, let faces):
            VStack(spacing: 8) {
                ProgressView(value: total == 0 ? 0 : Double(done) / Double(total)).frame(width: 240)
                Text(total == 0 ? L("Starting…") : L("Looking at file \(min(done + 1, total)) of \(total) — \(faces) face\(faces == 1 ? "" : "s") so far")).sectionLabel()
            }.padding(.vertical, 24)
        case .failed(let m):
            Text(L(m)).sectionLabel().foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).padding(.vertical, 10)
        case .ready:
            if clusters.isEmpty {
                Text(L("No faces found in the selection.")).sectionLabel().padding(.vertical, 24)
            } else {
                Text(clusters.contains { $0.name != nil } ? L("Pick the people to keep. The ones you saved come first, with their name.") : L("Pick the people to keep. Files where they appear are selected.")).sectionLabel()
                ScrollView(.horizontal, showsIndicators: clusters.count > 6) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(104), spacing: 8), count: clusters.count > 7 ? 2 : 1), spacing: 14) {
                        ForEach(clusters) { c in face(c) }
                    }.padding(.horizontal, 6).padding(.vertical, 6)
                }.frame(height: clusters.count > 7 ? 230 : 120)
                HStack(spacing: 8) {
                    Text(L("Same person")).sectionLabel()
                    Text(L("loose")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                    Slider(value: $strictness, in: 0.38...0.65).controlSize(.small).frame(width: 150)
                        .onChange(of: strictness) { _ in regroup() }
                    Text(L("strict")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Text(L("\(files.count) of \(urls.count) files")).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                Text(L("The same person can show up twice (angle, glasses): select both. If two people are mixed up, make it stricter. Right-click a face to save it as a person."))
                    .sectionLabel().multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Visage rond : sélectionné = bord blanc et coche ; sinon estompé. Une personne enregistrée porte son nom.
    private func face(_ c: FaceCluster) -> some View {
        let on = chosen.contains(c.id)
        return Button {
            if on { chosen.remove(c.id) } else { chosen.insert(c.id) }
        } label: {
            VStack(spacing: 4) {
                Image(decorative: c.thumb, scale: 1).resizable().scaledToFill().frame(width: 68, height: 68).clipShape(Circle())
                    .overlay(Circle().stroke(c.name != nil ? Theme.orange : Color.white, lineWidth: on ? 3.5 : (c.name != nil ? 1.5 : 0)))
                    .overlay(alignment: .bottomTrailing) {
                        if on { Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, Theme.orange).background(Circle().fill(.white).padding(2)) }
                    }
                    .shadow(color: on ? Color.black.opacity(0.35) : .clear, radius: 2.5, y: 1)
                    .opacity(on ? 1 : 0.7)
                if let n = c.name { Text(n).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).frame(width: 84) }
                Text(c.files.count == 1 ? L("1 file") : L("\(c.files.count) files")).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.muted)
            }.contentShape(Rectangle())
        }.buttonStyle(WiiPlainButtonStyle())
        .contextMenu {
            if c.name == nil { Button(L("Save as a person…")) { save(c) } }
        }
    }

    /// Enregistre ce groupe de visages comme une personne (ses 5 visages les plus nets servent de référence).
    private func save(_ c: FaceCluster) {
        let alert = NSAlert()
        alert.messageText = L("Save as a person")
        alert.informativeText = L("Face Select will find this person first, with this name, in every selection. You can edit people in Settings → People.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = L("Name")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save")); alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let best = c.members.compactMap { rest.indices.contains($0) ? rest[$0] : nil }.sorted { $0.score > $1.score }
        FacePeople.shared.addPerson(name: name, samples: best)
        regroup()
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
            regroup()
            phase = .ready
        } catch is CancellationError {
            return
        } catch { phase = .failed(error.localizedDescription) }
    }

    /// Les personnes enregistrées d'abord (dans l'ordre des Réglages), puis les visages inconnus regroupés par ressemblance.
    private func regroup() {
        let known = FacePeople.shared.people
        let a = FacePeople.assign(hits, people: known, threshold: Float(AppSettings.shared.faceMatchThreshold))
        var named: [FaceCluster] = []
        for p in known {
            guard let idx = a.byPerson[p.id], !idx.isEmpty else { continue }
            var seen = Set<URL>()
            let files = idx.map { hits[$0].file }.filter { seen.insert($0).inserted }
            let thumb = p.samples.first?.image ?? hits[idx.max { hits[$0].score < hits[$1].score }!].thumb
            named.append(FaceCluster(id: 0, members: idx, centroid: [], files: files, thumb: thumb, name: p.name, personID: p.id))
        }
        rest = a.rest.map { hits[$0] }
        let others = FaceScanner.cluster(rest, threshold: Float(strictness))
        clusters = (named + others).enumerated().map { var c = $1; c.id = $0; return c }
        chosen = []
    }
}
