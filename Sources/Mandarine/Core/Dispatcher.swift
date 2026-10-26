import AppKit

/// Exécute ce qui a été déposé sur un segment de la roue.
enum Dispatcher {
    static func run(_ item: WheelItem, on urls: [URL]) {
        switch item.payload {
        case .convert(let ext): convert(urls, to: ext)
        case .tool(.tagSelect): TagSelect.start(urls)          // pas de fenêtre vide : elle ne s'ouvre que s'il y a un choix
        case .tool(let id): ToolWindowController.present(id, urls: urls)
        case .action(let a): FileActions.perform(a, on: urls)
        }
    }

    static func convert(_ urls: [URL], to ext: String) {
        let title = "Converting to \(ext.uppercased())…"
        if urls.count > 1, FileKind.common(of: urls) == .image, Catalog.normalized(ext) == "pdf" {      // plusieurs images → un seul PDF
            JobQueue.shared.add(title, subtitle: "\(urls.count) images") { progress in
                try await Converter.run(urls: urls, to: ext, progress: progress)
            }
            return
        }
        for u in urls {      // sinon : un travail par fichier, la file gère la simultanéité
            JobQueue.shared.add(title, subtitle: u.lastPathComponent) { progress in
                try await Converter.run(urls: [u], to: ext, progress: progress)
            }
        }
    }

    /// Met un travail dans la file (voir JobQueue). `light` : travail court, qui ne compte pas dans la limite de travaux lourds.
    static func job(_ title: String, subtitle: String = "", light: Bool = false, _ work: @escaping JobQueue.Work) {
        JobQueue.shared.add(title, subtitle: subtitle, light: light, work: work)
    }
}
