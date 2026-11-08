import SwiftUI

/// Un dossier de l'arborescence DaVinci (modifiable dans les Réglages). `on` = coché par défaut ; `receives` = type de fichier déposé qui y est rangé.
struct DaVinciFolder: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var on: Bool = true
    var receives: String? = nil          // "video" | "audio" | "image"
    var children: [DaVinciFolder] = []

    /// Nom utilisable comme nom de dossier (sans / ni :, espaces rognés).
    var cleanName: String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Arborescence de projet pour DaVinci Resolve.
enum DaVinciLayout {
    static let defaults: [DaVinciFolder] = [
        .init(id: "footage", name: "01_Footage", receives: "video", children: [.init(id: "aroll", name: "A-Roll"), .init(id: "broll", name: "B-Roll"), .init(id: "drone", name: "Drone"), .init(id: "screen", name: "Screen Recordings")]),
        .init(id: "audio", name: "02_Audio", receives: "audio", children: [.init(id: "music", name: "Music"), .init(id: "sfx", name: "SFX"), .init(id: "voice", name: "Voiceover")]),
        .init(id: "graphics", name: "03_Graphics", children: [.init(id: "titles", name: "Titles"), .init(id: "logos", name: "Logos"), .init(id: "stills", name: "Stills", receives: "image")]),
        .init(id: "project", name: "04_Project", children: [.init(id: "resolve", name: "Resolve Project"), .init(id: "timelines", name: "Timelines"), .init(id: "notes", name: "Notes")]),
        .init(id: "luts", name: "05_LUTs"),
        .init(id: "cache", name: "06_Cache", children: [.init(id: "proxies", name: "Proxies"), .init(id: "rendercache", name: "Render Cache")]),
        .init(id: "exports", name: "07_Exports", children: [.init(id: "review", name: "Review"), .init(id: "final", name: "Final")])
    ]

    static let maxDepth = 3

    /// Crée les dossiers cochés dans `root` ; retourne le nombre de dossiers créés. Ne touche jamais à l'existant.
    @discardableResult
    static func create(_ list: [DaVinciFolder], in root: URL) throws -> Int {
        let fm = FileManager.default
        var n = 0
        for f in list where f.on && !f.cleanName.isEmpty {
            let u = root.appendingPathComponent(f.cleanName, isDirectory: true)
            if !fm.fileExists(atPath: u.path) { try fm.createDirectory(at: u, withIntermediateDirectories: true); n += 1 }
            n += try create(f.children, in: u)
        }
        return n
    }

    /// Où ranger un fichier déposé : le premier dossier coché qui reçoit ce type (vidéo, son, image).
    static func destination(for file: URL, in root: URL, chosen: [DaVinciFolder]) -> URL? {
        let role: String
        switch FileKind.detect(file) {
        case .video: role = "video"
        case .audio: role = "audio"
        case .image: role = "image"
        default: return nil
        }
        func find(_ list: [DaVinciFolder], _ base: URL) -> URL? {
            for f in list where f.on && !f.cleanName.isEmpty {
                let u = base.appendingPathComponent(f.cleanName, isDirectory: true)
                if f.receives == role { return u }
                if let r = find(f.children, u) { return r }
            }
            return nil
        }
        return find(chosen, root)
    }

    /// Aperçu en arbre (├── └──) des dossiers cochés.
    static func treeText(_ list: [DaVinciFolder], prefix: String = "") -> String {
        let on = list.filter { $0.on && !$0.cleanName.isEmpty }
        var s = ""
        for (i, f) in on.enumerated() {
            let last = i == on.count - 1
            s += prefix + (last ? "└── " : "├── ") + f.cleanName + "\n"
            s += treeText(f.children, prefix: prefix + (last ? "    " : "│   "))
        }
        return s
    }

    /// Déplace l'élément d'identifiant `id` d'un cran (-1 vers le haut, +1 vers le bas).
    static func move(_ list: inout [DaVinciFolder], id: String, by d: Int) {
        guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + d) else { return }
        list.swapAt(i, i + d)
    }

    static func load() -> [DaVinciFolder] {
        guard let data = UserDefaults.standard.data(forKey: "davinciFolders"),
              let list = try? JSONDecoder().decode([DaVinciFolder].self, from: data) else { return defaults }
        return list
    }
    static func save(_ list: [DaVinciFolder]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: "davinciFolders") }
    }
}

