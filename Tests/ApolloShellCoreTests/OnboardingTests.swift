import ApolloShellCore
import Foundation
import Testing

@Suite("Einführung, Autostart, Nur-Launcher")
struct OnboardingTests {
    @Test("Einführung nur bei frischer Installation", arguments: [
        (nil, false, true),
        (nil, true, false),
        ("{}", false, false),
        ("kaputt", false, false),
        (#"{"bar":{"showClock":false},"toasts":{}}"#, false, false),
        (#"{"onboarding":{"completed":false}}"#, false, true),
        (#"{"onboarding":{"completed":false}}"#, true, false),
        (#"{"onboarding":{"completed":true}}"#, false, false),
        (#"{"onboarding":{}}"#, false, false),
        (#"{"onboarding":"ja"}"#, false, false),
    ] as [(String?, Bool, Bool)])
    func shouldShow(json: String?, launcherOnly: Bool, expected: Bool) {
        let settings = ShellSettings.load(from: json.map { Data($0.utf8) })
        #expect(OnboardingRule.shouldShow(settings, launcherOnly: launcherOnly) == expected)
    }

    @Test("Frische Datei nach dem ersten Speichern: bis zum Abschluss offen", arguments: [
        (false, true), (true, false),
    ])
    func afterFirstWrite(completed: Bool, expected: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.onboarding.completed = completed
        let reloaded = ShellSettings.load(from: settings.encoded())
        #expect(reloaded == settings)
        #expect(OnboardingRule.shouldShow(reloaded, launcherOnly: false) == expected)
    }

    @Test("Schritte in fester Reihenfolge", arguments: [
        (OnboardingStep.welcome, nil, OnboardingStep.permissions),
        (OnboardingStep.permissions, OnboardingStep.welcome, OnboardingStep.hotKeys),
        (OnboardingStep.hotKeys, OnboardingStep.permissions, OnboardingStep.finish),
        (OnboardingStep.finish, OnboardingStep.hotKeys, nil),
    ] as [(OnboardingStep, OnboardingStep?, OnboardingStep?)])
    func steps(step: OnboardingStep, previous: OnboardingStep?, next: OnboardingStep?) {
        #expect(step.previous == previous)
        #expect(step.next == next)
        #expect(step.isLast == (next == nil))
    }

    @Test("Nur-Launcher: neuer Schlüssel gewinnt, alter wird weiter gelesen", arguments: [
        (nil, nil, false), (nil, true, true), (nil, false, false),
        (true, nil, true), (false, true, false), (true, false, true),
    ] as [(Bool?, Bool?, Bool)])
    func launcherOnly(current: Bool?, legacy: Bool?, expected: Bool) {
        let values: [String: Bool] = [LauncherOnlyFlag.key: current, LauncherOnlyFlag.legacyKey: legacy].compactMapValues { $0 }
        #expect(LauncherOnlyFlag.isOn { values[$0] } == expected)
    }

    @Test("Nur-Launcher: Zahlen und Text wie UserDefaults.bool", arguments: [
        ("YES", true), ("1", true), ("true", true), ("no", false), ("", false),
    ])
    func launcherOnlyText(text: String, expected: Bool) {
        #expect(LauncherOnlyFlag.isOn { $0 == LauncherOnlyFlag.legacyKey ? text : nil } == expected)
    }

    @Test("launchd-Label aus XPC_SERVICE_NAME", arguments: [
        ("org.example.shell", "org.example.shell"),
        ("application.com.example.Terminal.1234.5678", nil),
        ("0", nil), ("", nil), (nil, nil),
    ] as [(String?, String?)])
    func launchdLabel(value: String?, expected: String?) {
        let environment = value.map { ["XPC_SERVICE_NAME": $0] } ?? [:]
        #expect(OnboardingAutostart.launchdLabel(environment: environment) == expected)
    }

    @Test("Autostart-Schalter: an, bedienbar, Hinweis", arguments: [
        (OnboardingAutostart.Status.notRegistered, nil, true, false, true, false, false),
        (OnboardingAutostart.Status.enabled, nil, true, true, true, false, false),
        (OnboardingAutostart.Status.requiresApproval, nil, true, true, true, true, true),
        (OnboardingAutostart.Status.notFound, nil, true, false, true, false, false),
        (OnboardingAutostart.Status.notRegistered, "org.example.shell", true, false, false, false, true),
        (OnboardingAutostart.Status.enabled, "org.example.shell", true, true, true, false, true),
        (OnboardingAutostart.Status.notRegistered, nil, false, false, false, false, true),
    ] as [(OnboardingAutostart.Status, String?, Bool, Bool, Bool, Bool, Bool)])
    func autostart(status: OnboardingAutostart.Status, label: String?, isAppBundle: Bool,
                   isOn: Bool, canToggle: Bool, needsApproval: Bool, hasNote: Bool) {
        let state = OnboardingAutostart.state(status: status, launchdLabel: label, isAppBundle: isAppBundle)
        #expect(state.isOn == isOn)
        #expect(state.canToggle == canToggle)
        #expect(state.needsApproval == needsApproval)
        #expect((state.note != nil) == hasNote)
    }

    @Test("Hinweis nennt das launchd-Label", arguments: ["org.example.shell"])
    func autostartNoteNamesLabel(label: String) {
        let state = OnboardingAutostart.state(status: .notRegistered, launchdLabel: label, isAppBundle: true)
        #expect(state.note?.contains(label) == true)
    }
}
