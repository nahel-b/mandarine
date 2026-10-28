import SwiftUI
import AppKit

/// Étiquette Finder : nom + couleur (0 aucune, 1 gris, 2 vert, 3 violet, 4 bleu, 5 jaune, 6 rouge, 7 orange).
struct FinderTag: Hashable, Identifiable {
    let name: String
    let color: Int
    var id: String { name }
    var swiftUIColor: Color {
        let colors = NSWorkspace.shared.fileLabelColors
        if (1..<colors.count).contains(color) { return Color(nsColor: colors[color]) }        // couleurs mêmes du Finder
        switch color {
        case 1: return Color(red: 0.60, green: 0.60, blue: 0.62)
        case 2: return Color(red: 0.35, green: 0.78, blue: 0.36)
        case 3: return Color(red: 0.69, green: 0.45, blue: 0.86)
        case 4: return Color(red: 0.28, green: 0.56, blue: 0.98)
        case 5: return Color(red: 1.00, green: 0.80, blue: 0.25)
        case 6: return Color(red: 1.00, green: 0.32, blue: 0.30)
        case 7: return Color(red: 1.00, green: 0.60, blue: 0.22)
        default: return Color(white: 0.82)
        }
    }
}

struct TaggedGroup: Identifiable {
    let tag: FinderTag
    var files: [URL]
    var id: String { tag.id }
}

/// Étiquettes Finder : lecture (nom + couleur) et sélection de fichiers dans le Finder.
enum TagSelect {
    static let attribute = "com.apple.metadata:_kMDItemUserTags"

    /// Étiquettes d'un fichier (le Finder les range dans un attribut étendu : « Nom\\nN » avec N = couleur).
    static func tags(of url: URL) -> [FinderTag] {
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, 0) }
        guard read > 0, let list = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String] else { return [] }
        return list.map { entry in
            let parts = entry.components(separatedBy: "\n")
            return FinderTag(name: parts[0], color: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        }
    }

    /// Étiquettes présentes dans la sélection, dans l'ordre d'apparition, avec leurs fichiers.
    static func groups(_ urls: [URL]) -> [TaggedGroup] {
        var order: [String] = [], byName: [String: TaggedGroup] = [:]
        for u in urls {
            for t in tags(of: u) {
                if byName[t.name] == nil { byName[t.name] = TaggedGroup(tag: t, files: []); order.append(t.name) }
                byName[t.name]?.files.append(u)
            }
        }
        return order.compactMap { byName[$0] }
    }

    static func select(_ files: [URL], of total: Int) {
        NSWorkspace.shared.activateFileViewerSelecting(files)
        Toast.shared.done("Selected \(files.count) of \(total) files", subtitle: "in the Finder")
    }
}

/// Écriture d'étiquettes Finder (couleurs 1 gris, 2 vert, 3 violet, 4 bleu, 5 jaune, 6 rouge, 7 orange ; noms localisés par le système).
enum FinderTags {
    static func labelName(_ index: Int) -> String { NSWorkspace.shared.fileLabels.indices.contains(index) ? NSWorkspace.shared.fileLabels[index] : "" }

    static func write(_ tags: [FinderTag], to url: URL) {
        let path = url.path
        if tags.isEmpty { removexattr(path, TagSelect.attribute, 0); return }
        let entries = tags.map { $0.color > 0 ? "\($0.name)\n\($0.color)" : $0.name }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0) else { return }
        _ = data.withUnsafeBytes { setxattr(path, TagSelect.attribute, $0.baseAddress, data.count, 0, 0) }
    }

    /// Pose l'étiquette de couleur `labelIndex` (ou aucune), en retirant les autres étiquettes de `managed` et en gardant toutes les autres.
    static func set(_ url: URL, label labelIndex: Int?, managed: [Int]) {
        let managedNames = Set(managed.map(labelName))
        var tags = TagSelect.tags(of: url).filter { !managedNames.contains($0.name) }
        if let i = labelIndex { tags.append(FinderTag(name: labelName(i), color: i)) }
        write(tags, to: url)
    }
}
