import ApolloShellCore
import Foundation
import Testing

@Suite("Hide Apple's Dock while ApolloShell is running")
struct AppleDockHidingTests {
    @Test("Versteckte Werte")
    func hiddenValues() {
        #expect(AppleDockHiding.hidden == AppleDockPreferenceValues(
            autohide: true, autohideDelay: 1000, autohideTimeModifier: 0
        ))
    }

    @Test("Original sichern: normaler Ist-Zustand bleibt Original")
    func originalKeepsNormalState() {
        let current = AppleDockPreferenceValues(autohide: false, autohideDelay: 0.5, autohideTimeModifier: 0.5)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Original sichern: teilweise fehlende Schlüssel bleiben Original")
    func originalKeepsPartialState() {
        let current = AppleDockPreferenceValues(autohide: nil, autohideDelay: 0.5, autohideTimeModifier: nil)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Migration: schon versteckt aussehender Ist-Zustand gilt nicht als Original", arguments: [100.0, 1000.0])
    func originalRejectsAlreadyHidden(delay: Double) {
        let current = AppleDockPreferenceValues(autohide: true, autohideDelay: delay, autohideTimeModifier: 0)
        #expect(AppleDockHiding.originalToSave(current: current) == AppleDockPreferenceValues())
    }

    @Test("Knapp unter der Schwelle gilt noch als Original")
    func originalAcceptsJustBelowThreshold() {
        let current = AppleDockPreferenceValues(autohide: true, autohideDelay: 99.9, autohideTimeModifier: 0)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Fehlende Verzögerung ist kein Hinweis auf schon versteckt")
    func originalKeepsMissingDelay() {
        let current = AppleDockPreferenceValues(autohide: nil, autohideDelay: nil, autohideTimeModifier: nil)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Wiederherstellen: vorhandene Werte setzen, fehlende löschen")
    func actionsForPartialOriginal() {
        let target = AppleDockPreferenceValues(autohide: false, autohideDelay: nil, autohideTimeModifier: 0.5)
        #expect(AppleDockHiding.actions(toReach: target) == [
            .setBool(key: AppleDockHiding.autohideKey, value: false),
            .remove(key: AppleDockHiding.autohideDelayKey),
            .setDouble(key: AppleDockHiding.autohideTimeModifierKey, value: 0.5),
        ])
    }

    @Test("Verstecken: every drei Schlüssel gesetzt")
    func actionsForHiding() {
        #expect(AppleDockHiding.actions(toReach: AppleDockHiding.hidden) == [
            .setBool(key: AppleDockHiding.autohideKey, value: true),
            .setDouble(key: AppleDockHiding.autohideDelayKey, value: 1000),
            .setDouble(key: AppleDockHiding.autohideTimeModifierKey, value: 0),
        ])
    }

    @Test("Wiederherstellen macOS-Vorgabe: every drei Schlüssel löschen")
    func actionsForDefault() {
        #expect(AppleDockHiding.actions(toReach: AppleDockPreferenceValues()) == [
            .remove(key: AppleDockHiding.autohideKey),
            .remove(key: AppleDockHiding.autohideDelayKey),
            .remove(key: AppleDockHiding.autohideTimeModifierKey),
        ])
    }

    @Test("Kodierung: keine Datei liefert kein Original")
    func loadMissingFile() {
        #expect(AppleDockPreferenceValues.load(from: nil) == nil)
    }

    @Test("Kodierung: kaputte Datei liefert kein Original")
    func loadBrokenFile() {
        #expect(AppleDockPreferenceValues.load(from: Data("kaputt".utf8)) == nil)
    }

    @Test("Kodierung übersteht Schreiben und Lesen", arguments: [
        AppleDockPreferenceValues(),
        AppleDockPreferenceValues(autohide: true, autohideDelay: 1000, autohideTimeModifier: 0),
        AppleDockPreferenceValues(autohide: false, autohideDelay: 0.5, autohideTimeModifier: nil),
    ])
    func roundTrip(values: AppleDockPreferenceValues) {
        #expect(AppleDockPreferenceValues.load(from: values.encoded()) == values)
    }

    @Test("Einstellung: aus bei frischer Installation, an für vorhandene", arguments: [
        (nil, false),
        ("{}", true),
        ("kaputt", true),
        (#"{"toasts":{"batteryWarnings":false}}"#, true),
        (#"{"appleDockHiding":"ja"}"#, true),
        (#"{"appleDockHiding":{}}"#, false),
        (#"{"appleDockHiding":{"hideWhileRunning":false}}"#, false),
        (#"{"appleDockHiding":{"hideWhileRunning":true}}"#, true),
    ] as [(String?, Bool)])
    func settingMigration(json: String?, hideWhileRunning: Bool) {
        #expect(ShellSettings.load(from: json.map { Data($0.utf8) }).appleDockHiding.hideWhileRunning == hideWhileRunning)
    }

    @Test("Einstellung übersteht Schreiben und Lesen", arguments: [true, false])
    func settingRoundTrip(hideWhileRunning: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.appleDockHiding.hideWhileRunning = hideWhileRunning
        #expect(ShellSettings.load(from: settings.encoded()).appleDockHiding.hideWhileRunning == hideWhileRunning)
    }
}
