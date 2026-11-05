import AppKit

/// Exécute ce qui a été déposé sur un segment de la roue.
enum Dispatcher {
    static func run(_ item: WheelItem, on urls: [URL]) {
        switch item.payload {
        case .convert(let ext): convert(urls, to: ext)
        case .tool(let id): ToolWindowController.present(id, urls: urls)
        case .action(let a): FileActions.perform(a, on: urls)
        }
    }

    static func convert(_ urls: [URL], to ext: String) {
        let title = "Converting to \(ext.uppercased())…"
        if urls.count > 1, FileKind.common(of: urls) == .image, Catalog.normalized(ext) == "pdf" {      // plusieurs images → un seul PDF
            JobQueue.shared.add(title, subtitle: L("\(urls.count) images")) { progress in
                try await Converter.run(urls: urls, to: ext, progress: progress)
            }
            return
        }
        // seuls de vrais fichiers peuvent être remplacés (pas un lien, pas un texte glissé)
        let replaceable = urls.allSatisfy(\.isFileURL) && FileKind.common(of: urls) != .snippet
        if urls.count == 1 {
            let u = urls[0]
            JobQueue.shared.add(title, subtitle: u.lastPathComponent, replaces: replaceable ? [u] : []) { progress in
                try await Converter.run(urls: [u], to: ext, progress: progress)
            }
            return
        }
        // Plusieurs fichiers : UNE seule ligne de notification pour tout le lot (« 3 of 10 done »), avec une progression globale.
        // Deux conversions tournent en même temps (comme avant) ; une conversion qui échoue n'arrête pas les autres.
        let total = urls.count
        JobQueue.shared.add(title, subtitle: L("0 of \(total) done"), replaces: replaceable ? urls : [], statusWork: { progress, status in
            let tally = BatchTally(total: total)
            var outs: [URL] = []
            var byIndex: [Int: [URL]] = [:]          // résultats rangés dans l'ordre des fichiers (pour associer chacun à son original)
            var failures: [String] = []
            try await withThrowingTaskGroup(of: (Int, [URL], String?).self) { group in
                var next = 0
                func launch() {
                    guard next < total else { return }
                    let i = next, u = urls[next]; next += 1
                    group.addTask {
                        do {
                            let o = try await Converter.run(urls: [u], to: ext) { p in
                                let (overall, done) = tally.update(i, p)
                                progress(overall); status("\(done) of \(total) done")
                            }
                            return (i, o, nil)
                        } catch is CancellationError { throw CancellationError() }
                        catch { return (i, [], "\(u.lastPathComponent): \(error.localizedDescription)") }
                    }
                }
                for _ in 0..<min(JobQueue.maxHeavy, total) { launch() }
                while let (i, o, failure) = try await group.next() {
                    byIndex[i] = o
                    if let f = failure { failures.append(f) }
                    let (overall, done) = tally.finish(i)
                    progress(overall); status("\(done) of \(total) done")
                    launch()
                }
            }
            outs = byIndex.keys.sorted().flatMap { byIndex[$0] ?? [] }
            if !failures.isEmpty {
                if outs.isEmpty { throw MandarineError(failures.first ?? L("Conversion failed.")) }
                throw JobQueue.Partial(outs: outs, failed: failures.count, total: total, message: failures.joined(separator: "\n"))
            }
            return outs
        })
    }

    /// Met un travail dans la file (voir JobQueue). `light` : travail court, qui ne compte pas dans la limite de travaux lourds.
    /// `count` : nombre de fichiers du lot ; la ligne indique alors « x of n done » (voir JobQueue.add).
    /// `replaces` : les fichiers d'origine que le travail peut remplacer (voir ReplaceMode) ; `replace` : forcer le choix (nil = réglage + touche).
    static func job(_ title: String, subtitle: String = "", light: Bool = false, count: Int = 1, replaces: [URL] = [], replace: Bool? = nil, _ work: @escaping JobQueue.Work) {
        JobQueue.shared.add(title, subtitle: subtitle, light: light, count: count, replaces: replaces, replace: replace, work: work)
    }
}

/// Avancement d'un lot de fichiers traités en parallèle : part de chaque fichier, fichiers terminés, progression globale.
final class BatchTally: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double]
    private var finished = Set<Int>()
    init(total: Int) { fractions = Array(repeating: 0, count: total) }
    func update(_ i: Int, _ p: Double) -> (Double, Int) {
        lock.lock(); defer { lock.unlock() }
        fractions[i] = max(fractions[i], min(1, p))
        return (fractions.reduce(0, +) / Double(fractions.count), finished.count)
    }
    func finish(_ i: Int) -> (Double, Int) {
        lock.lock(); defer { lock.unlock() }
        fractions[i] = 1; finished.insert(i)
        return (fractions.reduce(0, +) / Double(fractions.count), finished.count)
    }
}
