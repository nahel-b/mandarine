import SwiftUI

/// Tri rapide : photos et vidéos en grand, une touche pour garder / peut-être / rejeter. Les marques sont des étiquettes Finder (vert, jaune, rouge).
struct CullTool: View {
    let urls: [URL]
    let close: () -> Void

    enum Mark: Int {
        case none, keep, maybe, reject
        var label: Int? { switch self { case .none: return nil; case .keep: return 2; case .maybe: return 5; case .reject: return 6 } }      // numéros de couleur des étiquettes
    }
    private static let managed = [2, 5, 6]

    @State private var marks: [Mark]
    @State private var index = 0
    @State private var images: [Int: NSImage] = [:]

    init(urls: [URL], close: @escaping () -> Void) {
        self.urls = urls; self.close = close
        _marks = State(initialValue: Array(repeating: .none, count: urls.count))
    }

    private var legend: String {
        let s = AppSettings.shared
        return "\(s.cullKeepKey.uppercased()) keep  ·  \(s.cullMaybeKey.uppercased()) maybe  ·  \(s.cullRejectKey.uppercased()) reject  ·  \(s.cullClearKey.uppercased()) clear  ·  ← → browse  ·  ↑ keep  ·  ↓ reject"
    }

    private func count(_ m: Mark) -> Int { marks.filter { $0 == m }.count }
    private func color(_ m: Mark) -> Color {
        guard let l = m.label else { return Color(white: 0.7) }
        return Color(nsColor: NSWorkspace.shared.fileLabelColors[l])
    }

    var body: some View {
        ToolShell(title: "Quick Sort", close: close) {
            VStack(spacing: 10) {
                ZStack {
                    Color.black.opacity(0.88)
                    if let img = images[index] { Image(nsImage: img).resizable().scaledToFit() } else { ProgressView().controlSize(.small) }
                    VStack {
                        HStack {
                            Text(urls[index].lastPathComponent).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.black.opacity(0.45)))
                            Spacer()
                            Text("\(index + 1) / \(urls.count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                        Spacer()
                    }.padding(10)
                    if marks[index] != .none {
                        Circle().fill(color(marks[index])).frame(width: 34, height: 34).overlay(Circle().stroke(Color.white, lineWidth: 3))
                            .shadow(color: .black.opacity(0.4), radius: 3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(14)
                    }
                }
                .frame(width: 860, height: 520).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                strip
                HStack(spacing: 18) {
                    ForEach([Mark.keep, .maybe, .reject], id: \.rawValue) { m in
                        HStack(spacing: 6) { Circle().fill(color(m)).frame(width: 12, height: 12); Text("\(count(m))").font(.system(size: 12).monospacedDigit()) }
                    }
                    Text("\(count(.none)) not sorted").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text(legend).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 860)
            .background(SortKeyCatcher { handle($0) })
        } footer: {
            Button("Select kept in Finder") {
                let kept = urls.indices.filter { marks[$0] == .keep }.map { urls[$0] }; let n = urls.count
                close(); TagSelect.select(kept, of: n)
            }.buttonStyle(PillButtonStyle()).disabled(count(.keep) == 0)
            Button(count(.reject) == 0 ? "Move rejects to the Trash" : "Move \(count(.reject)) reject\(count(.reject) == 1 ? "" : "s") to the Trash…") { trashRejects() }
                .buttonStyle(PillButtonStyle()).disabled(count(.reject) == 0)
        }
        .task { await readMarks() }
        .task(id: index) { await preload() }
    }

    /// Une barre fine : une case par fichier, de la couleur de sa marque ; on peut y cliquer ou la balayer.
    private var strip: some View {
        Canvas { ctx, size in
            let n = max(urls.count, 1), w = size.width / CGFloat(n)
            for i in 0..<urls.count {
                let r = CGRect(x: CGFloat(i) * w, y: i == index ? 0 : 4, width: max(w - (w > 3 ? 1 : 0), 1), height: i == index ? size.height : size.height - 8)
                ctx.fill(Path(r), with: .color(color(marks[i]).opacity(marks[i] == .none ? 0.35 : 1)))
                if i == index { ctx.stroke(Path(r.insetBy(dx: -1, dy: -1)), with: .color(Theme.text), lineWidth: 1.5) }
            }
        }
        .frame(width: 860, height: 18)
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in index = min(max(Int(v.location.x / 860 * CGFloat(urls.count)), 0), urls.count - 1) })
    }

