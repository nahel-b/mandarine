import AppKit
import SwiftUI
import ServiceManagement

enum TriggerKey: String, CaseIterable, Identifiable {
    case shift, command, control, option
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        }
    }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        }
    }
}

enum MenuAppearance: String, CaseIterable, Identifiable {
    case wheel, wii
    var id: String { rawValue }
    var title: String { self == .wheel ? "Wheel" : "Wii menu" }
}

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal, iterm
    var id: String { rawValue }
    var title: String { self == .terminal ? "Terminal" : "iTerm2" }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var convertKey: TriggerKey { didSet { d.set(convertKey.rawValue, forKey: "convertKey") } }
    @Published var toolsKey: TriggerKey { didSet { d.set(toolsKey.rawValue, forKey: "toolsKey") } }
    @Published var actionsKey: TriggerKey { didSet { d.set(actionsKey.rawValue, forKey: "actionsKey") } }
    @Published var terminalApp: TerminalApp { didSet { d.set(terminalApp.rawValue, forKey: "terminalApp") } }
    @Published var revealAfterSave: Bool { didSet { d.set(revealAfterSave, forKey: "revealAfterSave") } }
    @Published var appearance: MenuAppearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var showWelcome: Bool { didSet { d.set(showWelcome, forKey: "showWelcome") } }
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    @Published var autoInstallUpdates: Bool { didSet { d.set(autoInstallUpdates, forKey: "autoInstallUpdates") } }
    // Pétales facultatifs de la roue ⌘
    @Published var enableFaceSelect: Bool { didSet { d.set(enableFaceSelect, forKey: "enableFaceSelect") } }
    // Touches du tri rapide : A = non (rejeter), Z = je ne sais pas (peut-être), E = oui (garder), R = effacer la marque
    @Published var cullKeepKey: String { didSet { d.set(cullKeepKey, forKey: "cullKeepKey") } }
    @Published var cullMaybeKey: String { didSet { d.set(cullMaybeKey, forKey: "cullMaybeKey") } }
    @Published var cullRejectKey: String { didSet { d.set(cullRejectKey, forKey: "cullRejectKey") } }
    @Published var cullClearKey: String { didSet { d.set(cullClearKey, forKey: "cullClearKey") } }
    @Published var enableTypeSelect: Bool { didSet { d.set(enableTypeSelect, forKey: "enableTypeSelect") } }
    /// Couleur de tinte (hexadécimal sans #) : orange Mandarine par défaut.
    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "accentHex") } }
    @Published var toolStyle: ToolStyle { didSet { d.set(toolStyle.rawValue, forKey: "toolStyle") } }
    @Published var enableCull: Bool { didSet { d.set(enableCull, forKey: "enableCull") } }
    @Published var enableScan: Bool { didSet { d.set(enableScan, forKey: "enableScan") } }
    @Published var enableRingtone: Bool { didSet { d.set(enableRingtone, forKey: "enableRingtone") } }
    @Published var ringtoneSeconds: Int { didSet { d.set(ringtoneSeconds, forKey: "ringtoneSeconds") } }
    @Published var enableTextDrag: Bool { didSet { d.set(enableTextDrag, forKey: "enableTextDrag") } }
    @Published var enableCode: Bool { didSet { d.set(enableCode, forKey: "enableCode") } }
    @Published var enableDavinci: Bool { didSet { d.set(enableDavinci, forKey: "enableDavinci") } }
    @Published var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "launchAtLogin")
            if #available(macOS 13.0, *) {
                do { launchAtLogin ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                catch { NSLog("Launch at login: \(error)") }
            }
        }
    }

    private init() {
        convertKey = TriggerKey(rawValue: d.string(forKey: "convertKey") ?? "") ?? .shift
        toolsKey = TriggerKey(rawValue: d.string(forKey: "toolsKey") ?? "") ?? .command
        actionsKey = TriggerKey(rawValue: d.string(forKey: "actionsKey") ?? "") ?? .control
        terminalApp = TerminalApp(rawValue: d.string(forKey: "terminalApp") ?? "") ?? .terminal
        revealAfterSave = d.object(forKey: "revealAfterSave") as? Bool ?? false
        appearance = MenuAppearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .wheel
        showWelcome = d.object(forKey: "showWelcome") as? Bool ?? true
        autoCheckUpdates = d.object(forKey: "autoCheckUpdates") as? Bool ?? true
        autoInstallUpdates = d.object(forKey: "autoInstallUpdates") as? Bool ?? true
        enableFaceSelect = d.object(forKey: "enableFaceSelect") as? Bool ?? true
        accentHex = ProcessInfo.processInfo.environment["MANDARINE_ACCENT"] ?? d.string(forKey: "accentHex") ?? AppSettings.defaultAccent
        toolStyle = ToolStyle(rawValue: d.string(forKey: "toolStyle") ?? "").flatMap { ToolStyle.available.contains($0) ? $0 : nil } ?? .capsule
        cullKeepKey = d.string(forKey: "cullKeepKey") ?? "e"
        cullMaybeKey = d.string(forKey: "cullMaybeKey") ?? "z"
        cullRejectKey = d.string(forKey: "cullRejectKey") ?? "a"
        cullClearKey = d.string(forKey: "cullClearKey") ?? "r"
        enableTypeSelect = d.object(forKey: "enableTypeSelect") as? Bool ?? true
        enableCull = d.object(forKey: "enableCull") as? Bool ?? true
        enableScan = d.object(forKey: "enableScan") as? Bool ?? true
        enableRingtone = d.object(forKey: "enableRingtone") as? Bool ?? true
        ringtoneSeconds = (d.object(forKey: "ringtoneSeconds") as? Int) ?? 30
        enableTextDrag = d.object(forKey: "enableTextDrag") as? Bool ?? true
        enableCode = d.object(forKey: "enableCode") as? Bool ?? true
        enableDavinci = d.object(forKey: "enableDavinci") as? Bool ?? true
        launchAtLogin = d.bool(forKey: "launchAtLogin")
    }

    static let defaultAccent = "F35B28"
    var isDefaultAccent: Bool { accentHex.uppercased() == Self.defaultAccent }
    var accentNSColor: NSColor { NSColor(hex: accentHex) ?? NSColor(hex: Self.defaultAccent)! }
    var accentColor: Color { Color(nsColor: accentNSColor) }

    func resetCullKeys() { cullKeepKey = "e"; cullMaybeKey = "z"; cullRejectKey = "a"; cullClearKey = "r" }

    func key(for mode: WheelMode) -> TriggerKey {
        switch mode {
        case .convert: return convertKey
        case .tools: return toolsKey
        case .actions: return actionsKey
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return AppSettings.defaultAccent }
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    /// Mélange avec une autre couleur (0 = soi-même, 1 = l'autre).
    func mixed(with o: NSColor, _ t: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = o.usingColorSpace(.sRGB) else { return self }
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t, green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
}
