import SwiftUI
import QuickLookThumbnailing

/// Aperçus des fichiers de l'étagère (image, première image d'une vidéo, page d'un PDF…), gardés en mémoire.
/// Les vues qui l'observent se redessinent quand un aperçu arrive ; en attendant (ou pour un autre type de fichier) elles gardent leur symbole.
@MainActor
final class ShelfThumbs: ObservableObject {
    static let shared = ShelfThumbs()
    @Published private(set) var version = 0
    private var cache: [String: NSImage] = [:]
    private var pending: Set<String> = []

    /// Ce genre d'élément peut-il avoir un aperçu ?
    static func wants(_ it: ShelfItem) -> URL? {
        guard case .file(let u)? = it.payload, it.kind != .folder else { return nil }          // un dossier garde son icône : on ne le lit pas
        return u
    }

    private func key(_ u: URL) -> String {
        let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return u.path + "@\(d)"
    }

    /// L'aperçu, s'il est prêt.
    func image(for it: ShelfItem) -> NSImage? { Self.wants(it).flatMap { cache[key($0)] } }

    /// Lance la fabrication de l'aperçu si besoin.
    func request(_ it: ShelfItem, side: CGFloat = 120) {
        guard let url = Self.wants(it) else { return }
        let k = key(url)
        guard cache[k] == nil, !pending.contains(k), FileManager.default.fileExists(atPath: url.path) else { return }
        pending.insert(k)
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            let img = rep?.nsImage
            Task { @MainActor in
                self.pending.remove(k)
                if let img = img { self.cache[k] = img; self.version += 1 }
            }
        }
    }
}

/// L'aperçu d'un élément (rien tant qu'il n'est pas prêt) : à poser sous un `if ShelfThumbs.shared.image(for:) != nil`.
struct ShelfThumb: View {
    let item: ShelfItem
    @ObservedObject private var thumbs = ShelfThumbs.shared
    var body: some View {
        if let img = thumbs.image(for: item) { Image(nsImage: img).resizable().scaledToFill() }
    }
}
