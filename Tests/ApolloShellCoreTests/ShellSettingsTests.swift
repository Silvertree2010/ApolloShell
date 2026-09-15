import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: settings.json lesen und schreiben")
struct ShellSettingsTests {
    @Test("fehlende Datei: frische Installation, sonst Vorgaben = bisheriges Verhalten")
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

    @Test("kaputt, leer, falscher Typ oder unbekannt: Vorgaben", arguments: [
        "", "kaputt", "[]", "{}", #"{"bar":5,"toasts":"nein","background":null}"#, #"{"unbekannt":true}"#,
    ])
    func brokenGivesDefaults(json: String) {
        #expect(ShellSettings.load(from: Data(json.utf8)) == ShellSettings())
    }

    @Test("einzelne Schluessel: nur dieser weicht ab, der Rest bleibt Vorgabe", arguments: [
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

    @Test("schreiben und wieder lesen ergibt dasselbe", arguments: [
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

    @Test("die Datei nennt jeden Schluessel (von Hand lesbar)", arguments: [
        "\"bar\"", "\"layout\"", "\"id\"", "\"kind\"", "\"options\"", "\"clock\"", "\"showDate\"",
        "\"toasts\"", "\"chargingChanged\"", "\"batteryWarnings\"", "\"audioOutputChanged\"", "\"background\"", "\"desktopClock\"",
    ])
    func keysWritten(key: String) {
        let text = String(decoding: ShellSettings().encoded(), as: UTF8.self)
        #expect(text.contains(key))
    }

    @Test("Akku-Ereignisse folgen ihrem Schalter", arguments: [
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
}
