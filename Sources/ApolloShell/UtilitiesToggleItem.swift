import AppKit
import ApolloShellCore
import SwiftUI

/// Ein Knopf aus der Anordnung, fertig fuer das Raster: was er zeigt, wie er
/// aussieht und was ein Klick tut. Die eine Stelle, an der jede Art ihren
/// Zustand und ihre Aktion bekommt - eine neue Art braucht hier einen Fall
/// (der Compiler verlangt ihn), in ApolloShellCore ihre Optionen und in
/// Nexus deren Editor.
@MainActor
struct UtilitiesToggleItem {
    enum Icon: Equatable {
        case symbol(String)
        case bluetooth
        /// Symbol der App mit dieser Bundle-ID.
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

    /// App-Knopf ohne eigenes Symbol: das App-Symbol (fehlt die App, das
    /// Ersatzsymbol). Ein eigenes Symbol, das es nicht gibt (Tippfehler in
    /// Nexus oder settings.json), zeigt das der Art - ein leerer Knopf
    /// saehe kaputt aus.
    static func icon(for toggle: UtilitiesToggle, look: QuickToggleLook) -> Icon {
        if let app = toggle.app, app.usesAppIcon, BarApps.info(for: app.bundleID) != nil {
            return .app(app.bundleID)
        }
        guard let symbol = look.symbol else { return .bluetooth }
        if UtilitiesSymbolCheck.exists(symbol) { return .symbol(symbol) }
        return toggle.kind.symbol.map(Icon.symbol) ?? .bluetooth
    }
}

/// Gibt es dieses SF Symbol? Gemerkt, weil das Raster bei jedem Zeichnen
/// fragt.
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

/// Die Kurzbefehle des Benutzers fuer Nexus. Liest NUR die Liste
/// (`shortcuts list`), fuehrt nichts aus - ausgefuehrt wird erst beim Klick
/// im Panel (`UtilitiesModel.runShortcut`).
enum UtilitiesShortcutCatalog {
    /// Eigener Prozess, nicht auf dem Hauptthread: meist nur Millisekunden,
    /// aber das Werkzeug kann beim ersten Aufruf nach dem Start laenger
    /// brauchen. Fehler: leere Liste.
    static func load() async -> [UtilitiesShortcut] {
        guard let result = await Subprocess.output(UtilitiesShortcuts.tool, UtilitiesShortcuts.listArguments),
              result.status == 0
        else { return [] }
        return UtilitiesShortcuts.parse(result.text)
    }
}
