import SwiftUI
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

/// Fenêtre commune « texte glissé » : le texte d'origine, le résultat, et Copy / Save .txt.
struct TextResultView<Extra: View>: View {
    let title: String
    let source: String
    let result: String
    let busy: Bool
    let error: String?
    let close: () -> Void
    @ViewBuilder var extra: () -> Extra
    @State private var copied = false

    var body: some View {
        ToolShell(title: title, close: close) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(SnippetStore.wordCount(source)) words").sectionLabel()
                Text(source.prefix(600) + (source.count > 600 ? "…" : ""))
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.05)))
                extra()
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.85))
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.1))
                    if let e = error {
                        Text(e).font(.system(size: 12)).foregroundStyle(.red).padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else if busy && result.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        ScrollView { Text(result).font(.system(size: 13)).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }.frame(width: 480, height: 200)
            }.frame(width: 480)
        } footer: {
            Button("Save as .txt") {
                let r = result; close()
                Dispatcher.job("Saving text…", light: true) { _ in
                    let out = SnippetStore.outputURL(for: r, ext: "txt"); try r.write(to: out, atomically: true, encoding: .utf8); return [out]
                }
            }.buttonStyle(PillButtonStyle()).disabled(result.isEmpty)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string)
                copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }.buttonStyle(PillButtonStyle()).disabled(result.isEmpty)
        }
    }
}

// MARK: Résumé

struct SummarizeTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var result = ""
    @State private var busy = true
    @State private var error: String?
    private var text: String { urls.map { SnippetStore.text(of: $0) }.joined(separator: "\n\n") }

    var body: some View {
        TextResultView(title: "Summarize", source: text, result: result, busy: busy, error: error, close: close) { EmptyView() }
            .task {
                do { result = try await SnippetEngine.summarize(text) } catch { self.error = error.localizedDescription }
                busy = false
            }
    }
}

// MARK: Traduction (framework Translation, macOS 15)

struct TranslateTool: View {
    let urls: [URL]
    let close: () -> Void
    var body: some View {
        if #available(macOS 15.0, *) { TranslateToolBody(text: urls.map { SnippetStore.text(of: $0) }.joined(separator: "\n\n"), close: close) }
        else { Text("Translation needs macOS 15 or later.").padding(30) }
    }
}

@available(macOS 15.0, *)
private struct TranslateToolBody: View {
    let text: String
    let close: () -> Void
    @State private var languages: [Locale.Language] = []
    @State private var target: Locale.Language = Locale.current.language
    @State private var config: TranslationSession.Configuration?
    @State private var result = ""
    @State private var busy = true
    @State private var error: String?

    private func name(_ l: Locale.Language) -> String { Locale.current.localizedString(forIdentifier: l.minimalIdentifier)?.capitalized ?? l.minimalIdentifier }

    var body: some View {
        TextResultView(title: "Translate", source: text, result: result, busy: busy, error: error, close: close) {
            HStack {
                Text("To").sectionLabel()
                Picker("", selection: $target) {
                    ForEach(languages, id: \.minimalIdentifier) { Text(name($0)).tag($0) }
                }.labelsHidden().frame(width: 200)
                Spacer()
                if let src = SnippetEngine.language(of: text) { Text("from " + (Locale.current.localizedString(forLanguageCode: src.rawValue)?.capitalized ?? src.rawValue)).sectionLabel() }
            }
        }
        .translationTask(config) { session in
            do { let r = try await session.translate(text); result = r.targetText; error = nil }
            catch { self.error = error.localizedDescription }
            busy = false
        }
        .task {
            let all = await LanguageAvailability().supportedLanguages
            languages = all.sorted { name($0) < name($1) }
            // Cible par défaut : la langue du Mac, ou l'anglais si le texte est déjà dans cette langue
            let sys = Locale.current.language
            let src = SnippetEngine.language(of: text)?.rawValue
            target = (src != nil && src == sys.languageCode?.identifier) ? Locale.Language(identifier: "en") : sys
            if let m = languages.first(where: { $0.minimalIdentifier == target.minimalIdentifier }) { target = m }
            config = .init(source: nil, target: target)
        }
        .onChange(of: target) { t in
            busy = true; result = ""; error = nil
            config = .init(source: nil, target: t)
        }
    }
}
