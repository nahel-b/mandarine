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
        var startedAt = Date()
        var samples: [(t: Double, p: Double)] = []      // progression relevée au fil du temps, pour estimer ce qui reste
        var eta = ""
        var replaces: [URL] = []                 // fichiers d'origine que ce travail peut remplacer (un résultat par original, dans le même ordre)
        var replaceNow = false                   // le remplacement a été demandé (réglage inversé par la touche) au moment de lancer le travail
        var etaLeft: Double?, etaAt = 0.0          // secondes restantes lissées, et l'instant (depuis le début) où elles ont été calculées
        init(title: String, subtitle: String, heavy: Bool, count: Int, work: @escaping StatusWork) {
            self.title = title; self.subtitle = subtitle; self.heavy = heavy; self.count = count; self.work = work
        }
    }

    /// Temps restant brut (en secondes) d'un travail long, d'après sa vitesse des dernières secondes (ou depuis le début s'il est trop récent).
    /// nil tant que l'estimation serait peu fiable (début du travail, aucune vitesse mesurable).
    static func etaSeconds(samples: [(t: Double, p: Double)]) -> Double? {
        guard let first = samples.first, let last = samples.last, last.p > 0.02, last.p < 0.98, last.t >= 6 else { return nil }
        let recent = samples.filter { $0.t >= last.t - 30 }
        let from = (recent.first.map { last.t - $0.t >= 6 } ?? false) ? recent.first! : first
        let rate = (last.p - from.p) / max(last.t - from.t, 0.001)
        guard rate > 0.00001 else { return nil }
        return (1 - last.p) / rate
    }

    /// Texte affiché pour un nombre de secondes restantes : arrondi pour ne pas clignoter.
    static func etaLabel(seconds left: Double) -> String {
        if left < 8 { return "Almost done" }
        if left < 60 { return "About \(max(Int((left / 5).rounded()), 2) * 5) s left" }
        let minutes = max(1, Int((left / 60).rounded()))
        if minutes < 60 { return "About \(minutes) min left" }
        let h = minutes / 60, m = (minutes % 60 / 5) * 5
        return m == 0 ? "About \(h) h left" : "About \(h) h \(m) min left"
    }

    /// Estimation affichable d'après des relevés isolés (vide tant qu'elle serait peu fiable ou quasi terminée) — sert aux tests.
    static func etaText(samples: [(t: Double, p: Double)]) -> String {
        guard let left = etaSeconds(samples: samples), left >= 10 else { return "" }
        return etaLabel(seconds: left)
    }

    /// Lisse l'estimation d'un travail en cours : une fois affichée, elle reste (elle décompte entre deux relevés au lieu de disparaître),
    /// et chaque nouvelle mesure ne la corrige que d'un quart, pour qu'elle ne saute pas de 15 s à 10 s puis revienne à 15 s.
    private static func smoothedETA(_ e: Entry) -> String {
        let now = Date().timeIntervalSince(e.startedAt)
        let counted = e.etaLeft.map { max($0 - (now - e.etaAt), 0) }
        if let raw = etaSeconds(samples: e.samples) { e.etaLeft = counted.map { $0 * 0.75 + raw * 0.25 } ?? raw }
        else { e.etaLeft = counted }
        e.etaAt = now
        return e.etaLeft.map { etaLabel(seconds: $0) } ?? ""
    }

    private var entries: [Entry] = []
    var isIdle: Bool { entries.isEmpty }      // en attente et en cours, dans l'ordre d'arrivée

    /// `replaces` : les fichiers d'origine, si ce travail en fait de nouvelles versions. `replace` : nil = d'après le réglage et la touche d'inversion.
    @discardableResult
    func add(_ title: String, subtitle: String = "", light: Bool = false, count: Int = 1, replaces: [URL] = [], replace: Bool? = nil, work: @escaping Work) -> UUID {
        add(title, subtitle: subtitle, light: light, count: count, replaces: replaces, replace: replace, statusWork: { progress, _ in try await work(progress) })
    }

    @discardableResult
    /// `count` : nombre de fichiers du lot. Au-dessus de 1, la ligne affiche « x of n done » d'après la progression globale
    /// (le travail doit la calculer comme (fichiers faits + part du fichier en cours) / n).
    func add(_ title: String, subtitle: String = "", light: Bool = false, count: Int = 1, replaces: [URL] = [], replace: Bool? = nil, statusWork work: @escaping StatusWork) -> UUID {
        let e = Entry(title: title, subtitle: subtitle, heavy: !light, count: count, work: work)
        e.replaces = replaces
        e.replaceNow = !replaces.isEmpty && (replace ?? ReplaceMode.shared.effectiveNow())
        entries.append(e)
        Toast.shared.add(ToastItem(id: e.id, phase: .waiting, title: title, subtitle: L("Waiting…"), progress: nil, cancel: { [weak self] in self?.cancel(e.id) }))
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

    /// Tant que des travaux tournent, le Mac ne se met pas en veille et macOS ne ralentit pas l'app (App Nap) :
    /// un gros lot (dizaines de vidéos) s'arrête sinon dès que l'écran se verrouille.
    private var activity: NSObjectProtocol?
    private func updateActivity() {
        if entries.isEmpty, let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        else if !entries.isEmpty, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Mandarine travaille sur vos fichiers")
        }
    }

    private func pump() {
        updateActivity()
        var heavyRunning = entries.filter { $0.started && $0.heavy }.count
        var ahead = 0
        for e in entries where !e.started {
            if e.heavy {
                if heavyRunning >= Self.maxHeavy {
                    ahead += 1
                    let n = heavyRunning + ahead - Self.maxHeavy
                    Toast.shared.update(e.id) { $0.subtitle = n <= 1 ? L("Waiting — next in line") : L("Waiting — \(n) jobs ahead") }
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
        Toast.shared.update(e.id) { $0.phase = .running; $0.subtitle = n > 1 ? L("0 of \(n) done") : e.subtitle; $0.progress = n > 1 ? 0 : -1 }
        let id = e.id
        let queue = self
        e.startedAt = Date()
        e.task = Task {
            do {
                let outs = try await e.work({ p in
                    DispatchQueue.main.async {
                        if p >= 0 { e.samples.append((Date().timeIntervalSince(e.startedAt), p)); if e.samples.count > 600 { e.samples.removeFirst(100) } }
                        let eta = e.cancelled ? "" : Self.smoothedETA(e)
                        let changed = eta != e.eta
                        e.eta = eta
                        Toast.shared.update(id) {
                            $0.progress = p
                            if changed { $0.eta = eta }
                            if n > 1, $0.phase == .running { $0.subtitle = L("\(min(max(Int((p * Double(n)).rounded(.down)), 0), n - 1)) of \(n) done") }
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

    /// Description d'un travail terminé : le nom du fichier (ou « et 2 autres »), puis le dossier.
    static func savedDetail(_ outs: [URL]) -> String {
        guard let first = outs.first else { return "" }
        let folder = "in " + first.deletingLastPathComponent().lastPathComponent
        return (outs.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) and \(outs.count - 1) more") + "\n" + folder
    }

    private func finish(_ e: Entry, _ result: Result<[URL], Error>) {
        entries.removeAll { $0 === e }
        defer { pump() }
        if e.cancelled { Toast.shared.remove(e.id); return }
        switch result {
        case .success(let outs):
            guard !outs.isEmpty else { Toast.shared.remove(e.id); return }
            // remplacement de l'original : seulement si chaque original a exactement un résultat
            let pairable = !e.replaces.isEmpty && e.replaces.count == outs.count
            var replacements: [Replacement] = []
            var note = ""
            if pairable && e.replaceNow {
                do { replacements = try Replacer.replace(originals: e.replaces, outputs: outs) }
                catch { note = "Couldn't replace the original: \(error.localizedDescription)" }
            }
            let shown = replacements.isEmpty ? outs : replacements.map(\.final)
            let replaced = !replacements.isEmpty
            let title = replaced ? (outs.count == 1 ? "Replaced" : "Replaced \(outs.count) items") : (outs.count == 1 ? "Saved" : "Saved \(outs.count) items")
            let id = e.id, originals = e.replaces
            Toast.shared.update(e.id) {
                $0.phase = .done; $0.title = title
                $0.subtitle = Self.savedDetail(shown) + (replaced ? L("\nThe original is in the Trash") : "") + (note.isEmpty ? "" : "\n" + note)
                $0.progress = nil; $0.reveal = shown; $0.cancel = nil; $0.eta = ""
                if replaced { $0.action = ("Undo", { ReplaceFlow.undo(id: id, replacements, originals: originals, outputs: outs) }) }
                else if pairable { $0.action = ("Replace original", { ReplaceFlow.apply(id: id, originals: originals, outputs: outs) }) }
            }
            Feedback.shared.done()
            if AppSettings.shared.revealAfterSave { NSWorkspace.shared.activateFileViewerSelecting(shown) }
        case .failure(let error):
            if error is CancellationError { Toast.shared.remove(e.id); return }
            if let part = error as? Partial, let first = part.outs.first {
                Toast.shared.update(e.id) {
                    $0.phase = .done; $0.title = L("Saved \(part.outs.count) of \(part.total)")
                    $0.subtitle = L("\(part.failed) failed\n\(part.message)"); $0.detail = part.message; $0.progress = nil; $0.reveal = part.outs; $0.cancel = nil; $0.eta = ""
                }
                Feedback.shared.done()
                if AppSettings.shared.revealAfterSave { NSWorkspace.shared.activateFileViewerSelecting(part.outs) }
                _ = first
                return
            }
            let msg = error.localizedDescription
            Toast.shared.update(e.id) {
                let task = e.title.replacingOccurrences(of: "…", with: "")
                let short = task.count <= 24
                $0.phase = .failed; $0.title = short ? task + L(" failed") : L("Failed")
                $0.subtitle = short ? msg : task + "\n" + msg; $0.detail = msg; $0.progress = nil; $0.cancel = nil; $0.eta = ""
            }
        }
    }
}

/// Remplacement des originaux à la demande depuis la notification (« Replace original »), et retour en arrière (« Undo »).
enum ReplaceFlow {
    static func apply(id: UUID, originals: [URL], outputs: [URL]) {
        do {
            let done = try Replacer.replace(originals: originals, outputs: outputs)
            let finals = done.map(\.final)
            Toast.shared.update(id) {
                $0.title = done.count == 1 ? L("Replaced") : L("Replaced \(done.count) items")
                $0.subtitle = JobQueue.savedDetail(finals) + L("\nThe original is in the Trash")
                $0.reveal = finals
                $0.action = ("Undo", { undo(id: id, done, originals: originals, outputs: outputs) })
            }
        } catch {
            Toast.shared.update(id) { $0.subtitle = L("Couldn't replace the original: \(error.localizedDescription)"); $0.action = nil }
        }
    }

    static func undo(id: UUID, _ done: [Replacement], originals: [URL], outputs: [URL]) {
        do {
            try Replacer.undo(done)
            Toast.shared.update(id) {
                $0.title = outputs.count == 1 ? L("Saved") : L("Saved \(outputs.count) items")
                $0.subtitle = JobQueue.savedDetail(outputs)
                $0.reveal = outputs
                $0.action = ("Replace original", { apply(id: id, originals: originals, outputs: outputs) })
            }
        } catch {
            Toast.shared.update(id) { $0.subtitle = error.localizedDescription; $0.action = nil }
        }
    }
}

/// Traitement d'un lot fichier par fichier : un fichier en échec n'arrête pas les autres.
/// À la fin, `finish()` rend tous les résultats, ou lève `JobQueue.Partial` (« Saved 8 of 10 — 2 failed ») si une partie seulement a réussi.
final class Batch {
    let total: Int
    private(set) var outs: [URL] = []
    private var failures: [String] = []
    init(total: Int) { self.total = total }

    func run(_ file: URL, _ body: () async throws -> [URL]) async throws {
        do { outs += try await body() }
        catch is CancellationError { throw CancellationError() }
        catch {
            if total == 1 { throw error }
            failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Version pour du code synchrone (dans un `Task.detached`).
    func runSync(_ file: URL, _ body: () throws -> [URL]) throws {
        do { outs += try body() }
        catch {
            if total == 1 { throw error }
            failures.append("\(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func finish() throws -> [URL] {
        if failures.isEmpty { return outs }
        if outs.isEmpty { throw MandarineError(failures[0]) }
        throw JobQueue.Partial(outs: outs, failed: failures.count, total: total, message: failures.joined(separator: "\n"))
    }
}