/// Une case par dossier (et ses sous-dossiers), pour choisir quoi créer dans la fenêtre de l'outil.
private struct DaVinciPickRow: View {
    @Binding var folder: DaVinciFolder
    let depth: Int
    let parentOn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: $folder.on) { Text(verbatim: folder.cleanName).font(.system(size: 12, weight: depth == 0 ? .medium : .regular).monospaced()) }
                .padding(.leading, CGFloat(depth) * 16).disabled(!parentOn).opacity(parentOn ? 1 : 0.45)
            ForEach($folder.children) { $c in
                DaVinciPickRow(folder: $c, depth: depth + 1, parentOn: parentOn && folder.on)
            }
        }
    }
}

struct DaVinciTreeTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var groups = AppSettings.shared.davinciFolders
    @State private var name = ""
    @State private var moveFiles = AppSettings.shared.davinciMoveFiles

    private var folders: [URL] { urls.filter { FileKind.detect($0) == .folder } }
    private var files: [URL] { urls.filter { FileKind.detect($0) != .folder } }
    private var root: URL {
        if let f = folders.first { return f }
        let parent = urls[0].deletingLastPathComponent()
        return parent.appendingPathComponent(safeName, isDirectory: true)
    }
    private var creatingWrapper: Bool { folders.isEmpty }
    private var defaultName: String { AppSettings.shared.davinciProjectName.isEmpty ? "DaVinci Project" : AppSettings.shared.davinciProjectName }
    private var safeName: String {
        let n = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? defaultName : n
    }

    var body: some View {
        ToolShell(title: L("DaVinci Project"), close: close) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 22)).foregroundStyle(Theme.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(creatingWrapper ? L("A new project folder will be created next to your files") : L("The folders are created inside")).font(.system(size: 12, weight: .semibold))
                        Text(L(root.path)).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                if creatingWrapper {
                    HStack { Text(L("Project name")).sectionLabel(); TextField(defaultName, text: $name).textFieldStyle(.roundedBorder) }
                }
                Divider()
                HStack(alignment: .top, spacing: 14) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach($groups) { $g in DaVinciPickRow(folder: $g, depth: 0, parentOn: true) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                    }.frame(width: 200, height: 200)
                    ScrollView {
                        Text(verbatim: treeText).font(.system(size: 11).monospaced()).foregroundStyle(Theme.text.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10).frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.05)))
                }
                if !files.isEmpty {
                    Toggle(L("Move the dropped files into the right folder (videos, sounds, images)"), isOn: $moveFiles).font(.system(size: 12))
                }
            }.frame(width: 500, alignment: .leading)
        } footer: {
            Button(L("Create Folders")) { run() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(!groups.contains { $0.on && !$0.cleanName.isEmpty }).keyboardShortcut(.defaultAction)
        }
        .onAppear { name = urls.count == 1 && AppSettings.shared.davinciNameFromFile ? urls[0].deletingPathExtension().lastPathComponent : defaultName }
    }

    private var treeText: String {
        (creatingWrapper ? safeName : root.lastPathComponent) + "/\n" + DaVinciLayout.treeText(groups)
    }

    private func run() {
        let chosen = groups, target = root, dropped = files, move = moveFiles, wrapper = creatingWrapper
        close()
        Dispatcher.job(L("Creating DaVinci folders…"), light: true) { _ in
            try await Task.detached {
                let fm = FileManager.default
                if wrapper { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
                let n = try DaVinciLayout.create(chosen, in: target)
                var moved = 0
                if move {
                    for f in dropped {
                        guard let dest = DaVinciLayout.destination(for: f, in: target, chosen: chosen) else { continue }
                        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                        let out = OutputNaming.unique(folder: dest, base: f.deletingPathExtension().lastPathComponent, ext: f.pathExtension)
                        try fm.moveItem(at: f, to: out); moved += 1
                    }
                }
                _ = (n, moved)
                return [target]
            }.value
        }
    }
}
