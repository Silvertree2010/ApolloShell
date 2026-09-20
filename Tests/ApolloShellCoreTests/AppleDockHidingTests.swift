import ApolloShellCore
import Foundation
import Testing

@Suite("Apple-Dock ausblenden, solange ApolloShell läuft")
struct AppleDockHidingTests {
    @Test("The hidden values")
    func hiddenValues() {
        #expect(AppleDockHiding.hidden == AppleDockPreferenceValues(
            autohide: true, autohideDelay: 1000, autohideTimeModifier: 0
        ))
    }

    @Test("Saving the original: an ordinary current state stays the original")
    func originalKeepsNormalState() {
        let current = AppleDockPreferenceValues(autohide: false, autohideDelay: 0.5, autohideTimeModifier: 0.5)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Saving the original: partly missing keys stay the original")
    func originalKeepsPartialState() {
        let current = AppleDockPreferenceValues(autohide: nil, autohideDelay: 0.5, autohideTimeModifier: nil)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Migration: a current state that already looks hidden does not count as the original", arguments: [100.0, 1000.0])
    func originalRejectsAlreadyHidden(delay: Double) {
        let current = AppleDockPreferenceValues(autohide: true, autohideDelay: delay, autohideTimeModifier: 0)
        #expect(AppleDockHiding.originalToSave(current: current) == AppleDockPreferenceValues())
    }

    @Test("Just below the threshold it still counts as the original")
    func originalAcceptsJustBelowThreshold() {
        let current = AppleDockPreferenceValues(autohide: true, autohideDelay: 99.9, autohideTimeModifier: 0)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("A missing delay is no sign of being hidden already")
    func originalKeepsMissingDelay() {
        let current = AppleDockPreferenceValues(autohide: nil, autohideDelay: nil, autohideTimeModifier: nil)
        #expect(AppleDockHiding.originalToSave(current: current) == current)
    }

    @Test("Restoring: set the values that are there, delete the missing ones")
    func actionsForPartialOriginal() {
        let target = AppleDockPreferenceValues(autohide: false, autohideDelay: nil, autohideTimeModifier: 0.5)
        #expect(AppleDockHiding.actions(toReach: target) == [
            .setBool(key: AppleDockHiding.autohideKey, value: false),
            .remove(key: AppleDockHiding.autohideDelayKey),
            .setDouble(key: AppleDockHiding.autohideTimeModifierKey, value: 0.5),
        ])
    }

    @Test("Hiding: all three keys set")
    func actionsForHiding() {
        #expect(AppleDockHiding.actions(toReach: AppleDockHiding.hidden) == [
            .setBool(key: AppleDockHiding.autohideKey, value: true),
            .setDouble(key: AppleDockHiding.autohideDelayKey, value: 1000),
            .setDouble(key: AppleDockHiding.autohideTimeModifierKey, value: 0),
        ])
    }

    @Test("Restoring the macOS default: delete all three keys")
    func actionsForDefault() {
        #expect(AppleDockHiding.actions(toReach: AppleDockPreferenceValues()) == [
            .remove(key: AppleDockHiding.autohideKey),
            .remove(key: AppleDockHiding.autohideDelayKey),
            .remove(key: AppleDockHiding.autohideTimeModifierKey),
        ])
    }

    @Test("Encoding: no file gives no original")
    func loadMissingFile() {
        #expect(AppleDockPreferenceValues.load(from: nil) == nil)
    }

    @Test("Encoding: a broken file gives no original")
    func loadBrokenFile() {
        #expect(AppleDockPreferenceValues.load(from: Data("kaputt".utf8)) == nil)
    }

    @Test("The encoding survives writing and reading", arguments: [
        AppleDockPreferenceValues(),
        AppleDockPreferenceValues(autohide: true, autohideDelay: 1000, autohideTimeModifier: 0),
        AppleDockPreferenceValues(autohide: false, autohideDelay: 0.5, autohideTimeModifier: nil),
    ])
    func roundTrip(values: AppleDockPreferenceValues) {
        #expect(AppleDockPreferenceValues.load(from: values.encoded()) == values)
    }

    @Test("The setting: off on a fresh installation, on for an existing one", arguments: [
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

    @Test("The setting survives writing and reading", arguments: [true, false])
    func settingRoundTrip(hideWhileRunning: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.appleDockHiding.hideWhileRunning = hideWhileRunning
        #expect(ShellSettings.load(from: settings.encoded()).appleDockHiding.hideWhileRunning == hideWhileRunning)
    }
}
