import Foundation
import whisper

/// Modèle de reconnaissance vocale Whisper « large-v3-turbo » quantifié en 5 bits (ggml q5_0), publié par le projet whisper.cpp.
/// Optionnel : il n'est ni dans l'app ni téléchargé tant que l'utilisateur ne le demande pas (Réglages → Engines).
/// Beaucoup plus précis que la reconnaissance d'Apple : bonne ponctuation, noms propres, un seul passage sur un long fichier, langue détectable.
enum WhisperModel {
    static let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
    static let sha256 = "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
    static let bytes: Int64 = 574_041_195
    static let sizeText = "570 MB"

    static var folder: URL { FaceModel.folder }          // ~/Library/Application Support/Mandarine/models
    static var file: URL { folder.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin") }
    static var isInstalled: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int64) == bytes
    }

    /// Télécharge, vérifie la taille et l'empreinte SHA-256, puis installe. `progress` : 0…1.
    static func download(progress: @escaping (Double) -> Void) async throws {
        let (tmp, resp) = try await Downloader.fetch(url, progress: progress)
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MandarineError(L("The server answered with an error (\((resp as? HTTPURLResponse)?.statusCode ?? 0)).")) }
        guard try Downloader.sha256(of: tmp) == sha256 else { throw MandarineError(L("The downloaded model doesn't match its expected checksum — nothing was installed.")) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
    }

    static func remove() { try? FileManager.default.removeItem(at: file) }
}

/// Transcription avec Whisper (whisper.cpp : Metal + Accelerate). Reçoit la piste audio en WAV mono 16 kHz.
enum WhisperEngine {
    /// Code de langue Whisper (« fr », « en »…) d'une langue de l'interface, nil (détection automatique) si Whisper ne la connaît pas.
    static func languageCode(_ locale: Locale?) -> String? {
        guard let code = locale?.language.languageCode?.identifier else { return nil }
        return whisper_lang_id(code) >= 0 ? code : nil
    }

    private final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        let progress: (Double) -> Void
        init(_ p: @escaping (Double) -> Void) { progress = p }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }

    /// Échantillons (−1…1) d'un WAV PCM 16 bits mono.
    static func samples(of wav: URL) throws -> [Float] {
        let d = try Data(contentsOf: wav, options: .mappedIfSafe)
        guard d.count > 44, d[0..<4] == Data("RIFF".utf8) else { throw MandarineError(L("The audio couldn't be read.")) }
        var p = 12, start = -1, len = 0
        while p + 8 <= d.count {                       // on cherche le bloc « data » (un bloc LIST peut le précéder)
            let id = String(decoding: d[p..<p + 4], as: UTF8.self)
            let size = Int(d[p + 4]) | Int(d[p + 5]) << 8 | Int(d[p + 6]) << 16 | Int(d[p + 7]) << 24
            if id == "data" { start = p + 8; len = min(size, d.count - start); break }
            p += 8 + size + (size & 1)
        }
        guard start >= 0 else { throw MandarineError(L("The audio couldn't be read.")) }
        let n = len / 2
        return d.withUnsafeBytes { raw -> [Float] in
            let s = raw.baseAddress!.advanced(by: start).assumingMemoryBound(to: Int16.self)
            return (0..<n).map { Float(Int16(littleEndian: s[$0])) / 32768 }
        }
    }

    /// Transcrit. `language` : code Whisper, nil pour la détecter. `progress` : 0…1.
    static func transcribe(wav: URL, language: String?, progress: @escaping (Double) -> Void) async throws -> (words: [SpokenWord], language: String) {
        guard WhisperModel.isInstalled else { throw MandarineError(L("The Whisper model isn't installed. Download it in Settings → Engines.")) }
        let pcm = try samples(of: wav)
        let control = Control(progress)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try run(pcm, language: language, control: control) }.value
        } onCancel: { control.cancel() }
    }

    private static func run(_ pcm: [Float], language: String?, control: Control) throws -> (words: [SpokenWord], language: String) {
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(WhisperModel.file.path, cparams) else {
            throw MandarineError(L("The Whisper model couldn't be loaded. Try downloading it again in Settings → Engines."))
        }
        defer { whisper_free(ctx) }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        params.translate = false
        params.print_progress = false; params.print_realtime = false; params.print_timestamps = false; params.print_special = false
        params.suppress_nst = true
        params.progress_callback = { _, _, pct, user in
            guard let user = user else { return }
            Unmanaged<Control>.fromOpaque(user).takeUnretainedValue().progress(Double(pct) / 100)
        }
        params.abort_callback = { user in
            guard let user = user else { return false }
            return Unmanaged<Control>.fromOpaque(user).takeUnretainedValue().isCancelled
        }
        let user = Unmanaged.passUnretained(control).toOpaque()
        params.progress_callback_user_data = user
        params.abort_callback_user_data = user

        let status: Int32 = (language ?? "auto").withCString { lang in
            params.language = lang
            params.detect_language = language == nil
            return pcm.withUnsafeBufferPointer { whisper_full(ctx, params, $0.baseAddress, Int32($0.count)) }
        }
        try Task.checkCancellation()
        if control.isCancelled { throw CancellationError() }
        guard status == 0 else { throw MandarineError(L("The Whisper transcription failed (code \(Int(status))).")) }

        // Segments → mots. Whisper donne le début et la fin de chaque segment (en centièmes de seconde) : les mots y sont répartis selon leur longueur.
        var words: [SpokenWord] = []
        for i in 0..<Int(whisper_full_n_segments(ctx)) {
            guard let c = whisper_full_get_segment_text(ctx, Int32(i)) else { continue }
            let text = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || isNoise(text) { continue }
            let t0 = Double(whisper_full_get_segment_t0(ctx, Int32(i))) / 100, t1 = max(Double(whisper_full_get_segment_t1(ctx, Int32(i))) / 100, t0 + 0.2)
            let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
            let total = Double(parts.reduce(0) { $0 + $1.count + 1 })
            var t = t0
            for w in parts {
                let d = (t1 - t0) * Double(w.count + 1) / total
                words.append(SpokenWord(start: t, end: t + d, text: w)); t += d
            }
        }
        let detected = whisper_lang_str(whisper_full_lang_id(ctx)).map { String(cString: $0) } ?? language ?? "en"
        return (words, detected)
    }

    /// « [BLANK_AUDIO] », « (musique) », « ♪ » : Whisper annonce ainsi les silences et la musique, ce n'est pas de la parole.
    private static func isNoise(_ t: String) -> Bool {
        if t.contains("♪") || t.contains("♫") { return true }
        return (t.hasPrefix("[") && t.hasSuffix("]")) || (t.hasPrefix("(") && t.hasSuffix(")")) || (t.hasPrefix("*") && t.hasSuffix("*"))
    }
}
