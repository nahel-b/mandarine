import SwiftUI
import AppKit

/// Les nouveautés de chaque version, affichées une fois après une mise à jour (et depuis le menu de la barre de menus).
struct WhatsNewItem { let symbol: String; let title: String; let text: String }
struct WhatsNewRelease { let version: String; let headline: String; let items: [WhatsNewItem] }

enum WhatsNew {
    /// À compléter à chaque version (la plus récente d'abord) : c'est ce que voit l'utilisateur après la mise à jour.
    static var releases: [WhatsNewRelease] { [
        WhatsNewRelease(version: "1.8.1", headline: L("Streams (.m3u8) as videos"), items: [
            WhatsNewItem(symbol: "play.rectangle.on.rectangle", title: L("Open .m3u8 videos"),
                         text: L("A local HLS playlist (.m3u8 with its segments) is now a video for Mandarine: convert it to MP4, GIF, MP3… and use the video tools such as frame capture. Results are regular files, never .m3u8. If a segment is missing or on the web, you get a clear message.")),
        ]),
        WhatsNewRelease(version: "1.8.0", headline: L("Your own DaVinci folders"), items: [
            WhatsNewItem(symbol: "folder.badge.gearshape", title: L("Customize the DaVinci tree"),
                         text: L("Settings → DaVinci: rename every folder and subfolder, add or remove some, reorder them, and tick the ones created by default. You can also choose which folder receives dropped videos, sounds or images, and the default project name.")),
        ]),
        WhatsNewRelease(version: "1.7.0", headline: L("Apple ProRes and big batches"), items: [
            WhatsNewItem(symbol: "film.stack", title: L("Apple ProRes"),
                         text: L("A PRORES petal on the video wheel makes a ProRes 422 HQ .mov, ready for editing. Export Video also has an Apple ProRes codec with its profiles (Proxy, LT, 422, 422 HQ, 4444). Interlaced MPEG from camcorders and PowerShots is deinterlaced.")),
            WhatsNewItem(symbol: "square.stack.3d.up", title: L("Batches keep going"),
                         text: L("In a batch, a file that fails no longer stops the others: you get “Saved 8 of 10 — 2 failed”. The Mac also stays awake while Mandarine is working.")),
            WhatsNewItem(symbol: "cursorarrow.rays", title: L("All your files on the wheel"),
                         text: L("When you drag a large selection from Finder, Mandarine now picks up every file, not just the first few.")),
        ]),
        WhatsNewRelease(version: "1.6.0", headline: L("Mandarine in French"), items: [
            WhatsNewItem(symbol: "globe", title: L("Choose your language"),
                         text: L("Settings → General → Language: English, Français, or follow your Mac. Menus, tools, notifications and guides all switch.")),
        ]),
        WhatsNewRelease(version: "1.5.1", headline: L("Swipe to dismiss"), items: [
            WhatsNewItem(symbol: "hand.draw", title: L("Swipe notifications away"),
                         text: L("Swipe a finished notification to the right with two fingers on the trackpad to dismiss it.")),
        ]),
        WhatsNewRelease(version: "1.5.0", headline: L("Keep the original, or replace it"), items: [
            WhatsNewItem(symbol: "arrow.triangle.2.circlepath", title: L("Replace the original"),
                         text: L("Settings → General: results keep your original (default) or replace it. Hold ⌥ when you click a tool's button or drop on a petal to do the opposite — the button even changes to “Replace original”. Drop on a tool with ⌥ held and its window opens in replace mode (⌥-click then keeps both). The old file goes to the Trash.")),
            WhatsNewItem(symbol: "return", title: L("Return runs the tool"),
                         text: L("In a tool window, press Return instead of clicking the main button.")),
            WhatsNewItem(symbol: "bell.badge", title: L("Decide after the fact"),
                         text: L("A finished job has a “Replace original” button in its notification, and “Undo” puts everything back.")),
            WhatsNewItem(symbol: "circle.hexagongrid", title: L("A badge while you drag"),
                         text: L("With ⌥ held, the wheel, the bubbles and the Wii screen say “Replaces the original” before you drop.")),
            WhatsNewItem(symbol: "rectangle.stack", title: L("New notifications"),
                         text: L("A slimmer capsule by default, with the file icon circled by a green arc as the job advances; or a larger card with the buttons underneath (Settings → General → Notifications). The “done” sound now plays in every menu style.")),
            WhatsNewItem(symbol: "sparkles", title: L("What's New"),
                         text: L("This window appears once after each update. You can reopen it from the menu bar icon.")),
        ]),
        WhatsNewRelease(version: "1.4.1", headline: L("HDR videos and little touches"), items: [
            WhatsNewItem(symbol: "film", title: L("HDR videos export correctly"),
                         text: L("An iPhone HDR clip is now exported as 10-bit HEVC instead of a gray, washed-out H.264.")),
            WhatsNewItem(symbol: "hand.point.up.left", title: L("Buttons that react"),
                         text: L("In the Wii screen, buttons and checkboxes grow slightly under the pointer, with new hover and “back to the menu” sounds.")),
        ]),
        WhatsNewRelease(version: "1.4.0", headline: L("Tools live inside the Wii screen"), items: [
            WhatsNewItem(symbol: "tv", title: L("Wii screen, all the way"),
                         text: L("Drop on a tool and the screen zooms into the tile, then the tool opens in a channel panel with “Wii Menu” to go back. CRT look, a hand that closes when you click, and a sound for everything.")),
            WhatsNewItem(symbol: "paintbrush", title: L("Eraser and brush"),
                         text: L("Remove Background lets you paint away what should be transparent, or paint back what was cut by mistake.")),
            WhatsNewItem(symbol: "scissors", title: L("Trim Audio, several times"),
                         text: L("Click the waveform to place the cursor, and tick “Keep trimming” to cut another part without leaving the tool.")),
            WhatsNewItem(symbol: "lock.open", title: L("Full Disk Access, once"),
                         text: L("Mandarine asks once so macOS stops asking folder by folder. Settings → General shows the state.")),
        ]),
        WhatsNewRelease(version: "1.3.9", headline: L("Download counts"), items: [
            WhatsNewItem(symbol: "chart.bar", title: L("Downloads per version"),
                         text: L("Settings → Download shows how many times each release was downloaded (disk image and updates).")),
        ]),
        WhatsNewRelease(version: "1.3.8", headline: L("All features, a shorter guide"), items: [
            WhatsNewItem(symbol: "square.grid.2x2", title: L("All features"),
                         text: L("A window that lists everything Mandarine can do, file type by file type, with a search field. It is built from the real wheels, so it is always up to date.")),
            WhatsNewItem(symbol: "questionmark.circle", title: L("A shorter guide"),
                         text: L("The welcome guide went from ten pages to four; the details live in All features.")),
            WhatsNewItem(symbol: "arrow.down.circle", title: L("Download tab"),
                         text: L("Settings → Download lists the published versions and downloads any of them.")),
        ]),
        WhatsNewRelease(version: "1.3.7", headline: L("Web pages and time left"), items: [
            WhatsNewItem(symbol: "link", title: L("Save a web page"),
                         text: L("Drag a link and use the PDF, MARKDOWN or SCREENSHOT petals to keep the page as a PDF, a Markdown text or a full-page picture.")),
            WhatsNewItem(symbol: "clock", title: L("Time left"),
                         text: L("Long jobs show “About 3 min left” in their notification.")),
        ]),
        WhatsNewRelease(version: "1.3.6", headline: L("Draggable notifications"), items: [
            WhatsNewItem(symbol: "hand.draw", title: L("Take the file from the notification"),
                         text: L("Drag a finished notification onto a Finder window, a message, or back onto the wheel. Notifications without a file carry their text, and stay a little longer.")),
            WhatsNewItem(symbol: "text.alignleft", title: L("Shorter titles"),
                         text: L("Titles are short; the details are in the description.")),
        ]),
        WhatsNewRelease(version: "1.3.5", headline: L("Fixes"), items: [
            WhatsNewItem(symbol: "wrench.and.screwdriver", title: L("Small fixes"), text: L("Stability and polish.")),
        ]),
        WhatsNewRelease(version: "1.3.4", headline: L("Compress a batch into a ZIP"), items: [
            WhatsNewItem(symbol: "doc.zipper", title: L("One archive for a batch"),
                         text: L("Compress can put several files into a single ZIP, and the update notification is simpler.")),
        ]),
        WhatsNewRelease(version: "1.3.3", headline: L("Batches and faces"), items: [
            WhatsNewItem(symbol: "list.number", title: L("One notification per batch"),
                         text: L("Converting ten files shows one line with “3 of 10 done” instead of ten.")),
            WhatsNewItem(symbol: "face.smiling", title: L("Face Select remembers"),
                         text: L("Faces you already picked are remembered, and files can be dragged from the Finder more reliably.")),
        ]),
        WhatsNewRelease(version: "1.3.2", headline: L("Engines without Homebrew"), items: [
            WhatsNewItem(symbol: "arrow.down.circle", title: L("One-click engines"),
                         text: L("Mandarine downloads ffmpeg, yt-dlp and the face model itself — no Homebrew, no Terminal. Updates found while the app was busy resume at the next launch.")),
        ]),
        WhatsNewRelease(version: "1.3.1", headline: L("Fixes"), items: [
            WhatsNewItem(symbol: "wrench.and.screwdriver", title: L("Small fixes"), text: L("Stability and polish.")),
        ]),
        WhatsNewRelease(version: "1.3.0", headline: L("Bubbles"), items: [
            WhatsNewItem(symbol: "circle.circle", title: L("Bubbles menu"),
                         text: L("A new menu style in Settings: bubbles around a stack of your files, with its own entrance animation.")),
        ]),
        WhatsNewRelease(version: "1.2.0", headline: L("Type Select"), items: [
            WhatsNewItem(symbol: "line.3.horizontal.decrease.circle", title: L("Type Select"),
                         text: L("Select files by extension, kind, Finder tag, size or date inside your selection. Tool windows also get new looks in Settings.")),
        ]),
        WhatsNewRelease(version: "1.1.2", headline: L("One update check a day"), items: [
            WhatsNewItem(symbol: "arrow.triangle.2.circlepath", title: L("Quieter updates"),
                         text: L("Mandarine checks for updates once a day, also after your Mac wakes up.")),
        ]),
        WhatsNewRelease(version: "1.1.1", headline: L("Fixes"), items: [
            WhatsNewItem(symbol: "wrench.and.screwdriver", title: L("yt-dlp version"), text: L("Settings shows the right yt-dlp version.")),
        ]),
        WhatsNewRelease(version: "1.1.0", headline: L("Scan and text tools"), items: [
            WhatsNewItem(symbol: "doc.viewfinder", title: L("Scan Document"),
                         text: L("Straighten a photo of a sheet of paper, clean it up and save it as a PDF.")),
            WhatsNewItem(symbol: "character.bubble", title: L("Translate and Summarize"),
                         text: L("Drag some text onto the wheel to translate it or summarize it on your Mac.")),
        ]),
        WhatsNewRelease(version: "1.0.1", headline: L("Fixes"), items: [
            WhatsNewItem(symbol: "wrench.and.screwdriver", title: L("Build fix"), text: L("The release is now built on the latest macOS.")),
        ]),
        WhatsNewRelease(version: "1.0.0", headline: L("Mandarine"), items: [
            WhatsNewItem(symbol: "hand.draw", title: L("Drag, tap, drop"),
                         text: L("Drag a file, tap ⇧ ⌘ or ⌃ and a wheel appears under your cursor: convert, edit, or act. Everything runs on your Mac.")),
        ]),
    ] }

