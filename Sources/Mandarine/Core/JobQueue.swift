import AppKit

/// File d'attente des travaux. Les travaux lourds (encodage, IA, téléchargement…) sont limités à `maxHeavy` en même temps
/// pour ne pas saturer le Mac ; les travaux légers démarrent tout de suite. Chaque travail a sa ligne dans la pile de notifications.
/// À utiliser depuis le thread principal.
final class JobQueue {
    static let shared = JobQueue()
    static let maxHeavy = 2

    typealias Work = (@escaping (Double) -> Void) async throws -> [URL]
    /// Variante qui peut aussi changer la ligne de détail pendant le travail (ex. « 3 / 27 — titre »).
    typealias StatusWork = (@escaping (Double) -> Void, @escaping (String) -> Void) async throws -> [URL]

    /// Un lot dont une partie seulement a réussi : les fichiers faits sont gardés, le reste est signalé (« Saved 8 of 10 — 2 failed »).
    struct Partial: Error { let outs: [URL]; let failed: Int; let total: Int; let message: String }

    private final class Entry {
        let id = UUID()
        let title: String, subtitle: String, heavy: Bool, count: Int, work: StatusWork
        var task: Task<Void, Never>?
        var started = false, cancelled = false
        init(title: String, subtitle: String, heavy: Bool, count: Int, work: @escaping StatusWork) {
            self.title = title; self.subtitle = subtitle; self.heavy = heavy; self.count = count; self.work = work
        }
    }

    private var entries: [Entry] = []
    var isIdle: Bool { entries.isEmpty }      // en attente et en cours, dans l'ordre d'arrivée

    @discardableResult
    func add(_ title: String, subtitle: String = "", light: Bool = false, count: Int = 1, work: @escaping Work) -> UUID {
        add(title, subtitle: subtitle, light: light, count: count, statusWork: { progress, _ in try await work(progress) })
    }

    @discardableResult
    /// `count` : nombre de fichiers du lot. Au-dessus de 1, la ligne affiche « x of n done » d'après la progression globale
    /// (le travail doit la calculer comme (fichiers faits + part du fichier en cours) / n).
    func add(_ title: String, subtitle: String = "", light: Bool = false, count: Int = 1, statusWork work: @escaping StatusWork) -> UUID {
        let e = Entry(title: title, subtitle: subtitle, heavy: !light, count: count, work: work)
        entries.append(e)
        Toast.shared.add(ToastItem(id: e.id, phase: .waiting, title: title, subtitle: "Waiting…", progress: nil, cancel: { [weak self] in self?.cancel(e.id) }))
        pump()
        return e.id
    }

    func cancel(_ id: UUID) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        e.cancelled = true
        e.task?.cancel()
        Toast.shared.remove(id)
        if !e.started { entries.removeAll { $0 === e } }      // un travail en cours se retire quand son processus s'arrête
        pump()
    }

    private func pump() {
        var heavyRunning = entries.filter { $0.started && $0.heavy }.count
        var ahead = 0
        for e in entries where !e.started {
            if e.heavy {
                if heavyRunning >= Self.maxHeavy {
                    ahead += 1
                    let n = heavyRunning + ahead - Self.maxHeavy
                    Toast.shared.update(e.id) { $0.subtitle = n <= 1 ? "Waiting — next in line" : "Waiting — \(n) jobs ahead" }
                    continue
                }
                heavyRunning += 1
            }
            start(e)
        }
    }

    private func start(_ e: Entry) {
        e.started = true
        let n = e.count
        Toast.shared.update(e.id) { $0.phase = .running; $0.subtitle = n > 1 ? "0 of \(n) done" : e.subtitle; $0.progress = n > 1 ? 0 : -1 }
        let id = e.id
        let queue = self
        e.task = Task {
            do {
                let outs = try await e.work({ p in
                    DispatchQueue.main.async {
                        Toast.shared.update(id) {
                            $0.progress = p
                            if n > 1, $0.phase == .running { $0.subtitle = "\(min(max(Int((p * Double(n)).rounded(.down)), 0), n - 1)) of \(n) done" }
                        }
                    }
                }, { text in
                    DispatchQueue.main.async { Toast.shared.update(id) { if $0.phase == .running { $0.subtitle = text } } }
                })
                await MainActor.run { queue.finish(e, .success(outs)) }
            } catch {
                await MainActor.run { queue.finish(e, .failure(error)) }
            }
        }
    }

    private func finish(_ e: Entry, _ result: Result<[URL], Error>) {
        entries.removeAll { $0 === e }
        defer { pump() }
        if e.cancelled { Toast.shared.remove(e.id); return }
        switch result {
        case .success(let outs):
            guard let first = outs.first else { Toast.shared.remove(e.id); return }
            let title = outs.count == 1 ? "Saved \(first.lastPathComponent)" : "Saved \(outs.count) items"
            Toast.shared.update(e.id) {
                $0.phase = .done; $0.title = title; $0.subtitle = first.deletingLastPathComponent().path
                $0.progress = nil; $0.reveal = outs; $0.cancel = nil
            }
            if AppSettings.shared.revealAfterSave { NSWorkspace.shared.activateFileViewerSelecting(outs) }
        case .failure(let error):
            if error is CancellationError { Toast.shared.remove(e.id); return }
            if let part = error as? Partial, let first = part.outs.first {
                Toast.shared.update(e.id) {
                    $0.phase = .done; $0.title = "Saved \(part.outs.count) of \(part.total) — \(part.failed) failed"
                    $0.subtitle = part.message; $0.detail = part.message; $0.progress = nil; $0.reveal = part.outs; $0.cancel = nil
                }
                if AppSettings.shared.revealAfterSave { NSWorkspace.shared.activateFileViewerSelecting(part.outs) }
                _ = first
                return
            }
            let msg = error.localizedDescription
            Toast.shared.update(e.id) {
                $0.phase = .failed; $0.title = e.title.replacingOccurrences(of: "…", with: "") + " failed"
                $0.subtitle = msg; $0.detail = msg; $0.progress = nil; $0.cancel = nil
            }
        }
    }
}