    // MARK: Touches

    private func handle(_ e: NSEvent) -> Bool {
        if e.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return false }
        switch e.keyCode {
        case 123: index = max(0, index - 1); return true                                 // ←
        case 124, 49: index = min(urls.count - 1, index + 1); return true                // →, espace
        case 126: set(.keep); return true                                                // ↑
        case 125: set(.reject); return true                                              // ↓
        case 51, 117: set(.reject); return true                                          // Supprimer
        default: break
        }
        let s = AppSettings.shared
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        if ch == s.cullKeepKey { set(.keep); return true }
        if ch == s.cullMaybeKey { set(.maybe); return true }
        if ch == s.cullRejectKey { set(.reject); return true }
        if ch == s.cullClearKey { set(.none, advance: false); return true }
        return false
    }

    /// Marque le fichier courant (étiquette Finder écrite tout de suite) et passe au suivant.
    private func set(_ m: Mark, advance: Bool = true) {
        marks[index] = m
        let u = urls[index]
        Task.detached { FinderTags.set(u, label: m.label, managed: Self.managed) }
        if advance { index = min(urls.count - 1, index + 1) }
    }

    // MARK: Chargement

    private func readMarks() async {
        let list = urls
        let found: [Mark] = await Task.detached {
            list.map { u in
                let names = Set(TagSelect.tags(of: u).map(\.name))
                if names.contains(FinderTags.labelName(6)) { return .reject }
                if names.contains(FinderTags.labelName(2)) { return .keep }
                if names.contains(FinderTags.labelName(5)) { return .maybe }
                return .none
            }
        }.value
        marks = found
    }

    private func preload() async {
        for j in [index, index + 1, index + 2, index - 1] where urls.indices.contains(j) && images[j] == nil {
            let u = urls[j]
            let cg: CGImage? = await Task.detached { () -> CGImage? in
                if FileKind.detect(u) == .video {
                    if let f = await VideoFrames.native(u, at: 1) { return f }
                    return await VideoFrames.native(u, at: 0)
                }
                return (try? ImageEngine.load(u, maxSide: 2200))?.image
            }.value
            if let cg = cg { images[j] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        }
        for k in images.keys where abs(k - index) > 4 { images[k] = nil }                  // garde la mémoire raisonnable
    }

    private func trashRejects() {
        let rejected = urls.indices.filter { marks[$0] == .reject }
        let alert = NSAlert()
        alert.messageText = rejected.count == 1 ? "Move 1 rejected file to the Trash?" : "Move \(rejected.count) rejected files to the Trash?"
        alert.informativeText = "You can put them back from the Trash."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var failed = 0
        for i in rejected { do { try FileManager.default.trashItem(at: urls[i], resultingItemURL: nil) } catch { failed += 1 } }
        close()
        if failed == 0 { Toast.shared.done("Moved \(rejected.count) to the Trash", subtitle: "Open the Trash to put them back.") }
        else { Toast.shared.fail("Couldn't move \(failed) files", subtitle: "They may be in use or protected.") }
    }
}

/// Reçoit les touches du clavier pour la fenêtre (vue invisible qui prend le focus).
struct SortKeyCatcher: NSViewRepresentable {
    var onKey: (NSEvent) -> Bool

    final class KeyView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            DispatchQueue.main.async { w.makeFirstResponder(self) }
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self] _ in
                guard let self = self else { return }; w.makeFirstResponder(self)
            }
        }
        override func keyDown(with e: NSEvent) { if onKey?(e) != true { super.keyDown(with: e) } }
    }

    func makeNSView(context: Context) -> KeyView { let v = KeyView(); v.onKey = onKey; return v }
    func updateNSView(_ v: KeyView, context: Context) { v.onKey = onKey }
}
