import AppKit
import ApolloShellCore
import SwiftUI

/// One button out of the arrangement, ready for the grid: what it shows, how
/// it looks and what a click does. The one place where every kind gets its
/// state and its action - a new kind needs a case here (the compiler asks for
/// it), its options in ApolloShellCore and its editor in Nexus.
/// Nexus deren Editor.
@MainActor
struct UtilitiesToggleItem {
    enum Icon: Equatable {
        case symbol(String)
        case bluetooth
        /// The symbol of the app with this bundle ID.
        case app(String)
    }

    let icon: Icon
    let look: QuickToggleLook
    let action: () -> Void

    init(entry: UtilitiesToggleEntry, model: UtilitiesModel) {
        let look: QuickToggleLook
        switch entry.toggle {
        case .wifi:
            look = QuickToggles.wifi(powerOn: model.wifiOn)
            action = model.toggleWifi
        case .microphone:
            look = QuickToggles.microphone(muted: model.micMuted, settable: model.micSettable)
            action = model.toggleMicMute
        case .bluetooth:
            look = QuickToggles.bluetooth(powerOn: model.bluetoothOn)
            action = model.openBluetoothSettings
        case .darkMode:
            look = QuickToggles.darkMode(on: model.darkMode)
            action = model.toggleDarkMode
        case .nightShift:
            look = QuickToggles.nightShift(enabled: model.nightShift)
            action = model.toggleNightShift
        case .screenshot:
            look = QuickToggles.screenshot
            action = model.takeScreenshot
        case .showDesktop:
            look = QuickToggles.showDesktop(available: model.showDesktopAvailable)
            action = model.showDesktop
        case .colorPicker:
            look = QuickToggles.colorPicker
            action = model.pickColor
        case .lockScreen:
            look = QuickToggles.lockScreen
            action = model.lockScreen
        case .settings:
            look = QuickToggles.settings
            action = model.openSettings
        case .displaySleep:
            look = QuickToggles.displaySleep
            action = model.sleepDisplay
        case .hideApps(let options):
            look = QuickToggles.hideApps(options)
            action = { model.hideApps(options) }
        case .openApp(let options):
            let info = BarApps.info(for: options.bundleID.trimmingCharacters(in: .whitespaces))
            look = QuickToggles.openApp(options, appName: info?.name)
            action = { model.openApp(options) }
        case .openLink(let options):
            look = QuickToggles.openLink(options)
            action = { model.openLink(options) }
        case .runShortcut(let options):
            look = QuickToggles.runShortcut(options)
            action = { model.runShortcut(options) }
        }
        self.look = look
        icon = Self.icon(for: entry.toggle, look: look)
    }

    /// An app button without a symbol of its own: the app symbol (when the app
    /// is missing, the stand-in). A symbol of its own that does not exist (a
    /// typo in Nexus or settings.json) shows the one of the kind - an empty
    /// button would look broken.
    static func icon(for toggle: UtilitiesToggle, look: QuickToggleLook) -> Icon {
        if let app = toggle.app, app.usesAppIcon, BarApps.info(for: app.bundleID) != nil {
            return .app(app.bundleID)
        }
        guard let symbol = look.symbol else { return .bluetooth }
        if UtilitiesSymbolCheck.exists(symbol) { return .symbol(symbol) }
        return toggle.kind.symbol.map(Icon.symbol) ?? .bluetooth
    }
}

/// Does this SF Symbol exist? Remembered, because the grid asks on every
/// drawing.
@MainActor
enum UtilitiesSymbolCheck {
    private static var cache: [String: Bool] = [:]

    static func exists(_ name: String) -> Bool {
        if let hit = cache[name] { return hit }
        let found = !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        cache[name] = found
        return found
    }
}

/// The shortcuts of the user for Nexus. Reads ONLY the list
/// (`shortcuts list`), runs nothing - running only happens on a click in the
/// panel (`UtilitiesModel.runShortcut`).
enum UtilitiesShortcutCatalog {
    /// A process of its own, not on the main thread: usually only
    /// milliseconds, but the tool can take longer on the first call after the
    /// start. An error: an empty list.
    static func load() async -> [UtilitiesShortcut] {
        guard let result = await Subprocess.output(UtilitiesShortcuts.tool, UtilitiesShortcuts.listArguments),
              result.status == 0
        else { return [] }
        return UtilitiesShortcuts.parse(result.text)
    }
}