    /// Versions à présenter : celles plus récentes que la dernière vue, sans dépasser la version installée (au plus trois).
    static func pending(since last: String, current: String) -> [WhatsNewRelease] {
        Array(releases.filter { YtDlpUpdater.isNewer($0.version, than: last) && !YtDlpUpdater.isNewer($0.version, than: current) }.prefix(3))
    }

    /// Au lancement : montre les nouveautés une fois après une mise à jour. Première installation : rien (le guide d'accueil suffit).
    static func showIfNeeded() {
        let d = UserDefaults.standard
        let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        var last = d.string(forKey: "lastSeenVersion") ?? ""
        // Version d'avant cette fonction : si l'app a déjà servi (réglages ou vérifications de mise à jour présents), c'est une mise à jour, pas une première installation.
        if last.isEmpty, ["lastUpdateCheck", "fullDiskAccessAsked", "showWelcome", "appearance"].contains(where: { d.object(forKey: $0) != nil }) { last = "1.3.9" }
        guard !last.isEmpty, last != current else { d.set(current, forKey: "lastSeenVersion"); return }
        let list = pending(since: last, current: current)
        if !list.isEmpty { WhatsNewWindowController.show(highlighting: list.map(\.version)) }
        d.set(current, forKey: "lastSeenVersion")          // noté une fois la fenêtre demandée (et pas avant, pour ne rien perdre si le lancement échoue)
    }
}

