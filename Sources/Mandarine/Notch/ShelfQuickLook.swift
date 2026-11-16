import AppKit
import Quartz

/// Espace sur l'étagère : l'aperçu Quick Look des fichiers (un deuxième Espace le ferme).
@MainActor
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = ShelfQuickLook()
    private var urls: [URL] = []

    static func toggle(_ items: [ShelfItem]) {
        let files = items.compactMap { i -> URL? in if case .file(let u) = i.payload, FileManager.default.fileExists(atPath: u.path) { return u } else { return nil } }
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        guard !files.isEmpty else { return }
        shared.urls = files
        panel.dataSource = shared
        panel.reloadData()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { MainActor.assumeIsolated { urls.count } }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { MainActor.assumeIsolated { urls[index] as NSURL } }
}
