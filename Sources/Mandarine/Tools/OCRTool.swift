import SwiftUI

/// Extract Text : lit le texte d'images ou de PDF scannés, le montre dans une zone modifiable, à copier ou à enregistrer en .txt.
struct OCRTool: View {
    let urls: [URL]
    let close: () -> Void
    @State private var results: [(name: String, pages: [[String]])] = []
    @State private var text = ""
    @State private var keepBreaks = true
    @State private var running = true
    @State private var status = "Reading…"
    @State private var fraction: Double = 0
    @State private var copied = false

    var body: some View {
        ToolShell(title: L("Extract Text"), close: close) {
            VStack(alignment: .leading, spacing: 10) {
                if running {
                    HStack(spacing: 10) {
                        ProgressView(value: fraction).frame(width: 120)
                        Text(L(status)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                } else {
                    HStack {
                        Text(text.isEmpty ? L("No text found") : L("\(text.split(whereSeparator: \.isNewline).count) lines · \(text.count) characters")).sectionLabel()
                        Spacer()
                        Toggle(L("Keep line breaks"), isOn: $keepBreaks).font(.system(size: 12))
                            .onChange(of: keepBreaks) { _ in rebuild() }
                    }
                }
                TextEditor(text: $text)
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .padding(8).frame(width: 476, height: 280)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.85)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.1)))
                    .disabled(running)
                Text(L("Recognized on this Mac, offline. The language is detected automatically. You can edit the text before using it."))
                    .sectionLabel().fixedSize(horizontal: false, vertical: true)
            }.frame(width: 476)
        } footer: {
            Button(L("Save as .txt")) { save() }.buttonStyle(PillButtonStyle()).disabled(running || text.isEmpty)
            Button(copied ? L("Copied") : L("Copy Text")) { copy() }.buttonStyle(PillButtonStyle()).disabled(running || text.isEmpty)
        }
        .task { await read() }
    }

    private func read() async {
        let files = urls
        var all: [(name: String, pages: [[String]])] = []
        for (i, f) in files.enumerated() {
            let label = files.count > 1 ? "\(f.lastPathComponent) (\(i + 1)/\(files.count))" : f.lastPathComponent
            status = "Reading \(label)…"
            do {
                let pages = try await Task.detached {
                    try OCREngine.pages(of: f) { done, total in
                        DispatchQueue.main.async {
                            fraction = (Double(i) + Double(done) / Double(max(total, 1))) / Double(files.count)
                            if total > 1 { status = "Reading \(f.lastPathComponent) — page \(min(done + 1, total)) of \(total)…" }
                        }
                    }
                }.value
                all.append((f.lastPathComponent, pages))
            } catch {
                Toast.shared.fail(L("Couldn't read file"), subtitle: L("\(f.lastPathComponent)\n\(error.localizedDescription)"))
            }
        }
        results = all
        running = false
        rebuild()
    }

    private func rebuild() {
        if results.count == 1 { text = OCREngine.join(results[0].pages, keepLineBreaks: keepBreaks); return }
        text = results.map { "— \($0.name) —\n" + OCREngine.join($0.pages, keepLineBreaks: keepBreaks) }.joined(separator: "\n\n")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func save() {
        let out = OutputNaming.sibling(of: urls[0], ext: "txt"), s = text
        close()
        Dispatcher.job(L("Saving text…"), light: true) { _ in
            try s.write(to: out, atomically: true, encoding: .utf8)
            return [out]
        }
    }
}
