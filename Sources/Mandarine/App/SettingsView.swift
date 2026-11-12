import SwiftUI

/// Réglages : onglets à gauche, contenu à droite.
struct SettingsView: View {
    @ObservedObject var s = AppSettings.shared
    @ObservedObject var yt = YtDlpUpdater.shared
    @ObservedObject var installer = EngineInstaller.shared
    @ObservedObject var updater = Updater.shared
    @State private var tab: Tab

    enum Tab: String, CaseIterable, Identifiable {
        case general, appearance, wheel, petals, davinci, engines, updates, download
        var id: String { rawValue }
        var title: String {
            switch self { case .general: return L("General"); case .appearance: return L("Appearance"); case .wheel: return L("Wheel keys"); case .petals: return L("Petals"); case .davinci: return L("DaVinci"); case .engines: return L("Engines"); case .updates: return L("Updates"); case .download: return L("Download") }
        }
        var symbol: String {
            switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .wheel: return "circle.hexagongrid"; case .petals: return "leaf"; case .davinci: return "folder.badge.gearshape"; case .engines: return "wrench.and.screwdriver"; case .updates: return "arrow.triangle.2.circlepath"; case .download: return "arrow.down.circle" }
        }
    }

    init(tab: Tab = .general) { _tab = State(initialValue: tab) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 168)
            Divider()
            Form { content }.formStyle(.grouped)
        }
        .frame(width: 720, height: 540)
        .id(s.language)
        .task { await yt.refreshCurrent() }          // la version de yt-dlp est lue dès l'ouverture, quel que soit l'onglet
    }

    private static let checkFormat: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; f.doesRelativeDateFormatting = true; return f
    }()

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 9) {
                        Image(systemName: t.symbol).frame(width: 20)
                        Text(L(t.title))
                        Spacer()
                        if t == .updates, case .available = updater.state { Circle().fill(Theme.orange).frame(width: 8, height: 8) }
                    }
                    .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tab == t ? Theme.orange.opacity(0.22) : .clear))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            Text(L("Mandarine \(updater.currentVersion)")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general:
            Section(L("General")) {
                Toggle(L("Launch at login"), isOn: $s.launchAtLogin)
                Toggle(L("Show the welcome guide at startup"), isOn: $s.showWelcome)
                Toggle(L("Reveal results in Finder"), isOn: $s.revealAfterSave)
                Picker(L("Terminal"), selection: $s.terminalApp) {
                    ForEach(TerminalApp.allCases) { Text(L($0.title)).tag($0) }
                }
            }
            Section(L("Language")) {
                Picker(L("Language"), selection: $s.language) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text(L("System follows your Mac's language. New windows use the language right away.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Notifications")) {
                Picker(L("Style"), selection: $s.notificationStyle) { ForEach(NotificationStyle.allCases) { Text(L($0.title)).tag($0) } }.pickerStyle(.segmented)
                Text(L("Capsule: one slim line. Card: a little larger, with the buttons underneath.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Files")) {
                Picker(L("Original file"), selection: $s.replaceOriginal) { Text(L("Keep it")).tag(false); Text(L("Replace it")).tag(true) }.pickerStyle(.segmented)
                Text(L("Hold \(ReplaceMode.shared.symbol) when you click a tool's button or drop on a petal to do the opposite. A replaced original goes to the Trash, so you can still get it back."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FullDiskAccessRow()
            }
        case .appearance:
            Section(L("Appearance")) {
                Picker(L("Menu style"), selection: $s.appearance) { ForEach(MenuAppearance.allCases) { Text(L($0.title)).tag($0) } }
                Text(s.appearance == .wii ? L("A small Wii-style screen: every tool is a channel, with a clock, a pointer hand and a description line.") : s.appearance.isBubbles ? L("Tools are round bubbles floating around your logo.") : L("The radial wheel."))
                    .font(.caption).foregroundStyle(.secondary)
                if s.appearance == .wii {
                    Toggle(L("Show the screen in a TV"), isOn: $s.wiiTV)
                    Text(L("The Wii screen sits inside an old see-through TV. Turn it off to get the screen alone."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if s.appearance == .wheel {
                    Picker(L("Opening animation"), selection: $s.wheelEntrance) { ForEach(WheelEntrance.allCases) { Text(L($0.title)).tag($0) } }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("Accent color"))
                        Spacer()
                        ColorPicker("", selection: Binding(get: { s.accentColor }, set: { s.accentHex = NSColor($0).hexString }), supportsOpacity: false).labelsHidden()
                        if !s.isDefaultAccent { Button(L("Reset")) { s.accentHex = AppSettings.defaultAccent }.controlSize(.small) }
                    }
                    HStack(spacing: 8) {
                        ForEach(Self.accents, id: \.1) { name, hex in
                            Button { s.accentHex = hex } label: {
                                Circle().fill(Color(nsColor: NSColor(hex: hex)!)).frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.9), lineWidth: s.accentHex.uppercased() == hex ? 2.5 : 0).padding(-3))
                            }.buttonStyle(.plain).help(name)
                        }
                    }
                    Text(L("The highlight of the wheel, buttons and progress in every window. Windows already open keep their color.")).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L("Window style"), selection: $s.toolStyle) { ForEach(ToolStyle.available) { Text(L($0.title)).tag($0) } }
                }
            }
        case .wheel:
            Section(L("Wheel keys")) {
                Text(L("Start dragging a file, then tap a key. The wheel stays open until you drop."))
                    .font(.caption).foregroundStyle(.secondary)
                keyPicker(L("Convert formats"), $s.convertKey)
                keyPicker(L("File tools"), $s.toolsKey)
                keyPicker(L("File actions"), $s.actionsKey)
                if Set([s.convertKey, s.toolsKey, s.actionsKey]).count < 3 {
                    Label(L("Each wheel needs its own key."), systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            }
        case .petals:
            Section(L("Photos & videos")) {
                Toggle(L("Face Select"), isOn: $s.enableFaceSelect)
                Text(L("Pick people by their face. Needs a small model (\(FaceModel.sizeText)), downloaded once; see Engines.")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("Quick Sort"), isOn: $s.enableCull)
                Text(L("Go through the photos and videos full screen and mark each one Keep, Maybe or Reject with a key. The marks are Finder tags.")).font(.caption).foregroundStyle(.secondary)
                if s.enableCull {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Quick Sort keys — click one, then press the new key")).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            KeyRecorder(title: L("No · reject"), key: $s.cullRejectKey, taken: { cullKeyOwner($0, except: \.cullRejectKey) })
                            KeyRecorder(title: L("Maybe"), key: $s.cullMaybeKey, taken: { cullKeyOwner($0, except: \.cullMaybeKey) })
                            KeyRecorder(title: L("Yes · keep"), key: $s.cullKeepKey, taken: { cullKeyOwner($0, except: \.cullKeepKey) })
                            KeyRecorder(title: L("Clear"), key: $s.cullClearKey, taken: { cullKeyOwner($0, except: \.cullClearKey) })
                            Spacer()
                            Button("A · Z · E · R") { s.resetCullKeys() }.controlSize(.small)
                        }
                        Text(L("Arrow keys always work: ← → browse, ↑ keep, ↓ reject.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(L("Type Select"), isOn: $s.enableTypeSelect)
                Text(L("With several items selected, keep only some extensions, kinds, Finder tags, sizes or dates (JPG, MP4, red tag, bigger than 100 MB…).")).font(.caption).foregroundStyle(.secondary)
                Toggle(L("Document scan (photos)"), isOn: $s.enableScan)
                Text(L("Straighten and clean a photo of a sheet of paper, and save it as a PDF.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Conversion (⇧ wheel)")) {
                Toggle(L("Ringtone — audio & video"), isOn: $s.enableRingtone)
                Text(L("Adds a RINGTONE petal that saves the start of the sound as an iPhone ringtone (.m4r) with a short fade out.")).font(.caption).foregroundStyle(.secondary)
                if s.enableRingtone {
                    Stepper(L("Ringtone length: \(s.ringtoneSeconds) s"), value: $s.ringtoneSeconds, in: 5...40, step: 5)
                }
            }
            Section(L("Dragged text")) {
                Toggle(L("Wheel for selected text"), isOn: $s.enableTextDrag)
                Text(L("Drag a text selection (from Safari, Notes, Mail…) and tap a key: translate, summarize, read aloud, save as a file, make a QR code.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Folders")) {
                Toggle(L("Code"), isOn: $s.enableCode)
                Toggle(L("DaVinci project"), isOn: $s.enableDavinci)
            }
        case .davinci:
            Section(L("Project")) {
                Toggle(L("DaVinci project"), isOn: $s.enableDavinci)
                HStack { Text(L("Default project name")); TextField("", text: $s.davinciProjectName, prompt: Text(verbatim: "DaVinci Project")).labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading) }
                Toggle(L("Name the project after the dropped file when there is just one"), isOn: $s.davinciNameFromFile)
                Toggle(L("Move the dropped files into the right folder by default"), isOn: $s.davinciMoveFiles)
            }
            Section(L("Folder tree")) {
                Text(L("Ticked folders are created by default. Rename them, add subfolders, reorder them, and choose which folder receives the dropped videos, sounds or images.")).font(.caption).foregroundStyle(.secondary)
                ForEach($s.davinciFolders) { $f in
                    DaVinciFolderRow(folder: $f, depth: 0,
                                     remove: { s.davinciFolders.removeAll { $0.id == f.id } },
                                     move: { DaVinciLayout.move(&s.davinciFolders, id: f.id, by: $0) })
                }
                HStack {
                    Button { s.davinciFolders.append(DaVinciFolder(name: L("New folder"))) } label: { Label(L("Add a folder"), systemImage: "plus") }
                    Spacer()
                    Button(L("Restore the default folders")) { s.davinciFolders = DaVinciLayout.defaults }.controlSize(.small)
                }
            }
            Section(L("Preview")) {
                Text(verbatim: "\(s.davinciProjectName)/\n" + DaVinciLayout.treeText(s.davinciFolders)).font(.system(size: 11).monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .engines:
            Section(L("Engines")) {
                engine(L("ffmpeg (video, audio)"), FFmpeg.ffmpeg?.path, install: .ffmpeg)
                engine(L("ffprobe"), FFmpeg.ffprobe?.path, install: .ffmpeg)
                engine(L("cwebp (WebP)"), FFmpeg.locate("cwebp")?.path, install: .cwebp)
                engine(L("Face model (Face Select, \(FaceModel.sizeText))"), FaceModel.isInstalled ? FaceModel.file.path : nil, install: .faceModel)
                engine(L("yt-dlp (video and music links)"), YtDlp.url?.path)
                ytDlpUpdate
                engine(L("LibreOffice (slides)"), Converter.libreOffice?.path)
                HStack {
                    Text(L("Install manually (no Homebrew): drop ffmpeg and ffprobe in this folder.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Open Engines Folder")) {
                        try? FileManager.default.createDirectory(at: FFmpeg.enginesFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(FFmpeg.enginesFolder)
                    }
                }
            }
        case .download:
            DownloadTab()
        case .updates:
            Section(L("Updates")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Mandarine \(updater.currentVersion)"))
                        Text(L("Last checked: ") + (updater.lastChecked.map { Self.checkFormat.string(from: $0) } ?? L("never")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    switch updater.state {
                    case .checking, .downloading, .installing: ProgressView().controlSize(.small)
                    case .available: Button(L("Update now")) { Task { await updater.install() } }
                    default: Button(L("Check for updates")) { Task { await updater.check(userInitiated: true) } }
                    }
                }
                Toggle(L("Check for updates automatically"), isOn: $s.autoCheckUpdates)
                Toggle(L("Install them automatically when Mandarine is idle"), isOn: $s.autoInstallUpdates)
                Text(updater.isConfigured ? L("Updates come from the project's GitHub releases and are checked against a signature before they are installed.") : L("This build has no update source yet."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Version installée + bouton pour vérifier / installer la dernière version.
    private var ytDlpUpdate: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(YtDlp.url == nil ? L("Not installed") : (yt.current.isEmpty ? L("Reading the version…") : L("Version \(yt.current)"))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                switch yt.state {
                case .checking, .installing:
                    ProgressView().controlSize(.small)
                case .available(let v):
                    Button(YtDlp.url == nil ? L("Install yt-dlp \(v)") : L("Update to \(v)")) { Task { await yt.install() } }
                default:
                    Button(YtDlp.url == nil ? L("Install yt-dlp") : L("Check for updates")) { Task { await (YtDlp.url == nil ? yt.install() : yt.check()) } }
                }
            }
            switch yt.state {
            case .checking: Text(L("Checking…")).font(.caption).foregroundStyle(.secondary)
            case .installing: Text(L("Downloading and checking the official release…")).font(.caption).foregroundStyle(.secondary)
            case .upToDate: Label(L("yt-dlp is up to date."), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .available(let v): Text(L("A newer version is available: \(v).")).font(.caption).foregroundStyle(.orange)
            case .installed(let v): Label(L("Installed \(v). It is used from now on."), systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
            case .failed(let m): Text(L(m)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            case .idle: Text(L("Sites change often: if a download stops working, update yt-dlp here. The copy is kept in Mandarine's engines folder.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Qui utilise déjà cette touche dans le tri rapide ? (nil si personne)
    private func cullKeyOwner(_ k: String, except: KeyPath<AppSettings, String>) -> String? {
        let all: [(String, KeyPath<AppSettings, String>)] = [("reject", \.cullRejectKey), ("maybe", \.cullMaybeKey), ("keep", \.cullKeepKey), ("clear", \.cullClearKey)]
        return all.first { $0.1 != except && s[keyPath: $0.1] == k }?.0
    }

    static let accents: [(String, String)] = [("Orange", "F35B28"), ("Red", "E0343A"), ("Pink", "E8488B"), ("Purple", "8E5CD9"), ("Indigo", "4F5BD5"),
                                              ("Blue", "2D7FF0"), ("Teal", "14A39A"), ("Green", "3FA34D"), ("Gold", "E0A100"), ("Graphite", "5B6068")]

    private func keyPicker(_ title: String, _ b: Binding<TriggerKey>) -> some View {
        Picker(title, selection: b) { ForEach(TriggerKey.allCases) { Text(L($0.title)).tag($0) } }
    }

    /// Ligne d'un moteur : trouvé / introuvable, avec un bouton pour le télécharger s'il manque.
    private func engine(_ name: String, _ path: String?, install e: EngineInstaller.Engine? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(name))
                Spacer()
                if let e = e, path == nil {
                    switch installer.state(e) {
                    case .working(let p):
                        ProgressView(value: p).frame(width: 90)
                    default:
                        Button(L("Download")) { installer.install(e) }.controlSize(.small)
                    }
                }
                if e == .faceModel, path != nil {
                    Button(L("Remove")) { FaceModel.remove(); installer.objectWillChange.send() }.controlSize(.small)
                }
                Text(path == nil ? L("not found") : L("found")).foregroundStyle(path == nil ? .orange : .green).font(.caption)
            }
            if let e = e, case .failed(let m) = installer.state(e), path == nil {
                Text(L(m)).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Une ligne de l'éditeur d'arborescence DaVinci : case « coché par défaut », nom, type reçu, ordre, sous-dossier, suppression.
struct DaVinciFolderRow: View {
    @Binding var folder: DaVinciFolder
    let depth: Int
    let remove: () -> Void
    let move: (Int) -> Void

    private var receivesSymbol: String {
        switch folder.receives { case "video": return "film"; case "audio": return "waveform"; case "image": return "photo"; default: return "tray" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: $folder.on).labelsHidden().toggleStyle(.checkbox).help(L("Created by default"))
                TextField("", text: $folder.name, prompt: Text(L("Folder name"))).labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).font(.system(size: 12).monospaced())
                Menu {
                    Picker(L("Dropped files go here"), selection: $folder.receives) {
                        Text(L("Receives nothing")).tag(String?.none)
                        Text(L("Receives videos")).tag(String?.some("video"))
                        Text(L("Receives sounds")).tag(String?.some("audio"))
                        Text(L("Receives images")).tag(String?.some("image"))
                    }.pickerStyle(.inline).labelsHidden()
                } label: { Image(systemName: receivesSymbol) }
                    .menuStyle(.borderlessButton).frame(width: 34).help(L("Dropped files go here"))
                Button { move(-1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless).help(L("Move up"))
                Button { move(1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless).help(L("Move down"))
                if depth + 1 < DaVinciLayout.maxDepth {
                    Button { folder.children.append(DaVinciFolder(name: L("New folder"))) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless).help(L("Add a subfolder"))
                }
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless).help(L("Remove"))
            }
            .padding(.leading, CGFloat(depth) * 20)
            ForEach($folder.children) { $c in
                DaVinciFolderRow(folder: $c, depth: depth + 1,
                                 remove: { folder.children.removeAll { $0.id == c.id } },
                                 move: { DaVinciLayout.move(&folder.children, id: c.id, by: $0) })
            }
        }
    }
}
