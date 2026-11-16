import SwiftUI
import UniformTypeIdentifiers

/// Un élément gardé sur l'étagère, tel qu'il est enregistré sur le disque.
private struct ShelfEntry: Codable {
    var id: UUID
    var type: String          // « file », « link » ou « text »
    var value: String         // chemin, adresse ou texte
    var added: Date
}

/// L'étagère de l'encoche : ce qu'on y a déposé, gardé d'un lancement à l'autre.
/// Les fichiers ne sont pas copiés (on garde leur chemin) sauf ceux qui n'existent que le temps du glisser (miniature de capture d'écran,
/// image glissée d'une page, pièce jointe…) : ceux-là sont recopiés dans `~/Library/Application Support/Mandarine/Shelf`.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore(persist: true)

    @Published private(set) var items: [ShelfItem] = []
    private var entries: [ShelfEntry] = []
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
    private func insert(_ e: ShelfEntry) {
        if let i = entries.firstIndex(where: { $0.type == e.type && $0.value == e.value }) { entries.remove(at: i); items.remove(at: i) }
        guard let it = Self.item(from: e) else { return }
        entries.insert(e, at: 0); items.insert(it, at: 0)
        save()
    }

    func add(file url: URL) { insert(ShelfEntry(id: UUID(), type: "file", value: url.path, added: Date())) }
    func add(link url: URL) { insert(ShelfEntry(id: UUID(), type: "link", value: url.absoluteString, added: Date())) }
    func add(text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), !t.contains(" "), !t.contains("\n") { add(link: u); return }
        insert(ShelfEntry(id: UUID(), type: "text", value: t, added: Date()))
    }

    /// Ce qui arrive d'un glisser-déposer : fichiers, liens, texte, images ou fichiers « promis » (miniature de capture, pièce jointe…).
    func add(providers: [NSItemProvider]) {
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) } else if let u = item as? URL { url = u }
                    Task { @MainActor in
                        guard let url = url else { return }
                        if ScreenshotStaging.isTemporary(url) || !FileManager.default.isReadableFile(atPath: url.path) { self.stage(p) } else { self.add(file: url) }
                    }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) } else if let u = item as? URL { url = u }
                    Task { @MainActor in if let u = url { self.add(link: u) } }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    var text: String?
                    if let s = item as? String { text = s } else if let d = item as? Data { text = String(data: d, encoding: .utf8) }
                    Task { @MainActor in if let t = text { self.add(text: t) } }
                }
            } else {
                stage(p)
            }
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

    /// Un fichier a été remplacé par son résultat (ou rendu) : les éléments de l'étagère qui le désignaient suivent, et leur détail (taille) est relu.
    func follow(_ moves: [(from: URL, to: URL)]) {
        var changed = false
        for (from, to) in moves {
            for i in entries.indices where entries[i].type == "file" && (entries[i].value == from.path || entries[i].value == to.path) {
                if entries[i].value == from.path { entries[i].value = to.path }
                changed = true
            }
        }
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
            default: kind = .other
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
            let detail = !exists ? L("Missing") : (FileKind.detect(url) == .folder ? L("Folder") : (size.map { $0.humanSize } ?? ""))
            return ShelfItem(id: e.id, payload: .file(url), kind: kind, name: url.lastPathComponent, detail: detail, age: age)
        case "link":
            guard let u = URL(string: e.value) else { return nil }
            let host = (u.host ?? e.value).replacingOccurrences(of: "www.", with: "")
            let path = u.path.count > 1 ? u.path : ""
            return ShelfItem(id: e.id, payload: .link(u), kind: .link, name: host + path, detail: L("Link"), age: age, title: nil)
        default:
            let first = e.value.split(whereSeparator: \.isNewline).first.map(String.init) ?? e.value
            return ShelfItem(id: e.id, payload: .text(e.value), kind: .text, name: String(first.prefix(40)), detail: L("\(e.value.count) characters"), age: age)
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
