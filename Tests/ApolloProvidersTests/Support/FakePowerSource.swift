import Foundation
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakePowerSource: PowerSource {
    let clock: ManualRuntimeClock
    var assertionHeld = false
    var assertionWorks = true
    var systemSleepDisabled: Bool? = false
    var sudoWorks = false
    var sudoCalls: [Bool] = []
    var adminRequests: [(disableSleep: Bool, installRule: Bool)] = []
    var adminCompletion: (@MainActor (Bool) -> Void)?
    var adminCancelled = 0
    var adminSyncCalls: [Bool] = []
    var markerExists = false
    var ruleInstalled = false
    var ruleRemovals = 0
    var batteryState: BatteryState? = BatteryState(level: 80, charging: false, onAC: false)

    init(clock: ManualRuntimeClock) {
        self.clock = clock
    }

    var now: Date { Date(timeIntervalSince1970: 1_790_000_000 + clock.now) }

    func takeAssertion() -> Bool {
        assertionHeld = assertionWorks
        return assertionWorks
    }

    func releaseAssertion() {
        assertionHeld = false
    }

    func sleepDisabled() -> Bool? { systemSleepDisabled }

    func sudoSetSleepDisabled(_ on: Bool) -> Bool {
        sudoCalls.append(on)
        if sudoWorks { systemSleepDisabled = on }
        return sudoWorks
    }

    func askAdmin(disableSleep: Bool, installRule: Bool, _ completion: @escaping @MainActor (Bool) -> Void) -> Bool {
        adminRequests.append((disableSleep, installRule))
        adminCompletion = completion
        return true
    }

    func answerAdmin(_ ok: Bool) {
        let completion = adminCompletion
        adminCompletion = nil
        if ok, let last = adminRequests.last {
            systemSleepDisabled = last.disableSleep
            if last.installRule { ruleInstalled = true }
        }
        completion?(ok)
    }

    func cancelAdmin() {
        adminCancelled += 1
    }

    func adminSync(disableSleep: Bool) -> Bool {
        adminSyncCalls.append(disableSleep)
        return false
    }

    func writeMarker() { markerExists = true }

    func removeMarker() { markerExists = false }

    func removeRule(_ completion: @escaping @MainActor (Bool) -> Void) {
        ruleRemovals += 1
        ruleInstalled = false
        completion(true)
    }

    func battery() -> BatteryState? { batteryState }
}

@MainActor
final class FakePermissionsSource: PermissionsSource {
    var accessibility = false
    var automation: Bool? = nil
    var screenRecording = true
    var loginItem = false
    var loginItemWorks = true
    var reads = 0
    var requests = 0
    var opened: [String] = []

    func read() -> PermissionsState {
        reads += 1
        return PermissionsState(accessibility: accessibility, automation: automation, screenRecording: screenRecording)
    }

    func requestAccessibility() { requests += 1 }

    func open(_ kind: String) { opened.append(kind) }

    func setLoginItem(_ on: Bool) -> Bool {
        if loginItemWorks { loginItem = on }
        return loginItemWorks
    }
}

@MainActor
final class FakeShortcutsSource: ShortcutsSource {
    var shortcuts: [UtilitiesShortcut]? = [UtilitiesShortcut(name: "Focus", identifier: "A1B2"), UtilitiesShortcut(name: "Backup", identifier: "")]
    var lists = 0
    var answersImmediately = true
    var pending: [@MainActor ([UtilitiesShortcut]?) -> Void] = []
    var runs: [String] = []
    var runWorks = true

    func list(_ completion: @escaping @MainActor ([UtilitiesShortcut]?) -> Void) {
        lists += 1
        if answersImmediately { completion(shortcuts) } else { pending.append(completion) }
    }

    func finish() {
        let waiting = pending
        pending.removeAll()
        for completion in waiting { completion(shortcuts) }
    }

    func run(_ name: String, _ completion: @escaping @MainActor (Bool) -> Void) {
        runs.append(name)
        completion(runWorks)
    }
}
