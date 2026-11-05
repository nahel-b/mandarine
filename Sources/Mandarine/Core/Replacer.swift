import Foundation

/// Un original remplacé par son résultat : de quoi tout remettre comme avant.
struct Replacement {
    let original: URL          // chemin d'origine
    let trashed: URL           // où est allé l'original (Corbeille)
    let output: URL            // où le résultat avait été écrit
    let final: URL             // où il se trouve maintenant
}

/// Remplacement des fichiers d'origine par les résultats d'un travail. Jamais de suppression : l'original va à la Corbeille.
enum Replacer {
    static func replace(originals: [URL], outputs: [URL]) throws -> [Replacement] {
        guard originals.count == outputs.count, !originals.isEmpty else { throw MandarineError("Nothing to replace here.") }
        let fm = FileManager.default
        // tout est vérifié avant de toucher à quoi que ce soit
        for (o, r) in zip(originals, outputs) {
            guard fm.fileExists(atPath: o.path) else { throw MandarineError("\(o.lastPathComponent) is no longer there.") }
            guard fm.fileExists(atPath: r.path), r.fileSize > 0 || r.hasDirectoryPath else { throw MandarineError("The result for \(o.lastPathComponent) is missing.") }
            guard o.standardizedFileURL != r.standardizedFileURL else { throw MandarineError("The result is the original itself.") }
        }
        var done: [Replacement] = []
        do {
            for (o, r) in zip(originals, outputs) {
                var trashedNS: NSURL?
                try fm.trashItem(at: o, resultingItemURL: &trashedNS)
                let trashed = (trashedNS as URL?) ?? o
                // le résultat prend le nom de l'original (avec sa propre extension si le format a changé), sauf si ce nom est déjà pris
                let wanted = o.deletingPathExtension().appendingPathExtension(r.pathExtension)
                var final = r
                if !fm.fileExists(atPath: wanted.path) { try fm.moveItem(at: r, to: wanted); final = wanted }
                done.append(Replacement(original: o, trashed: trashed, output: r, final: final))
            }
        } catch {
            try? undo(done)          // une erreur en route : on remet ce qui avait déjà été fait
            throw error
        }
        return done
    }

    /// Rend l'original et remet le résultat là où il avait été écrit.
    static func undo(_ list: [Replacement]) throws {
        let fm = FileManager.default
        for r in list.reversed() {
            if r.final != r.output, fm.fileExists(atPath: r.final.path), !fm.fileExists(atPath: r.output.path) { try fm.moveItem(at: r.final, to: r.output) }
            if fm.fileExists(atPath: r.trashed.path), !fm.fileExists(atPath: r.original.path) { try fm.moveItem(at: r.trashed, to: r.original) }
            else if !fm.fileExists(atPath: r.original.path) { throw MandarineError("Put \(r.original.lastPathComponent) back from the Trash (Finder → Put Back).") }
        }
    }
}
