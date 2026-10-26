import SwiftUI
import AppKit

/// Étiquette Finder : nom + couleur (0 aucune, 1 gris, 2 vert, 3 violet, 4 bleu, 5 jaune, 6 rouge, 7 orange).
struct FinderTag: Hashable, Identifiable {
    let name: String
    let color: Int
    var id: String { name }
    var swiftUIColor: Color {
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

/// « Tag Select » : dans une sélection, ne garder que les fichiers qui ont une étiquette Finder (au choix quand il y en a plusieurs)
/// et les sélectionner dans le Finder.
enum TagSelect {
    private static let attribute = "com.apple.metadata:_kMDItemUserTags"

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

    static func start(_ urls: [URL]) {
        let groups = groups(urls)
        if groups.isEmpty {
            Toast.shared.done("No tagged files", subtitle: "None of the \(urls.count) selected files has a Finder tag.")
        } else if groups.count == 1 {
            select(groups[0].files, of: urls.count)          // une seule étiquette : rien à choisir
        } else {
            ToolWindowController.present { close in AnyView(TagSelectTool(total: urls.count, groups: groups, close: close)) }
        }
    }

    static func select(_ files: [URL], of total: Int) {
        NSWorkspace.shared.activateFileViewerSelecting(files)
        Toast.shared.done("Selected \(files.count) of \(total) files", subtitle: "in the Finder")
    }
}

struct TagSelectTool: View {
    let total: Int
    let groups: [TaggedGroup]
    let close: () -> Void
    @State private var chosen: Set<String>

    init(total: Int, groups: [TaggedGroup], close: @escaping () -> Void) {
        self.total = total; self.groups = groups; self.close = close
        _chosen = State(initialValue: Set(groups.map(\.id)))          // tout est pris au départ
    }

    private var files: [URL] {
        var seen = Set<URL>()
        return groups.filter { chosen.contains($0.id) }.flatMap(\.files).filter { seen.insert($0).inserted }
    }

    var body: some View {
        ToolShell(title: "Tag Select", close: close) {
            VStack(spacing: 14) {
                Text("Pick the tags to keep. Files carrying at least one of them are selected.").sectionLabel()
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(groups) { g in dot(g) }
                    }.padding(.horizontal, 6).padding(.vertical, 8)
                }
                Text("\(files.count) of \(total) files").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
            }.frame(width: min(max(CGFloat(groups.count) * 82 + 24, 330), 470))
        } footer: {
            Button(files.count == 1 ? "Select 1 file" : "Select \(files.count) files") {
                let f = files; close(); TagSelect.select(f, of: total)
            }.buttonStyle(PillButtonStyle()).disabled(files.isEmpty)
        }
    }

    /// Rond de couleur : sélectionné = bord blanc ; sinon estompé.
    private func dot(_ g: TaggedGroup) -> some View {
        let on = chosen.contains(g.id)
        return Button {
            if on { chosen.remove(g.id) } else { chosen.insert(g.id) }
        } label: {
            VStack(spacing: 6) {
                Circle().fill(g.tag.swiftUIColor).frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.white, lineWidth: on ? 3.5 : 0))
                    .overlay(Circle().stroke(Color.black.opacity(g.tag.color == 0 ? 0.25 : 0), lineWidth: 1))
                    .shadow(color: on ? Color.black.opacity(0.35) : .clear, radius: 2.5, y: 1)
                    .opacity(on ? 1 : 0.35)
                Text(g.tag.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).frame(width: 64)
                Text("\(g.files.count)").font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.muted)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(g.tag.name)
    }
}
