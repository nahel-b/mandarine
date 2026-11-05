import AppKit
import SwiftUI

/// « Remplacer le fichier d'origine ou le garder » : le réglage (Réglages → General) s'inverse tant qu'une touche est maintenue au moment où l'on clique
/// sur le bouton d'un outil ou où l'on dépose sur un pétale. La touche est ⌥, sauf si une roue l'utilise déjà (alors la première touche libre).
final class ReplaceMode: ObservableObject {
    static let shared = ReplaceMode()
    @Published private(set) var held = false
    private var timer: Timer?
    private var users = 0
    private var capturedAt = Date.distantPast
    private var capturedHeld = false
    private let settings = AppSettings.shared

    /// Touche d'inversion.
    var flag: NSEvent.ModifierFlags {
        let used = Set(WheelMode.allCases.map { settings.key(for: $0).flag.rawValue })
        return [NSEvent.ModifierFlags.option, .control, .shift, .command].first { !used.contains($0.rawValue) } ?? .option
    }
    var symbol: String {
        switch flag { case .control: return "⌃"; case .shift: return "⇧"; case .command: return "⌘"; default: return "⌥" }
    }

    /// Ce qui s'appliquerait si l'on agissait maintenant (d'après la touche telle qu'elle a été lue en dernier : voir `refresh`).
    var effective: Bool { settings.replaceOriginal != held }

    /// Relit la touche (sans autorisation particulière : simple lecture de l'état du clavier).
    func refresh() {
        let h = NSEvent.modifierFlags.contains(flag)
        if h != held { held = h }
    }

    /// Mémorise l'état de la touche à l'instant d'un dépôt : l'outil ou la conversion démarre un peu après, et la touche peut déjà être relâchée.
    func capture() { refresh(); capturedHeld = held; capturedAt = Date() }

    /// (test) comme si la touche d'inversion avait été tenue au moment d'un dépôt.
    func debugCapture(held: Bool) { capturedHeld = held; capturedAt = Date() }

    /// Le bouton d'un outil qu'on est en train de cliquer : sa base (réglage, ou son inverse si la fenêtre a été ouverte par un dépôt avec la touche) sert de référence.
    var clickBase: Bool?

    /// Base d'une fenêtre d'outil qui vient de s'ouvrir : si on l'a ouverte en déposant avec la touche d'inversion, elle remplace par défaut (et la touche, au clic, repasse à « garder »).
    func baseForNewWindow() -> Bool {
        Date().timeIntervalSince(capturedAt) < 1.5 ? settings.replaceOriginal != capturedHeld : settings.replaceOriginal
    }

    /// À appeler au moment où un travail est ajouté : l'état capturé au dépôt s'il est tout récent, sinon la touche telle qu'elle est maintenant.
    func effectiveNow() -> Bool {
        if let b = clickBase { refresh(); return b != held }
        if Date().timeIntervalSince(capturedAt) < 1.5 { return settings.replaceOriginal != capturedHeld }
        refresh()
        return effective
    }

    /// Tant qu'une fenêtre d'outil est ouverte, la touche est relevée régulièrement : le texte du bouton change dès qu'on l'enfonce.
    func begin() {
        users += 1
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func end() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil; held = false }
    }
}

private struct ReplaceBaseKey: EnvironmentKey { static let defaultValue: Bool? = nil }
extension EnvironmentValues {
    /// Mode de remplacement par défaut de la fenêtre d'outil (nil : le réglage).
    var replaceBase: Bool? { get { self[ReplaceBaseKey.self] } set { self[ReplaceBaseKey.self] = newValue } }
}

/// Bouton principal d'un outil qui modifie un fichier : son texte devient « Replace original » (et il passe en évidence) tant que le remplacement est actif.
/// Entrée le déclenche (sauf `isDefault: false`).
struct ReplaceButton: View {
    let title: String
    var prominent = false
    var isDefault = true
    let action: () -> Void
    @ObservedObject private var mode = ReplaceMode.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.replaceBase) private var windowBase

    init(_ title: String, prominent: Bool = false, isDefault: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.prominent = prominent; self.isDefault = isDefault; self.action = action
    }

    private var base: Bool { windowBase ?? settings.replaceOriginal }

    var body: some View {
        let replacing = base != mode.held
        let button = Button {
            ReplaceMode.shared.clickBase = base            // le travail lancé par ce clic part de la base de cette fenêtre
            action()
            ReplaceMode.shared.clickBase = nil
        } label: {
            if replacing { Label("Replace original", systemImage: "arrow.triangle.2.circlepath") } else { Text(title) }
        }
        .buttonStyle(PillButtonStyle(prominent: replacing || prominent))
        .help(replacing ? "The result replaces the original; the original goes to the Trash. Hold \(mode.symbol) to keep both instead." : "Hold \(mode.symbol) to replace the original instead of keeping both.")
        if isDefault { button.keyboardShortcut(.defaultAction) } else { button }
    }
}
