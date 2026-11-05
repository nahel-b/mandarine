import Foundation

/// Traduction à l'exécution : `L("English text")` rend le texte dans la langue choisie (Réglages → General → Language) s'il existe, sinon le texte tel quel.
/// Les textes d'origine sont en anglais ; le français est dans `Resources/Localization/fr.json` (clé = texte anglais ; `%@` = une partie variable,
/// reprise dans la valeur par `%@` (dans l'ordre) ou `%1$@`, `%2$@`… pour changer l'ordre).
func L(_ s: String) -> String { L10n.tr(s) }

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, fr
    var id: String { rawValue }
    var title: String { self == .system ? L("System") : (self == .en ? "English" : "Français") }
}

enum L10n {
    static let changed = Notification.Name("MandarineLanguageChanged")

    /// Langue choisie dans les Réglages, ou dictée par `MANDARINE_LANG` (essais).
    static var setting: AppLanguage {
        get { AppLanguage(rawValue: ProcessInfo.processInfo.environment["MANDARINE_LANG"] ?? UserDefaults.standard.string(forKey: "language") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language"); lock.lock(); cache = [:]; lock.unlock(); NotificationCenter.default.post(name: changed, object: nil) }
    }

    /// « en » ou « fr » : la langue effectivement utilisée (en mode Système : celle du Mac si on la connaît, sinon l'anglais).
    static var code: String {
        switch setting {
        case .en: return "en"
        case .fr: return "fr"
        case .system: return (Locale.preferredLanguages.first ?? "en").hasPrefix("fr") ? "fr" : "en"
        }
    }
    static var locale: Locale { Locale(identifier: code) }

    private static let lock = NSLock()
    private static var table: [String: String] = [:]
    private static var templates: [(regex: NSRegularExpression, value: String)] = []
    private static var cache: [String: String] = [:]
    private static var loaded = false
    private static let missLog = ProcessInfo.processInfo.environment["MANDARINE_L10NLOG"] != nil

    static func tr(_ s: String) -> String {
        guard code == "fr", s.count > 1 else { return s }
        lock.lock(); defer { lock.unlock() }
        if !loaded { load() }
        if let v = table[s] { return v }
        if let c = cache[s] { return c }
        var out = s
        if s.contains("\n") {
            // texte sur plusieurs lignes : chaque ligne est traduite à part (nom de fichier, dossier, remarque…)
            out = s.split(separator: "\n", omittingEmptySubsequences: false).map { translateLine(String($0)) }.joined(separator: "\n")
        } else { out = translateLine(s) }
        if cache.count > 4000 { cache = [:] }
        cache[s] = out
        if out == s, missLog { FileHandle.standardError.write(Data(("L10N-MISS " + s.replacingOccurrences(of: "\n", with: "⏎") + "\n").utf8)) }
        return out
    }

    private static func translateLine(_ s: String) -> String {
        if let v = table[s] { return v }
        let range = NSRange(s.startIndex..., in: s)
        for t in templates {
            guard let m = t.regex.firstMatch(in: s, range: range), m.range.length == range.length else { continue }
            var groups: [String] = []
            for i in 1..<m.numberOfRanges { groups.append(Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "") }
            return fill(t.value, groups)
        }
        return s
    }

    /// Remplace `%@` (dans l'ordre) et `%1$@`… (par position) par les parties variables.
    private static func fill(_ template: String, _ groups: [String]) -> String {
        var out = "", next = 0
        let chars = Array(template)
        var i = 0
        while i < chars.count {
            if chars[i] == "%" {
                if i + 1 < chars.count, chars[i + 1] == "@" { out += next < groups.count ? groups[next] : ""; next += 1; i += 2; continue }
                var j = i + 1, num = ""
                while j < chars.count, chars[j].isNumber { num.append(chars[j]); j += 1 }
                if !num.isEmpty, j + 1 < chars.count, chars[j] == "$", chars[j + 1] == "@", let n = Int(num), n >= 1 {
                    out += n - 1 < groups.count ? groups[n - 1] : ""; i = j + 2; continue
                }
            }
            out.append(chars[i]); i += 1
        }
        return out
    }

    private static func load() {
        loaded = true
        var candidates: [URL] = []
        if let u = Bundle.main.url(forResource: "fr", withExtension: "json", subdirectory: "Localization") { candidates.append(u) }
        // exécution depuis .build (essais) : le fichier du dépôt
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localization/fr.json"))
        for u in candidates {
            guard let data = try? Data(contentsOf: u), let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { continue }
            var temps: [(NSRegularExpression, String, Int)] = []
            for (k, v) in dict {
                if k.contains("%@") {
                    let parts = k.components(separatedBy: "%@").map { NSRegularExpression.escapedPattern(for: $0) }
                    if let rx = try? NSRegularExpression(pattern: "^" + parts.joined(separator: "(.+?)") + "$", options: [.dotMatchesLineSeparators]) {
                        temps.append((rx, v, k.replacingOccurrences(of: "%@", with: "").count))     // les plus spécifiques (le plus de texte fixe) d'abord
                    }
                } else { table[k] = v }
            }
            templates = temps.sorted { $0.2 > $1.2 }.map { ($0.0, $0.1) }
            return
        }
    }
}
