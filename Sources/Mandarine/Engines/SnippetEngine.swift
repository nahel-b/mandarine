import Foundation
import AppKit
import AVFoundation
import NaturalLanguage
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Un texte glissé est enregistré dans un petit fichier .txt du dossier de cache : le reste de l'app le traite alors comme n'importe quel fichier.
enum SnippetStore {
    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Mandarine/snippets", isDirectory: true)
    }
    static func isSnippet(_ u: URL) -> Bool { u.isFileURL && u.path.hasPrefix(folder.path + "/") }
    static func text(of u: URL) -> String { (try? String(contentsOf: u, encoding: .utf8)) ?? "" }

    static func make(_ text: String) -> URL? {
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent("Selected text.txt")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); try text.write(to: file, atomically: true, encoding: .utf8) } catch { return nil }
        return file
    }

    /// Supprime les extraits de plus d'un jour.
    static func cleanup() {
        let fm = FileManager.default
        for d in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let m = try? d.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(m) > 86400 { try? fm.removeItem(at: d) }
        }
    }

    /// Où enregistrer les résultats : le Bureau, nommés d'après les premiers mots du texte.
    static func outputURL(for text: String, ext: String) -> URL {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(6).joined(separator: " ")
        let clean = words.components(separatedBy: CharacterSet(charactersIn: "/:\\?*\"<>|")).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?…-")))
        let base = String((clean.isEmpty ? "Text" : clean).prefix(48))
        let dir = ProcessInfo.processInfo.environment["MANDARINE_SNIPPET_OUT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        return OutputNaming.unique(folder: dir, base: base, ext: ext)
    }

    static func wordCount(_ t: String) -> Int { t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }
}

enum SnippetEngine {
    /// Langue dominante du texte (« fr », « en »…).
    static func language(of text: String) -> NLLanguage? { NLLanguageRecognizer.dominantLanguage(for: String(text.prefix(2000))) }

    // MARK: Conversions de la roue ⇧

    static func supports(_ to: String) -> Bool { ["txt", "md", "pdf", "docx", "m4a", "qr"].contains(to) }

    static func convert(_ file: URL, to e: String) async throws -> URL {
        let text = SnippetStore.text(of: file)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MandarineError("The text is empty.") }
        let out = SnippetStore.outputURL(for: text, ext: e == "qr" ? "png" : e)
        switch e {
        case "txt", "md":
            try text.write(to: out, atomically: true, encoding: .utf8)
        case "pdf", "docx":
            // Le fichier .txt est converti par le moteur de documents, puis déplacé sur le Bureau
            let made = try await Task.detached { try Converter.convertDocument(file, to: e) }.value
            try FileManager.default.moveItem(at: made, to: out)
        case "m4a":
            try await speechFile(text, to: out)
        case "qr":
            try qrCode(text, to: out)
        default:
            throw MandarineError("Unsupported format.")
        }
        return out
    }

    // MARK: QR code

    static func qrCode(_ text: String, to out: URL) throws {
        guard let data = text.data(using: .utf8), data.count <= 2300 else { throw MandarineError("The text is too long for a QR code (about 2,000 characters at most).") }
        let f = CIFilter.qrCodeGenerator()
        f.message = data; f.correctionLevel = "M"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { throw MandarineError("Couldn't make the QR code.") }
        // Marge blanche de 4 modules, fond blanc
        let pad: CGFloat = 48
        let canvas = CGRect(x: img.extent.minX - pad, y: img.extent.minY - pad, width: img.extent.width + 2 * pad, height: img.extent.height + 2 * pad)
        let composed = img.composited(over: CIImage(color: .white).cropped(to: canvas))
        guard let cg = CIContext().createCGImage(composed, from: canvas) else { throw MandarineError("Couldn't make the QR code.") }
        try ImageEngine.write(cg, to: out, ext: "png")
    }

    // MARK: Voix

    /// Voix du système qui correspond à la langue du texte (sinon la voix par défaut).
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        guard let lang = language(of: text)?.rawValue else { return nil }
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(lang.lowercased()) }
        let sys = Locale.current.region?.identifier.lowercased() ?? ""
        return candidates.max { a, b in
            func score(_ v: AVSpeechSynthesisVoice) -> Int { (v.quality == .enhanced ? 2 : v.quality == .premium ? 3 : 0) + (v.language.lowercased().hasSuffix(sys) ? 1 : 0) }
            return score(a) < score(b)
        } ?? AVSpeechSynthesisVoice(language: lang)
    }

    /// Fichier audio de la lecture du texte (outil `say` du système).
    static func speechFile(_ text: String, to out: URL) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var args = ["-o", out.path, "--data-format=aac", "-f", tmp.path]
        if let v = voice(for: text) { args = ["-v", v.name] + args }
        let status = try await Task.detached { () throws -> Int32 in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = args
            p.standardError = Pipe(); try p.run(); p.waitUntilExit(); return p.terminationStatus
        }.value
        guard status == 0, FileManager.default.fileExists(atPath: out.path) else { throw MandarineError("The system voice couldn't read the text.") }
    }

    // MARK: Résumé (modèle de langage du Mac, macOS 26 avec Apple Intelligence)

    static var canSummarize: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    static var summarizeUnavailableReason: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This Mac doesn't support Apple Intelligence."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings to summarize."
                case .modelNotReady: return "The Apple Intelligence model is still downloading. Try again later."
                @unknown default: return "The on-device model isn't available."
                }
            }
        }
        #endif
        return "Summaries need macOS 26 with Apple Intelligence."
    }

    static func summarize(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard canSummarize else { throw MandarineError(summarizeUnavailableReason) }
            let langName = language(of: text).flatMap { Locale(identifier: "en").localizedString(forLanguageCode: $0.rawValue) } ?? "the language of the text"
            let session = LanguageModelSession(instructions: "Summarize the user's text clearly and briefly. Write the summary in \(langName), the language of the text. Use short bullet points when it helps. Add nothing that isn't in the text.")
            let r = try await session.respond(to: String(text.prefix(9000)))
            return r.content
        }
        #endif
        throw MandarineError(summarizeUnavailableReason)
    }

    static var canTranslate: Bool { if #available(macOS 15.0, *) { return true } else { return false } }
}

/// Lecture à voix haute, avec un bouton Stop dans la pile de notifications.
@MainActor
final class SnippetSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SnippetSpeaker()
    private let synth = AVSpeechSynthesizer()
    private var toastID: UUID?
    override init() { super.init(); synth.delegate = self }

    func speak(_ text: String) {
        stop()
        let u = AVSpeechUtterance(string: text)
        if let v = SnippetEngine.voice(for: text) { u.voice = v }
        synth.speak(u)
        toastID = Toast.shared.add(ToastItem(id: UUID(), phase: .running, title: "Reading aloud…", subtitle: "\(SnippetStore.wordCount(text)) words", progress: -1,
                                              cancel: { [weak self] in self?.stop() }))
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        if let id = toastID { Toast.shared.remove(id); toastID = nil }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in if let id = self.toastID { Toast.shared.remove(id); self.toastID = nil } }
    }
}
