import SwiftUI
import UniformTypeIdentifiers

/// Un visage à départager : la photo en contient plusieurs et il faut dire lequel est la personne.
struct FaceChoice: Identifiable {
    let id = UUID()
    let person: UUID
    let personName: String
    let file: URL
    let hits: [FaceHit]
}

/// Réglages → Personnes : créer des personnes, leur ajouter des photos, les supprimer. Face Select les reconnaît ensuite et les place en tête.
struct PeopleSettings: View {
    @ObservedObject private var people = FacePeople.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var installer = EngineInstaller.shared
    @State private var working: Set<UUID> = []
    @State private var queue: [FaceChoice] = []            // photos à départager, en attente
    @State private var current: FaceChoice?                 // celle qu'on montre
    @State private var notes: [String] = []

    var body: some View {
        Group {
            Section(L("People")) {
                Text(L("Save people here, with a few photos of each. In Face Select, they are recognized among your photos and shown first, with their name."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !FaceModel.isInstalled { modelRow }
                ForEach(people.people) { p in
                    PersonRow(person: p, busy: working.contains(p.id), addPhotos: { addPhotos($0, to: p) })
                }
                HStack {
                    Button(L("Add a person")) { people.addPerson(name: "") }.disabled(!FaceModel.isInstalled)
                    Spacer()
                    if people.people.isEmpty { Text(L("No one yet.")).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
            Section(L("Recognition")) {
                HStack(spacing: 8) {
                    Text(L("Same person"))
                    Text(L("loose")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settings.faceMatchThreshold, in: 0.38...0.65)
                    Text(L("strict")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Looser finds more photos of a person but may include look-alikes; stricter avoids mistakes but may miss some. The default suits most photos."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(L("Only a small numeric fingerprint of each face and a tiny thumbnail are kept, on this Mac. Your photos are not copied."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $current) { choice in
            ChooseFaceSheet(choice: choice) { hit in
                if let hit = hit { people.add(hit, to: choice.person) }
                current = nil
            }
        }
        .onChange(of: current?.id) { _ in nextChoice() }          // la fenêtre se ferme (choix ou Échap) : photo suivante
    }

    private func nextChoice() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
    }

    /// Le modèle de visages n'est pas encore là : le télécharger.
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("People need the face model (\(FaceModel.sizeText)), downloaded once. Everything then runs on this Mac."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch installer.state(.faceModel) {
            case .working(let p): ProgressView(value: p)
            case .failed(let m): Text(L(m)).font(.caption).foregroundStyle(.red)
            default: EmptyView()
            }
            if !installer.isWorking(.faceModel) { Button(L("Download model (\(FaceModel.sizeText))")) { installer.install(.faceModel) } }
        }
    }

    /// Cherche le visage dans chaque photo : un seul visage → ajouté ; plusieurs → on demande lequel ; aucun → signalé.
    private func addPhotos(_ urls: [URL], to person: KnownPerson) {
        guard FaceModel.isInstalled, !urls.isEmpty else { return }
        working.insert(person.id)
        Task {
            var none = 0, failed = 0
            for u in urls {
                do {
                    let hits = try await FacePeople.detect(in: u)
                    if hits.isEmpty { none += 1 }
                    else if hits.count == 1 { people.add(hits[0], to: person.id) }
                    else { queue.append(FaceChoice(person: person.id, personName: person.name, file: u, hits: hits)); nextChoice() }
                } catch { failed += 1 }
            }
            working.remove(person.id)
            if none > 0 { notes.append(none == 1 ? L("No face was found in 1 photo.") : L("No face was found in \(none) photos.")) }
            if failed > 0 { notes.append(L("\(failed) photo(s) couldn't be read.")) }
        }
    }
}

/// Une personne : nom modifiable, ses visages de référence (supprimables), ajout de photos (bouton ou glisser-déposer), suppression.
private struct PersonRow: View {
    let person: KnownPerson
    let busy: Bool
    let addPhotos: ([URL]) -> Void
    @ObservedObject private var people = FacePeople.shared
    @State private var name: String
    @State private var targeted = false

    init(person: KnownPerson, busy: Bool, addPhotos: @escaping ([URL]) -> Void) {
        self.person = person; self.busy = busy; self.addPhotos = addPhotos
        _name = State(initialValue: person.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: $name, prompt: Text(L("Name"))).labelsHidden().textFieldStyle(.roundedBorder)
                    .onChange(of: name) { people.rename(person.id, to: $0) }
                if busy { ProgressView().controlSize(.small) }
                Button(L("Add photos…")) { pick() }.controlSize(.small)
                Button(role: .destructive) { confirmDelete() } label: { Image(systemName: "trash") }.controlSize(.small).help(L("Delete this person"))
            }
            if person.samples.isEmpty {
                Text(L("Drop photos of this person here, or use “Add photos…”.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(person.samples) { s in
                            ZStack(alignment: .topTrailing) {
                                if let img = s.image { Image(decorative: img, scale: 1).resizable().scaledToFill().frame(width: 46, height: 46).clipShape(Circle()) }
                                Button { people.removeSample(s.id, of: person.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .gray)
                                }.buttonStyle(.plain).help(L("Remove this photo"))
                            }
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [5] : [])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for p in providers {
                    if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier), let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { urls.append(u) }
                }
                addPhotos(urls)
            }
            return true
        }
    }

    private func pick() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.allowedContentTypes = [.image]
        p.message = L("Choose photos of \(person.name.isEmpty ? L("this person") : person.name)")
        if p.runModal() == .OK { addPhotos(p.urls) }
    }

    private func confirmDelete() {
        let a = NSAlert()
        a.messageText = L("Delete \(person.name.isEmpty ? L("this person") : person.name)?")
        a.informativeText = L("Their saved faces are removed. Your photos are not touched.")
        a.addButton(withTitle: L("Delete")); a.addButton(withTitle: L("Cancel"))
        a.buttons.first?.hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { people.remove(person.id) }
    }
}

/// La photo contient plusieurs visages : on touche celui de la personne.
private struct ChooseFaceSheet: View {
    let choice: FaceChoice
    let done: (FaceHit?) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(L("Which one is \(choice.personName.isEmpty ? L("this person") : choice.personName)?")).font(.headline)
            Text(choice.file.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(choice.hits.enumerated()), id: \.offset) { _, h in
                        Button { done(h) } label: {
                            Image(decorative: h.thumb, scale: 1).resizable().scaledToFill().frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }.padding(4)
            }
            Button(L("Skip this photo")) { done(nil) }
        }
        .padding(20).frame(width: 420)
    }
}
