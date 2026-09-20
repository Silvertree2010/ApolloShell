import ApolloShellCore
import Foundation
import Testing

@Suite("Onboarding, autostart, launcher-only")
struct OnboardingTests {
    @Test("onboarding only on a fresh install", arguments: [
        (nil, false, true),
        (nil, true, false),
        ("{}", false, false),
        ("broken", false, false),
        (#"{"bar":{"showClock":false},"toasts":{}}"#, false, false),
        (#"{"onboarding":{"completed":false}}"#, false, true),
        (#"{"onboarding":{"completed":false}}"#, true, false),
        (#"{"onboarding":{"completed":true}}"#, false, false),
        (#"{"onboarding":{}}"#, false, false),
        (#"{"onboarding":"yes"}"#, false, false),
    ] as [(String?, Bool, Bool)])
    func shouldShow(json: String?, launcherOnly: Bool, expected: Bool) {
        let settings = ShellSettings.load(from: json.map { Data($0.utf8) })
        #expect(OnboardingRule.shouldShow(settings, launcherOnly: launcherOnly) == expected)
    }

    @Test("fresh file after the first save: open until completion", arguments: [
        (false, true), (true, false),
    ])
    func afterFirstWrite(completed: Bool, expected: Bool) {
        var settings = ShellSettings.firstLaunch
        settings.onboarding.completed = completed
        let reloaded = ShellSettings.load(from: settings.encoded())
        #expect(reloaded == settings)
        #expect(OnboardingRule.shouldShow(reloaded, launcherOnly: false) == expected)
    }

    @Test("steps in a fixed order", arguments: [
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

    @Test("launcher-only: the new key wins, the old one is still read", arguments: [
        (nil, nil, false), (nil, true, true), (nil, false, false),
        (true, nil, true), (false, true, false), (true, false, true),
    ] as [(Bool?, Bool?, Bool)])
    func launcherOnly(current: Bool?, legacy: Bool?, expected: Bool) {
        let values: [String: Bool] = [LauncherOnlyFlag.key: current, LauncherOnlyFlag.legacyKey: legacy].compactMapValues { $0 }
        #expect(LauncherOnlyFlag.isOn { values[$0] } == expected)
    }

    @Test("launcher-only: numbers and text like UserDefaults.bool", arguments: [
        ("YES", true), ("1", true), ("true", true), ("no", false), ("", false),
    ])
    func launcherOnlyText(text: String, expected: Bool) {
        #expect(LauncherOnlyFlag.isOn { $0 == LauncherOnlyFlag.legacyKey ? text : nil } == expected)
    }

    @Test("launchd label from XPC_SERVICE_NAME", arguments: [
        ("org.example.shell", "org.example.shell"),
        ("application.com.example.Terminal.1234.5678", nil),
        ("0", nil), ("", nil), (nil, nil),
    ] as [(String?, String?)])
    func launchdLabel(value: String?, expected: String?) {
        let environment = value.map { ["XPC_SERVICE_NAME": $0] } ?? [:]
        #expect(OnboardingAutostart.launchdLabel(environment: environment) == expected)
    }

    @Test("autostart toggle: on, usable, note", arguments: [
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

    @Test("the note names the launchd label", arguments: ["org.example.shell"])
    func autostartNoteNamesLabel(label: String) {
        let state = OnboardingAutostart.state(status: .notRegistered, launchdLabel: label, isAppBundle: true)
        #expect(state.note?.contains(label) == true)
    }
}
