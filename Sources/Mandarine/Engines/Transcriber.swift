import Foundation
import Speech

/// Un mot reconnu, avec son instant de début et sa durée (en secondes).
struct SpokenWord { let start: Double; let end: Double; let text: String }

/// Un sous-titre : texte affiché entre deux instants.
struct SubtitleCue { let start: Double; let end: Double; let text: String }

/// Transcription audio → texte avec la reconnaissance vocale d'Apple (framework Speech).
enum Transcriber {
    // MARK: Langues

    /// Les langues reconnues par ce Mac, triées par nom.
    static var locales: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted { displayName($0).localizedCompare(displayName($1)) == .orderedAscending }
    }

    static func displayName(_ l: Locale) -> String {
        (Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier).capitalized
    }

    private static let savedKey = "transcribeLocale"

    static var savedIdentifier: String? {
        get { UserDefaults.standard.string(forKey: savedKey) }
        set { UserDefaults.standard.set(newValue, forKey: savedKey) }
    }

    /// Langue proposée au départ : la dernière choisie, sinon la langue de l'app / du Mac, sinon l'anglais.
    static func defaultLocale() -> Locale {
        let supported = locales
        func match(_ id: String) -> Locale? {
            let norm = id.replacingOccurrences(of: "-", with: "_")
            if let l = supported.first(where: { $0.identifier == norm || $0.identifier.replacingOccurrences(of: "-", with: "_") == norm }) { return l }
            let lang = norm.split(separator: "_").first.map(String.init) ?? norm
            return supported.first { ($0.languageCode ?? "") == lang }
        }
        if let s = savedIdentifier, let l = match(s) { return l }
        var wanted: [String] = []
        if L10n.code == "fr" { wanted.append("fr-FR") }
        wanted += Locale.preferredLanguages
        for w in wanted { if let l = match(w) { return l } }
        return match("en-US") ?? supported.first ?? Locale(identifier: "en_US")
    }

    /// Cette langue est-elle reconnue sans envoyer l'audio à Apple ?
    static func isOnDevice(_ l: Locale) -> Bool { SFSpeechRecognizer(locale: l)?.supportsOnDeviceRecognition ?? false }

    // MARK: Autorisation

    static func authorize() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { cont in SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) } }
        }
        guard status == .authorized else {
            throw MandarineError(L("Speech recognition is not allowed. Allow Mandarine in System Settings → Privacy & Security → Speech Recognition."))
        }
    }

    // MARK: Transcription

    private static let debugLog = ProcessInfo.processInfo.environment["MANDARINE_STTLOG"] != nil

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        var task: SFSpeechRecognitionTask?
        var committed: [SpokenWord] = []       // phrases dont l'horodatage est définitif
        var pending: [String] = []             // dernier résultat provisoire (texte sans horodatage) de la phrase en cours
        var reached = 0.0                      // point le plus avancé du fichier atteint par la reconnaissance (ne recule jamais)

        /// Phrase provisoire jamais « confirmée » : on la garde avec un horodatage estimé plutôt que de la perdre.
        func flushPending() {
            guard !pending.isEmpty else { return }
            var t = committed.last?.end ?? 0
            for w in pending { committed.append(SpokenWord(start: t, end: t + 0.4, text: w)); t += 0.4 }
            pending = []
        }
        /// Vrai une seule fois : le premier qui conclut.
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// Reconnaît un fichier audio court (≤ ~1 min si le serveur est utilisé). `offset` décale les instants.
    private static func recognize(_ file: URL, _ recognizer: SFSpeechRecognizer, onDevice: Bool, offset: Double,
                                  progress: @escaping (Double) -> Void) async throws -> [SpokenWord] {
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        request.addsPunctuation = true
        let gate = Gate()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[SpokenWord], Error>) in
                gate.task = recognizer.recognitionTask(with: request) { result, error in
                    if let result = result {
                        // Après un silence, la reconnaissance repart d'une phrase neuve : le résultat ne contient plus que cette phrase.
                        // Les résultats provisoires n'ont pas d'horodatage (0) ; celui qui clôt la phrase en a un. On garde chaque phrase clôturée.
                        let segs = result.bestTranscription.segments
                        if debugLog { FileHandle.standardError.write(Data("STT final=\(result.isFinal) n=\(segs.count) t=\(segs.first?.timestamp ?? -1)…\(segs.last.map { $0.timestamp + $0.duration } ?? -1) «\(result.bestTranscription.formattedString.prefix(70))»\n".utf8)) }
                        if let first = segs.first, let last = segs.last {
                            let words = segs.map { SpokenWord(start: offset + $0.timestamp, end: offset + $0.timestamp + $0.duration, text: $0.substring) }
                            if last.timestamp + last.duration > 0 {
                                gate.committed = gate.committed.filter { $0.start < offset + first.timestamp - 0.05 } + words
                                gate.pending = []
                                gate.reached = max(gate.reached, last.timestamp + last.duration)    // seuls les résultats horodatés font avancer la barre
                            } else {
                                // Une phrase neuve commence alors que l'ancienne n'a jamais été clôturée : on la garde (début différent, très courte).
                                if gate.pending.count >= 3, segs.count <= 2, segs[0].substring != gate.pending[0] { gate.flushPending() }
                                gate.pending = segs.map(\.substring)
                            }
                            progress(gate.reached)
                        }
                        if result.isFinal, gate.claim() { gate.flushPending(); cont.resume(returning: gate.committed) }
                    }
                    if let error = error, gate.claim() {
                        let ns = error as NSError
                        // « Aucune parole détectée » : un morceau silencieux n'est pas une erreur.
                        if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 || ns.code == 203 { gate.flushPending(); cont.resume(returning: gate.committed) }
                        else { cont.resume(throwing: error) }
                    }
                }
            }
        } onCancel: {
            gate.task?.cancel()          // le rappel reçoit alors une erreur d'annulation, qui reprend la continuation
        }
    }

    /// Le moteur de reconnaissance : celui d'Apple (intégré) ou Whisper (modèle optionnel, Réglages → Engines).
    enum Engine: String { case apple, whisper }
    private static let engineKey = "transcribeEngine"
    /// Dernier moteur choisi dans l'outil.
    static var savedEngine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: engineKey) }
    }
    /// Identifiant de langue qui demande à Whisper de détecter la langue lui-même.
    static let autoLanguage = "auto"

    /// Transcrit un fichier audio ou vidéo. `progress` : 0…1. `locale` nil : langue détectée (Whisper seulement).
    static func transcribe(_ source: URL, locale: Locale?, engine: Engine = .apple, duration: Double, detected: ((Locale) -> Void)? = nil, progress: @escaping (Double) -> Void) async throws -> [SpokenWord] {
        if engine == .whisper {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-stt-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let wav = dir.appendingPathComponent("audio.wav")
            try await FFmpeg.run(["-i", source.path, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav.path], duration: duration) { p in progress(p * 0.05) }
            let r = try await WhisperEngine.transcribe(wav: wav, language: WhisperEngine.languageCode(locale)) { p in progress(0.05 + 0.95 * p) }
            detected?(Locale(identifier: r.language))          // la langue trouvée par Whisper règle la mise en forme (espaces, ponctuation)
            return r.words
        }
        guard let locale = locale else { throw MandarineError(L("Speech recognition is not available for this language right now.")) }
        try await authorize()
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw MandarineError(L("Speech recognition is not available for this language right now."))
        }
        let onDevice = recognizer.supportsOnDeviceRecognition
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mandarine-stt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Piste audio en WAV mono 16 kHz : lisible par Speech quel que soit le format d'origine (vidéo, MP3, FLAC…).
        let wav = dir.appendingPathComponent("audio.wav")
        try await FFmpeg.run(["-i", source.path, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav.path], duration: duration) { p in progress(p * 0.1) }

        if onDevice {
            return try await recognize(wav, recognizer, onDevice: true, offset: 0) { t in
                if duration > 0 { progress(0.1 + 0.9 * min(1, t / duration)) }
            }
        }

        // Reconnaissance par le serveur d'Apple : environ une minute par requête, on découpe donc en morceaux.
        let chunk = 50.0
        try await FFmpeg.run(["-i", wav.path, "-f", "segment", "-segment_time", "\(Int(chunk))", "-c", "copy", dir.appendingPathComponent("part%05d.wav").path])
        let parts = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("part") }.sorted()
        var words: [SpokenWord] = []
        for (i, name) in parts.enumerated() {
            try Task.checkCancellation()
            let base = 0.1 + 0.9 * Double(i) / Double(max(parts.count, 1))
            let span = 0.9 / Double(max(parts.count, 1))
            words += try await recognize(dir.appendingPathComponent(name), recognizer, onDevice: false, offset: Double(i) * chunk) { t in
                progress(base + span * min(1, t / chunk))
            }
            progress(base + span)
        }
        return words
    }

    // MARK: Mise en forme

    /// Les langues écrites sans espaces entre les mots.
    private static func spaceless(_ l: Locale) -> Bool { ["ja", "zh", "yue", "th"].contains(l.languageCode ?? "") }

    private static func joined(_ words: [SpokenWord], _ l: Locale) -> String {
        if spaceless(l) { return words.map(\.text).joined() }
        var out = ""
        for w in words {
            let t = w.text
            if out.isEmpty { out = t; continue }
            // pas d'espace après une apostrophe (« l' année »), ni avant une virgule ou un point reconnus comme un mot à part
            let glue = out.hasSuffix("'") || out.hasSuffix("’") || [",", ".", "…"].contains(t) || (t.count == 1 && "?!:;".contains(t) && l.languageCode != "fr")
            out += (glue ? "" : " ") + t
        }
        return out
    }

    private static func endsSentence(_ s: String) -> Bool {
        guard let c = s.last else { return false }
        return ".?!…。！？".contains(c)
    }

    /// Texte brut : un paragraphe à chaque silence marqué (un point est ajouté si la phrase n'en a pas).
    static func plainText(_ words: [SpokenWord], locale: Locale) -> String {
        var paragraphs: [[SpokenWord]] = []
        var current: [SpokenWord] = []
        for w in words {
            if let last = current.last, w.start - last.end >= 1.8 { paragraphs.append(current); current = [] }
            current.append(w)
        }
        if !current.isEmpty { paragraphs.append(current) }
        let texts = paragraphs.map { p -> String in
            let t = joined(p, locale)
            guard let c = t.last, !spaceless(locale), !".?!…:;,".contains(c) else { return t }
            return t + "."
        }
        return texts.joined(separator: "\n\n") + "\n"
    }

    /// Découpe les mots en sous-titres : au plus ~80 caractères et ~6 s, coupés aux silences et à la fin des phrases.
    static func cues(_ words: [SpokenWord], locale: Locale) -> [SubtitleCue] {
        var out: [SubtitleCue] = []
        var cur: [SpokenWord] = []
        func flush() {
            guard let first = cur.first, let last = cur.last else { return }
            let end = max(last.end, first.start + 0.5)
            out.append(SubtitleCue(start: first.start, end: end, text: joined(cur, locale)))
            cur = []
        }
        for w in words {
            if let last = cur.last {
                let gap = w.start - last.end
                let length = joined(cur, locale).count
                let span = w.end - (cur.first?.start ?? w.start)
                if gap >= 0.7 || span > 6 || length + w.text.count > 80 || (length >= 24 && endsSentence(last.text)) { flush() }
            }
            cur.append(w)
        }
        flush()
        // Pas de chevauchement : un sous-titre finit au plus tard quand le suivant commence.
        for i in 0..<out.count - (out.isEmpty ? 0 : 1) where out[i].end > out[i + 1].start {
            out[i] = SubtitleCue(start: out[i].start, end: max(out[i].start + 0.2, out[i + 1].start), text: out[i].text)
        }
        return out
    }

    private static func timecode(_ t: Double) -> String {
        let ms = Int((max(0, t) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    /// Une ligne trop longue est coupée en deux lignes équilibrées (au plus ~42 caractères chacune).
    private static func wrapped(_ text: String, _ l: Locale) -> String {
        guard text.count > 42, !spaceless(l) else { return text }
        let parts = text.split(separator: " ")
        var best = text, bestDiff = Int.max
        for i in 1..<max(parts.count, 1) {
            let a = parts[..<i].joined(separator: " "), b = parts[i...].joined(separator: " ")
            let diff = abs(a.count - b.count)
            if diff < bestDiff { bestDiff = diff; best = a + "\n" + b }
        }
        return best
    }

    static func srt(_ cues: [SubtitleCue], locale: Locale) -> String {
        cues.enumerated().map { i, c in
            "\(i + 1)\n\(timecode(c.start)) --> \(timecode(c.end))\n\(wrapped(c.text, locale))\n"
        }.joined(separator: "\n")
    }
}
