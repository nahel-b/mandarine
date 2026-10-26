import SwiftUI

/// Arborescence de projet pour DaVinci Resolve.
enum DaVinciLayout {
    struct Group: Identifiable { let id: String; let name: String; let children: [String]; var on = true }

    static let groups: [Group] = [
        .init(id: "footage", name: "01_Footage", children: ["A-Roll", "B-Roll", "Drone", "Screen Recordings"]),
        .init(id: "audio", name: "02_Audio", children: ["Music", "SFX", "Voiceover"]),
        .init(id: "graphics", name: "03_Graphics", children: ["Titles", "Logos", "Stills"]),
        .init(id: "project", name: "04_Project", children: ["Resolve Project", "Timelines", "Notes"]),
        .init(id: "luts", name: "05_LUTs", children: []),
        .init(id: "cache", name: "06_Cache", children: ["Proxies", "Render Cache"]),
        .init(id: "exports", name: "07_Exports", children: ["Review", "Final"])
    ]

    /// Crée les dossiers choisis dans `root` ; retourne le nombre de dossiers créés. Ne touche jamais à l'existant.
    @discardableResult
    static func create(_ chosen: [Group], in root: URL) throws -> Int {
        let fm = FileManager.default
        var n = 0
        func make(_ u: URL) throws { if !fm.fileExists(atPath: u.path) { try fm.createDirectory(at: u, withIntermediateDirectories: true); n += 1 } }
        for g in chosen {
            let top = root.appendingPathComponent(g.name, isDirectory: true)
            try make(top)
            for c in g.children { try make(top.appendingPathComponent(c, isDirectory: true)) }
        }
        return n
    }

    /// Où ranger un fichier déposé : vidéo → 01_Footage, audio → 02_Audio, image → 03_Graphics/Stills.
    static func destination(for file: URL, in root: URL, chosen: [Group]) -> URL? {
        func has(_ id: String) -> Bool { chosen.contains { $0.id == id } }
        switch FileKind.detect(file) {
        case .video: return has("footage") ? root.appendingPathComponent("01_Footage") : nil
        case .audio: return has("audio") ? root.appendingPathComponent("02_Audio") : nil
        case .image: return has("graphics") ? root.appendingPathComponent("03_Graphics/Stills") : nil
        default: return nil
        }
    }
}

struct DaVinciTreeTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var groups = DaVinciLayout.groups
    @State private var name = ""
    @State private var moveFiles = true

    private var folders: [URL] { urls.filter { FileKind.detect($0) == .folder } }
    private var files: [URL] { urls.filter { FileKind.detect($0) != .folder } }
    private var root: URL {
        if let f = folders.first { return f }
        let parent = urls[0].deletingLastPathComponent()
        return parent.appendingPathComponent(name.isEmpty ? "DaVinci Project" : name, isDirectory: true)
    }
    private var creatingWrapper: Bool { folders.isEmpty }

    var body: some View {
        ToolShell(title: "DaVinci Project", close: close) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape").font(.system(size: 22)).foregroundStyle(Theme.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(creatingWrapper ? "A new project folder will be created next to your files" : "The folders are created inside").font(.system(size: 12, weight: .semibold))
                        Text(root.path).font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                if creatingWrapper {
                    HStack { Text("Project name").sectionLabel(); TextField("DaVinci Project", text: $name).textFieldStyle(.roundedBorder) }
                }
                Divider()
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach($groups) { $g in
                            Toggle(isOn: $g.on) { Text(g.name).font(.system(size: 12, weight: .medium).monospaced()) }
                        }
                    }.frame(width: 150, alignment: .leading)
                    ScrollView {
                        Text(treeText).font(.system(size: 11).monospaced()).foregroundStyle(Theme.text.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10).frame(height: 200)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.05)))
                }
                if !files.isEmpty {
                    Toggle("Move the dropped files into the right folder (video → Footage, audio → Audio, images → Stills)", isOn: $moveFiles).font(.system(size: 12))
                }
            }.frame(width: 470, alignment: .leading)
        } footer: {
            Button("Create Folders") { run() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(!groups.contains { $0.on })
        }
        .onAppear { name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "DaVinci Project" }
    }

    private var treeText: String {
        var s = (creatingWrapper ? (name.isEmpty ? "DaVinci Project" : name) : root.lastPathComponent) + "/\n"
        let on = groups.filter(\.on)
        for (i, g) in on.enumerated() {
            let last = i == on.count - 1
            s += (last ? "└── " : "├── ") + g.name + "\n"
            for (j, c) in g.children.enumerated() {
                s += (last ? "    " : "│   ") + (j == g.children.count - 1 ? "└── " : "├── ") + c + "\n"
            }
        }
        return s
    }

    private func run() {
        let chosen = groups.filter(\.on), target = root, dropped = files, move = moveFiles, wrapper = creatingWrapper
        close()
        Dispatcher.job("Creating DaVinci folders…", light: true) { _ in
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