struct WhatsNewView: View {
    let releases: [WhatsNewRelease]
    var highlighted: Set<String> = []          // versions apparues depuis la dernière fois : repérées par une pastille « NEW »
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 46, height: 46)
                            Text(L("What's new")).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                        }
                        Text(highlighted.isEmpty ? L("Every version, newest first.") : L("The new versions are marked; scroll down for the earlier ones.")).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    ForEach(releases, id: \.version) { r in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Text(L(r.version)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(highlighted.isEmpty || highlighted.contains(r.version) ? Theme.orange : Color(white: 0.62)))
                                Text(L(r.headline)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                                if highlighted.contains(r.version) { Text(L("NEW")).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(Theme.orange) }
                            }
                            ForEach(r.items, id: \.title) { it in
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: it.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.orange)
                                        .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.orange.opacity(0.13)))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(L(it.title)).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
                                        Text(L(it.text)).font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true).lineSpacing(1.5)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 38).padding(.top, 44).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L("See all features")) { close(); FeaturesWindowController.show() }.buttonStyle(PillButtonStyle())
                Spacer()
                Button(L("Got it")) { close() }.buttonStyle(PillButtonStyle(prominent: true))
            }
            .padding(.horizontal, 38).padding(.vertical, 16)
            .overlay(Divider().opacity(0.6), alignment: .top)
        }
        .frame(width: 600, height: 620)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    static let shared = WhatsNewWindowController()
    private var window: NSWindow?

    /// Toutes les versions, la plus récente d'abord ; `highlighting` : celles à signaler comme nouvelles.
    static func show(highlighting: [String] = []) { shared.present(WhatsNew.releases, highlighted: Set(highlighting)) }

    private func present(_ list: [WhatsNewRelease], highlighted: Set<String>) {
        window?.close()
        let host = NSHostingView(rootView: WhatsNewView(releases: list, highlighted: highlighted, close: { [weak self] in self?.window?.close() }))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .white
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        // juste après une mise à jour l'app se relance en arrière-plan : la fenêtre se place au-dessus de tout un instant pour qu'on la voie
        w.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak w] in w?.level = .normal }
    }

    func windowWillClose(_ notification: Notification) { window?.contentView = nil; window = nil }
}

/// Astuce affichée une seule fois, à la première ouverture d'un outil qui peut remplacer l'original.
enum ReplaceTip {
    private static let key = "replaceTipShown"
    static func maybeShow(for id: ToolID) {
        guard id.replacesOriginal, !ToolRegistry.isDirect(id), !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            let tid = UUID()
            let sym = ReplaceMode.shared.symbol
            Toast.shared.add(ToastItem(id: tid, phase: .done, title: L("Tip: keep or replace"),
                                       subtitle: L("Hold \(sym) while you click the button to replace the original instead of keeping both — the old file goes to the Trash. The default is in Settings → General."),
                                       action: ("Got it", { Toast.shared.remove(tid) }), sticky: true))
        }
    }
}
