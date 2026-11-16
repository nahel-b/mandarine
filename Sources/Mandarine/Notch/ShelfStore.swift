import SwiftUI
import UniformTypeIdentifiers

/// Un élément gardé sur l'étagère, tel qu'il est enregistré sur le disque.
private struct ShelfEntry: Codable {
    var id: UUID
    var type: String          // « file », « link » ou « text »
    var value: String         // chemin, adresse ou texte
    var added: Date
    var pinned: Bool? = nil          // absent dans les anciens fichiers
}

/// L'étagère de l'encoche : ce qu'on y a déposé, gardé d'un lancement à l'autre.
/// Les fichiers ne sont pas copiés (on garde leur chemin) sauf ceux qui n'existent que le temps du glisser (miniature de capture d'écran,
/// image glissée d'une page, pièce jointe…) : ceux-là sont recopiés dans `~/Library/Application Support/Mandarine/Shelf`.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore(persist: true)

    @Published private(set) var items: [ShelfItem] = []
    /// Éléments à montrer sélectionnés quand l'étagère s'ouvre d'elle-même (le bouton « Afficher » d'une notification) ; `highlightToken` change à chaque demande.
    @Published private(set) var highlightToken = UUID()
    private(set) var highlightIDs: Set<UUID> = []
    /// ⌘A : change à chaque demande, les vues sélectionnent alors tout ce qu'elles montrent.
    @Published private(set) var selectAllToken = UUID()
    func selectAll() { selectAllToken = UUID() }
    private var entries: [ShelfEntry] = []
    private var watched: [(path: String, at: Date)] = []          // fichiers de l'étagère déposés sur la roue : leurs résultats reviennent ici
    private let persist: Bool

    nonisolated static var folder: URL { FaceModel.folder.deletingLastPathComponent().appendingPathComponent("Shelf", isDirectory: true) }
    nonisolated static var file: URL { FaceModel.folder.deletingLastPathComponent().appendingPathComponent("shelf.json") }

    /// `persist` faux + `sample` : un faux contenu pour les essais de design.
    init(persist: Bool, sample: ShelfState? = nil) {
        self.persist = persist
        if let st = sample { items = st == .empty ? [] : ShelfSample.items; return }
        if persist { load(); cleanStash() }
    }

    /// Supprime du dossier de l'étagère les copies que plus aucun élément n'utilise (au bout de trois jours : le temps qu'un travail lancé par la roue s'achève).
    private func cleanStash() {
        let fm = FileManager.default
        let used = Set(entries.filter { $0.type == "file" }.map { URL(fileURLWithPath: $0.value).deletingLastPathComponent().path })
        for d in (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where !used.contains(d.path) {
            if let m = try? d.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(m) > 3 * 86400 { try? fm.removeItem(at: d) }
        }
    }

    // MARK: Lecture / écriture

    private func load() {
        guard let data = try? Data(contentsOf: Self.file), let e = try? JSONDecoder().decode([ShelfEntry].self, from: data) else { return }
        entries = e
        items = e.compactMap(Self.item(from:))
    }

    private func save() {
        guard persist else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(entries) { try? d.write(to: Self.file, options: .atomic) }
    }

    // MARK: Ajouter

    /// Les nouveaux arrivent devant. Un élément déjà présent (même fichier, même lien) remonte au lieu d'être doublé.
    /// Les épinglés restent devant les autres.
    private func insert(_ e: ShelfEntry) {
        var e = e
        if let i = entries.firstIndex(where: { $0.type == e.type && $0.value == e.value }) { if entries[i].pinned == true { e.pinned = true }; entries.remove(at: i); items.remove(at: i) }
        guard let it = Self.item(from: e) else { return }
        let at = e.pinned == true ? 0 : entries.filter { $0.pinned == true }.count
        entries.insert(e, at: at); items.insert(it, at: at)
        save()
    }

    func add(file url: URL, pinned: Bool = false) { insert(ShelfEntry(id: UUID(), type: "file", value: url.path, added: Date(), pinned: pinned ? true : nil)) }
    func add(link url: URL, pinned: Bool = false) { insert(ShelfEntry(id: UUID(), type: "link", value: url.absoluteString, added: Date(), pinned: pinned ? true : nil)) }

    /// Depuis la roue : ajoute ces fichiers, dossiers ou liens (épinglés ou non) et ouvre l'étagère dessus.
    func add(urls: [URL], pinned: Bool) {
        for u in urls { if u.isFileURL { add(file: u, pinned: pinned) } else { add(link: u, pinned: pinned) } }
        highlightIDs = Set(items.prefix(urls.count).map(\.id)); highlightToken = UUID()
        if AppSettings.shared.shelfEnabled { ShelfPanelController.shared.present() }
    }

    /// Touche pressée sur l'étagère (Suppr, Échap, Espace) : les vues agissent sur leur sélection.
    @Published private(set) var keyToken = UUID()
    private(set) var keyKind = ""
    func key(_ kind: String) { keyKind = kind; keyToken = UUID() }

    /// Change la place d'éléments (glisser pour réordonner). `target` : rang visé dans la liste actuelle ; les épinglés restent devant.
    func move(_ ids: [UUID], to target: Int) {
        let moving = items.indices.filter { ids.contains(items[$0].id) }
        guard !moving.isEmpty else { return }
        let pinnedMoving = items[moving[0]].pinned
        let movedE = moving.map { entries[$0] }, movedI = moving.map { items[$0] }
        var at = target - moving.filter { $0 < target }.count
        for i in moving.reversed() { entries.remove(at: i); items.remove(at: i) }
        let pinnedLeft = entries.filter { $0.pinned == true }.count
        at = pinnedMoving ? min(max(0, at), pinnedLeft) : min(max(pinnedLeft, at), entries.count)
        entries.insert(contentsOf: movedE, at: at); items.insert(contentsOf: movedI, at: at)
        save()
    }

    func isPinned(_ id: UUID) -> Bool { items.first { $0.id == id }?.pinned ?? false }

    /// Épingle ou désépingle ; les épinglés remontent devant.
    func setPinned(_ ids: Set<UUID>, _ on: Bool) {
        for i in entries.indices where ids.contains(entries[i].id) { entries[i].pinned = on ? true : nil; items[i].pinned = on }
        let order = entries.indices.filter { entries[$0].pinned == true } + entries.indices.filter { entries[$0].pinned != true }
        entries = order.map { entries[$0] }; items = order.map { items[$0] }
        save()
    }
    func add(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), !t.contains(" "), !t.contains("\n") { add(link: u); return }
        insert(ShelfEntry(id: UUID(), type: "text", value: t, added: Date()))
    }

    /// Ce qui arrive d'un glisser-déposer : fichiers, liens, texte, images ou fichiers « promis » (miniature de capture, pièce jointe…).
    /// Un lien reste un lien : même quand le navigateur le présente comme un fichier « .webloc », c'est l'adresse qu'on garde.
    func add(providers: [NSItemProvider]) {
        for p in providers {
            if DragMonitor.debugLog { DragMonitor.log("SHELF drop types: \(p.registeredTypeIdentifiers)") }
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {          // couvre les adresses web ET les fichiers/dossiers (une adresse de fichier est une adresse)
                p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                    var url: URL?
                    if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) } else if let u = item as? URL { url = u } else if let s = item as? String { url = URL(string: s) }
                    if url == nil {          // second essai : l'objet URL que sait fabriquer le fournisseur
                        _ = p.loadObject(ofClass: URL.self) { u, _ in Task { @MainActor in self.dropped(url: u, provider: p) } }
                        return
                    }
                    if DragMonitor.debugLog { DragMonitor.log("SHELF drop url: \(url!) err=\(String(describing: error))") }
                    Task { @MainActor in self.dropped(url: url, provider: p) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var text: String?
                    if let s = item as? String { text = s } else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    Task { @MainActor in if let t = text { self.add(text: t) } }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.folder.identifier) {
                p.loadItem(forTypeIdentifier: UTType.folder.identifier, options: nil) { item, _ in          // un dossier : son adresse seulement
                    var url: URL?
                    if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) } else if let u = item as? URL { url = u }
                    Task { @MainActor in self.dropped(url: url, provider: p) }
                }
            } else {
                stage(p)
            }
        }
    }

    /// Une adresse reçue d'un glisser : web → lien ; raccourci Internet → son adresse ; fichier ou DOSSIER → on garde son chemin (rien n'est copié) ;
    /// seul un fichier qui n'existe que le temps du glisser est recopié.
    private func dropped(url: URL?, provider p: NSItemProvider) {
        guard var url = url else { if DragMonitor.debugLog { DragMonitor.log("SHELF drop: pas d'adresse") }; return }
        if !url.isFileURL { add(link: url); return }
        if let real = (url as NSURL).filePathURL { url = real }          // adresse « par référence » du Finder → vrai chemin
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue, !Self.isDocumentPackage(url) { add(file: url); return }          // dossier : jamais copié
        if let link = Self.linkInside(url) { add(link: link); return }          // « Lien.webloc » → l'adresse
        if exists, !ScreenshotStaging.isTemporary(url) { add(file: url) }
        else if ScreenshotStaging.isTemporary(url) || !exists { stage(p) }
    }

    nonisolated private static func isDocumentPackage(_ url: URL) -> Bool { false }

    /// L'adresse que contient un raccourci Internet (.webloc, .url), sinon nil.
    nonisolated static func linkInside(_ file: URL) -> URL? {
        switch file.pathExtension.lowercased() {
        case "webloc":
            guard let d = try? Data(contentsOf: file), let plist = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
                  let s = plist["URL"] as? String, let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return nil }
            return u
        case "url":
            guard let t = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            for line in t.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("url=") {
                if let u = URL(string: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)), ["http", "https"].contains(u.scheme?.lowercased() ?? "") { return u }
            }
            return nil
        default: return nil
        }
    }

    /// Recopie un fichier qui n'existe que pendant le glisser (image d'une page, miniature, pièce jointe) dans le dossier de l'étagère.
    private func stage(_ p: NSItemProvider) {
        let type = p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true || UTType($0)?.conforms(to: .data) == true } ?? UTType.data.identifier
        p.loadFileRepresentation(forTypeIdentifier: type) { tmp, _ in
            guard let tmp = tmp else { return }
            let dir = Self.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let name = p.suggestedName.map { $0.contains(".") ? $0 : $0 + "." + (UTType(type)?.preferredFilenameExtension ?? tmp.pathExtension) } ?? tmp.lastPathComponent
            let dest = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: tmp.path, isDirectory: &isDir), isDir.boolValue { return }          // jamais de copie de dossier
            do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try FileManager.default.copyItem(at: tmp, to: dest) } catch { return }
            Task { @MainActor in self.add(file: dest) }
        }
    }

    // MARK: Retirer

    /// `deleteStaged` : supprime aussi la copie qu'on avait recopiée (pas après un glisser vers la roue ou une app, qui lit encore le fichier).
    func remove(_ ids: Set<UUID>, deleteStaged: Bool = true) {
        for i in entries.indices.reversed() where ids.contains(entries[i].id) {
            if deleteStaged, entries[i].type == "file", entries[i].value.hasPrefix(Self.folder.path + "/") { try? FileManager.default.removeItem(at: URL(fileURLWithPath: entries[i].value).deletingLastPathComponent()) }
            entries.remove(at: i); items.remove(at: i)
        }
        save()
    }
    func remove(_ id: UUID) { remove([id]) }

    // MARK: Travaux lancés depuis l'étagère

    /// Ces fichiers viennent d'être déposés sur la roue : on retient ceux qui sont sur l'étagère.
    func watch(_ urls: [URL]) {
        let mine = Set(entries.filter { $0.type == "file" }.map(\.value))
        for u in urls where mine.contains(u.path) { watched.append((u.path, Date())) }
        watched = watched.filter { Date().timeIntervalSince($0.at) < 3600 }
    }

    /// Un travail s'est terminé : ce qu'il a produit à côté d'un fichier de l'étagère (même dossier, nom qui commence pareil) rejoint l'étagère.
    func adopt(_ outputs: [URL]) {
        guard !watched.isEmpty else { return }
        for out in outputs {
            let dir = out.deletingLastPathComponent().standardizedFileURL.path
            let stem = out.deletingPathExtension().lastPathComponent
            for w in watched where Date().timeIntervalSince(w.at) < 3600 {
                let src = URL(fileURLWithPath: w.path)
                if src.deletingLastPathComponent().standardizedFileURL.path == dir, out.path != src.path, stem.hasPrefix(src.deletingPathExtension().lastPathComponent) {
                    add(file: out); break
                }
            }
        }
    }

    /// Le bouton « Afficher » d'une notification : si ces fichiers sont sur l'étagère, on l'ouvre dessus au lieu d'aller dans le Finder.
    @discardableResult
    func presentIfOnShelf(_ urls: [URL]) -> Bool {
        guard AppSettings.shared.shelfEnabled else { return false }
        let paths = Set(urls.map(\.path))
        let ids = Set(items.compactMap { i -> UUID? in if case .file(let u)? = i.payload, paths.contains(u.path) { return i.id } else { return nil } })
        guard !ids.isEmpty else { return false }
        highlightIDs = ids; highlightToken = UUID()
        ShelfPanelController.shared.present()
        return true
    }

    /// Un fichier a été remplacé par son résultat (ou rendu) : les éléments de l'étagère qui le désignaient suivent, et leur détail (taille) est relu.
    func follow(_ moves: [(from: URL, to: URL)]) {
        var changed = false
        for (from, to) in moves where from.path != to.path {
            guard let i = entries.firstIndex(where: { $0.type == "file" && $0.value == from.path }) else { continue }
            if entries.contains(where: { $0.type == "file" && $0.value == to.path && $0.id != entries[i].id }) { entries.remove(at: i) }          // déjà là : on fusionne
            else { entries[i].value = to.path }
            changed = true
        }
        if !changed, moves.contains(where: { m in entries.contains { $0.type == "file" && ($0.value == m.from.path || $0.value == m.to.path) } }) { changed = true }          // même chemin : seule la taille change
        guard changed else { return }
        items = entries.compactMap(Self.item(from:))
        save()
    }

    // MARK: Entrée → élément

    private static func item(from e: ShelfEntry) -> ShelfItem? {
        let age = Self.age(e.added)
        switch e.type {
        case "file":
            let url = URL(fileURLWithPath: e.value)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let kind: ShelfKind
            switch FileKind.detect(url) {
            case .image: kind = .image
            case .video: kind = .video
            case .audio: kind = .audio
            case .pdf: kind = .pdf
            case .folder: kind = .folder
            default: kind = .other
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
            // un dossier n'est jamais copié ni parcouru en profondeur : on garde son chemin et on compte juste ce qu'il contient au premier niveau
            let detail: String
            if !exists { detail = L("Missing") }
            else if kind == .folder { let n = (try? FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }.count) ?? 0; detail = L("Folder · \(n) items") }
            else { detail = size.map { $0.humanSize } ?? "" }
            return ShelfItem(id: e.id, payload: .file(url), kind: kind, name: url.lastPathComponent, detail: detail, age: age, pinned: e.pinned == true)
        case "link":
            guard let u = URL(string: e.value) else { return nil }
            let host = (u.host ?? e.value).replacingOccurrences(of: "www.", with: "")
            let path = u.path.count > 1 ? u.path : ""
            return ShelfItem(id: e.id, payload: .link(u), kind: .link, name: host + path, detail: L("Link"), age: age, title: nil, pinned: e.pinned == true)
        default:
            let first = e.value.split(whereSeparator: \.isNewline).first.map(String.init) ?? e.value
            return ShelfItem(id: e.id, payload: .text(e.value), kind: .text, name: String(first.prefix(40)), detail: L("\(e.value.count) characters"), age: age, pinned: e.pinned == true)
        }
    }

    private static func age(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return L("now") }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86400 { return "\(s / 3600) h" }
        return "\(s / 86400) d"
    }
}
