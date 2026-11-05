import AppKit
import SwiftUI

/// Accès complet au disque : macOS ne permet pas de le demander par une fenêtre système. On l'explique une seule fois, on ouvre le bon réglage
/// et on montre l'app dans le Finder (pour la glisser dans la liste si elle n'y figure pas). Ensuite c'est réglé pour de bon.
enum FullDiskAccess {
    private static let probe = "/Library/Application Support/com.apple.TCC/TCC.db"      // lisible seulement avec l'accès complet au disque
    private static let askedKey = "fullDiskAccessAsked", grantedKey = "fullDiskAccessGranted", lostNoticeKey = "fullDiskAccessLostNotice"

    /// Vrai si l'app a l'accès complet au disque. (Tenter la lecture suffit aussi à faire apparaître l'app dans la liste des réglages.)
    static var isGranted: Bool {
        let fd = open(probe, O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }

    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
    }

    /// Au lancement : demande une seule fois (jamais plus, même si on refuse). Si l'accès avait été donné puis perdu (une mise à jour peut le
    /// réinitialiser), une simple notification propose de le rétablir, une fois par version.
    static func checkAtLaunch() {
        let d = UserDefaults.standard
        if isGranted { d.set(true, forKey: grantedKey); return }
        if d.bool(forKey: grantedKey) {
            let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
            guard d.string(forKey: lostNoticeKey) != v else { return }
            d.set(v, forKey: lostNoticeKey)
            Toast.shared.add(ToastItem(id: UUID(), phase: .done, title: L("Full Disk Access was reset"), subtitle: L("An update can reset it. Switch Mandarine back on."),
                                       action: ("Open Settings", { openSettings() }), sticky: true))
            return
        }
        guard !d.bool(forKey: askedKey) else { return }
        d.set(true, forKey: askedKey)
        let a = NSAlert()
        a.messageText = L("Give Mandarine access to all your files?")
        a.informativeText = L("Mandarine saves its results next to your files, in Desktop, Documents, Downloads or on external drives. Allow “Full Disk Access” once and macOS stops asking folder by folder.\n\nSystem Settings opens on the right page: switch Mandarine on (if it isn't listed, drag it in from the Finder window that appears). You can also do it later in Settings → General.")
        a.addButton(withTitle: L("Open System Settings"))
        a.addButton(withTitle: L("Not now"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            openSettings()
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }
}

/// Ligne des Réglages → General : état de l'accès complet au disque et raccourci vers le réglage.
struct FullDiskAccessRow: View {
    @State private var granted = FullDiskAccess.isGranted
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Full Disk Access"))
                Label(granted ? L("Allowed") : L("Not allowed yet"), systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(granted ? Color.green : Color.orange)
            }
            Spacer()
            if !granted {
                Button(L("Open System Settings")) { FullDiskAccess.openSettings(); NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
            }
        }
        .onAppear { granted = FullDiskAccess.isGranted }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in granted = FullDiskAccess.isGranted }
    }
}
