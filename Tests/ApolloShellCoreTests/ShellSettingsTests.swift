import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: reading and writing settings.json")
struct ShellSettingsTests {
    @Test("missing file: fresh install, otherwise defaults = previous behavior")
    func missingFile() {
        let settings = ShellSettings.load(from: nil)
        #expect(settings == ShellSettings.firstLaunch)
        #expect(settings.bar == ShellSettings().bar)
        #expect(settings.toasts == ShellSettings().toasts)
        #expect(settings.utilities == ShellSettings().utilities)
        #expect(settings.dashboard == ShellSettings().dashboard)
        #expect(settings.bar.layout == BarPreset.caelestia.layout)
        #expect(settings.bar.layout[id: "clock"]?.module.clock == BarClockOptions(showIcon: true, showDate: false))
        #expect(settings.toasts.chargingChanged && settings.background.desktopClock)
    }

    @Test("broken, empty, wrong type, or unknown: defaults", arguments: [
        "", "kaputt", "[]", "{}", #"{"bar":5,"toasts":"nein","background":null}"#, #"{"unbekannt":true}"#,
    ])
    func brokenGivesDefaults(json: String) {
        #expect(ShellSettings.load(from: Data(json.utf8)) == ShellSettings())
    }

    @Test("individual keys: only that one differs, the rest stays default", arguments: [
        (#"{"bar":{"showClock":false}}"#, ShellSettings(bar: .init(layout: .migrated(showClock: false)))),
        (#"{"bar":{"clock":{"showDate":true}}}"#, ShellSettings(bar: .init(layout: .migrated(clock: .init(showDate: true))))),
        (#"{"bar":{"layout":[{"kind":"hologram"}]},"toasts":{"batteryWarnings":false}}"#,
         ShellSettings(bar: .init(layout: BarLayout()), toasts: .init(batteryWarnings: false))),
        (#"{"bar":{"showSpaces":false,"showWorkspaces":"nein"}}"#, ShellSettings()),
        (#"{"toasts":{"batteryWarnings":false}}"#, ShellSettings(toasts: .init(batteryWarnings: false))),
        (#"{"toasts":{"audioInputChanged":false,"chargingChanged":1}}"#, ShellSettings(toasts: .init(audioInputChanged: false))),
        (#"{"background":{"desktopClock":false},"bar":[]}"#, ShellSettings(background: .init(desktopClock: false))),
    ])
    func partialKeys(json: String, expected: ShellSettings) {
        #expect(ShellSettings.load(from: Data(json.utf8)) == expected)
    }

    @Test("writing and reading again gives the same result", arguments: [
        ShellSettings(),
        ShellSettings.firstLaunch,
        ShellSettings(
            bar: .init(layout: BarPreset.everything.layout),
            toasts: .init(chargingChanged: false, batteryWarnings: false, audioOutputChanged: false, audioInputChanged: false),
            background: .init(desktopClock: false)
        ),
    ])
    func roundTrip(settings: ShellSettings) {
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
    }

    @Test("the file names every key (readable by hand)", arguments: [
        "\"bar\"", "\"layout\"", "\"id\"", "\"kind\"", "\"options\"", "\"clock\"", "\"showDate\"",
        "\"toasts\"", "\"chargingChanged\"", "\"batteryWarnings\"", "\"audioOutputChanged\"", "\"background\"", "\"desktopClock\"",
    ])
    func keysWritten(key: String) {
        let text = String(decoding: ShellSettings().encoded(), as: UTF8.self)
        #expect(text.contains(key))
    }

    // MARK: - Bar background

    @Test("Menu bar item: on without the key, off only when the file says so", arguments: [
        ("{}", true),
        (#"{"menuBar":{}}"#, true),
        (#"{"menuBar":{"shown":"nein"}}"#, true),
        (#"{"menuBar":{"shown":false}}"#, false),
    ])
    func menuBarShown(json: String, shown: Bool) {
        #expect(ShellSettings.load(from: Data(json.utf8)).menuBar.shown == shown)
        #expect(ShellSettings.firstLaunch.menuBar.shown)
    }

    @Test("Background: writing and reading again gives the same result", arguments: BarBackground.allCases)
    func backgroundRoundTrip(background: BarBackground) {
        // In a list instead of individually: a single value would be a
        // JSON fragment, whereas in settings.json it's inside an object anyway.
        let data = try! JSONEncoder().encode([background])
        #expect(try! JSONDecoder().decode([BarBackground].self, from: data) == [background])
        let settings = ShellSettings(bar: .init(background: background))
        #expect(ShellSettings.load(from: settings.encoded()).bar.background == background)
    }

    @Test("Background: unknown value falls back to the default")
    func backgroundUnknown() {
        let json = #"["glass","hologramm","","fixedGlass"]"#
        let decoded = try! JSONDecoder().decode([BarBackground].self, from: Data(json.utf8))
        #expect(decoded == [.glass, .material, .material, .fixedGlass])
        #expect(BarBackground.standard == .material)
    }

    @Test("Background: missing or broken key gives Material", arguments: [
        #"{"bar":{"layout":[]}}"#, #"{"bar":{"background":"hologramm"}}"#, #"{"bar":{"background":5}}"#,
        #"{"bar":{"background":null}}"#, #"{"bar":{"background":{"art":"glas"}}}"#,
    ])
    func backgroundLenient(json: String) {
        #expect(ShellSettings.load(from: Data(json.utf8)).bar.background == .material)
    }

    @Test("Background: unchanged, it stays with the previous look")
    func backgroundDefault() {
        #expect(ShellSettings().bar.background == .material)
        #expect(ShellSettings.firstLaunch.bar.background == .material)
    }

    @Test("Battery events follow their switch", arguments: [
        (ShellSettings.Toasts(), BatteryToastEvent.chargerConnected, true),
        (ShellSettings.Toasts(chargingChanged: false), BatteryToastEvent.chargerConnected, false),
        (ShellSettings.Toasts(chargingChanged: false), BatteryToastEvent.chargerDisconnected, false),
        (ShellSettings.Toasts(chargingChanged: false), BatteryToastEvent.warning(BatteryWarningLevel.caelestiaDefaults[0]), true),
        (ShellSettings.Toasts(batteryWarnings: false), BatteryToastEvent.warning(BatteryWarningLevel.caelestiaDefaults[0]), false),
        (ShellSettings.Toasts(batteryWarnings: false), BatteryToastEvent.chargerDisconnected, true),
    ])
    func batteryFilter(toasts: ShellSettings.Toasts, event: BatteryToastEvent, shown: Bool) {
        #expect(toasts.allows(event) == shown)
    }

    // MARK: Dashboard pages (0.2)

    @Test("Pages and size: missing in old files, slider clamped, old section stays")
    func dashboardPages() throws {
        let old = ShellSettings.load(from: Data(#"{"dashboard":{"tabs":[{"id":"media","visible":false}]}}"#.utf8))
        #expect(old.dashboardPages == nil)
        #expect(old.dashboardScale == 1)

        var settings = old
        settings.dashboardPages = DashboardPages(pages: DashboardPages.defaultPages(places: .empty, hasBattery: true))
        settings.dashboardScale = 1.2
        let reread = ShellSettings.load(from: settings.encoded())
        #expect(reread.dashboardPages == settings.dashboardPages)
        #expect(reread.dashboardScale == 1.2)
        #expect(reread.dashboard == old.dashboard)

        let loud = ShellSettings.load(from: Data(#"{"dashboardScale":9,"dashboardPages":[]}"#.utf8))
        #expect(loud.dashboardScale == 1.5)
        #expect(loud.dashboardPages == nil)
    }
}
