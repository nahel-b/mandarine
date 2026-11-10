import SwiftUI

/// Transcription : audio (ou vidéo) → texte (.txt) et sous-titres (.srt), avec la reconnaissance vocale d'Apple.
struct TranscribeTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var localeID = Transcriber.defaultLocale().identifier
    @State private var wantText = true
    @State private var wantSRT = true
    private let locales = Transcriber.locales

    private var locale: Locale { Locale(identifier: localeID) }
    private var onDevice: Bool { Transcriber.isOnDevice(locale) }

    var body: some View {
        ToolShell(title: L("Transcribe"), close: close) {
            VStack(alignment: .leading, spacing: 12) {
                Text(urls.count == 1 ? urls[0].lastPathComponent : L("\(urls.count) files")).sectionLabel().lineLimit(1).truncationMode(.middle)
                HStack {
                    Text(L("Spoken language")).font(.system(size: 15, weight: .semibold))
                    Picker("", selection: $localeID) {
                        ForEach(locales, id: \.identifier) { Text(Transcriber.displayName($0)).tag($0.identifier) }
                    }.labelsHidden().frame(maxWidth: 220)
                }
                Text(onDevice ? L("This language is recognized on your Mac: the audio does not leave it.")
                              : L("This language is not downloaded for offline use: the audio is sent to Apple to be transcribed. You can download it in System Settings → Keyboard → Dictation."))
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
                Text(L("Save as")).font(.system(size: 15, weight: .semibold))
                Toggle(L("Text (.txt)"), isOn: $wantText)
                Toggle(L("Subtitles (.srt) — with the time of each line"), isOn: $wantSRT)
                Text(L("The files are saved next to the original. The first time, macOS asks to allow speech recognition."))
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 400, alignment: .leading)
        } footer: {
            Button(L("Transcribe")) { run() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(!wantText && !wantSRT).keyboardShortcut(.defaultAction)
        }
    }

    private func run() {
        let files = urls, id = localeID, text = wantText, srt = wantSRT
        Transcriber.savedIdentifier = id
        close()
        Dispatcher.job(L("Transcribing…"), subtitle: files.count == 1 ? files[0].lastPathComponent : L("\(files.count) files"), count: files.count) { progress in
            let batch = Batch(total: files.count)
            let loc = Locale(identifier: id)
            for (i, f) in files.enumerated() {
                try await batch.run(f) {
                    let info = await FFmpeg.probe(f)
                    guard info.hasAudio || info.duration > 0 else { throw MandarineError(L("\(f.lastPathComponent) n'a pas de piste audio.")) }
                    let words = try await Transcriber.transcribe(f, locale: loc, duration: info.duration) { p in progress((Double(i) + p) / Double(files.count)) }
                    guard !words.isEmpty else { throw MandarineError(L("No speech was found in \(f.lastPathComponent).")) }
                    var outs: [URL] = []
                    if text {
                        let u = OutputNaming.sibling(of: f, ext: "txt")
                        try Transcriber.plainText(words, locale: loc).write(to: u, atomically: true, encoding: .utf8); outs.append(u)
                    }
                    if srt {
                        let u = OutputNaming.sibling(of: f, ext: "srt")
                        try Transcriber.srt(Transcriber.cues(words, locale: loc), locale: loc).write(to: u, atomically: true, encoding: .utf8); outs.append(u)
                    }
                    return outs
                }
            }
            return try batch.finish()
        }
    }
}
