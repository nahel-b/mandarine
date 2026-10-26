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
    @Published var enableTagSelect: Bool { didSet { d.set(enableTagSelect, forKey: "enableTagSelect") } }
    @Published var enableFaceSelect: Bool { didSet { d.set(enableFaceSelect, forKey: "enableFaceSelect") } }
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
        enableTagSelect = d.object(forKey: "enableTagSelect") as? Bool ?? true
        enableFaceSelect = d.object(forKey: "enableFaceSelect") as? Bool ?? true
        enableCode = d.object(forKey: "enableCode") as? Bool ?? true
        enableDavinci = d.object(forKey: "enableDavinci") as? Bool ?? true
        launchAtLogin = d.bool(forKey: "launchAtLogin")
    }

    func key(for mode: WheelMode) -> TriggerKey {
        switch mode {
        case .convert: return convertKey
        case .tools: return toolsKey
        case .actions: return actionsKey
        }
    }
}
