import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider power")
struct PowerProviderTests {
    func make(_ prepare: (FakePowerSource) -> Void = { _ in }) -> (ProviderHarness, FakePowerSource, PowerProvider) {
        let harness = ProviderHarness()
        let source = FakePowerSource(clock: harness.clock)
        prepare(source)
        let provider = PowerProvider(source: source, clock: harness.clock)
        harness.register(provider)
        return (harness, source, provider)
    }

    @Test("Liefert jedes Registry-Feld, beim Start aus")
    func deliversAllFields() {
        let (harness, source, _) = make()
        harness.demand("power")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("power")).isEmpty)
        #expect(harness.value("power", "keep-awake") == .bool(false))
        #expect(harness.value("power", "keep-awake-since") == .null)
        #expect(harness.value("power", "lid") == .string("off"))
        #expect(harness.value("power", "keep-awake-text") == .string(KeepAwakeText.inactive))
        #expect(!source.assertionHeld)
    }

    @Test("Wachhalten ohne Deckel: Zusicherung, seit, Text")
    func keepAwakeWithoutLid() async throws {
        let (harness, source, _) = make()
        harness.demand("power")
        _ = try await harness.perform("power", "power.toggle-keep-awake")
        #expect(source.assertionHeld)
        #expect(harness.value("power", "keep-awake") == .bool(true))
        #expect(harness.value("power", "keep-awake-since") == .date(source.now))
        #expect(harness.value("power", "keep-awake-text") == .string(KeepAwakeText.subtitle(since: source.now, now: source.now, lid: .off)))
        #expect(source.sudoCalls.isEmpty)
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(false)])
        #expect(!source.assertionHeld)
        #expect(harness.value("power", "keep-awake") == .bool(false))
    }

    @Test("Deckel: Administrator-Dialog, pending, on, Ausschalten abgelehnt meldet Ereignis")
    func lidWithApproval() async throws {
        let (harness, source, provider) = make()
        provider.configure(Record([("lid-closed", .bool(true))]))
        harness.demand("power")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        #expect(source.sudoCalls == [true])
        #expect(source.markerExists)
        #expect(harness.value("power", "lid") == .string("pending"))
        #expect(source.adminRequests.count == 1 && source.adminRequests[0].disableSleep && source.adminRequests[0].installRule)
        source.answerAdmin(true)
        harness.flush()
        #expect(harness.value("power", "lid") == .string("on"))
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(false)])
        #expect(source.adminRequests.count == 2 && !source.adminRequests[1].disableSleep)
        source.answerAdmin(false)
        harness.flush()
        #expect(harness.eventNames() == ["power.lid-still-awake"])
        #expect(harness.value("power", "lid") == .string("off"))
    }

    @Test("Deckel abgelehnt: declined, Merker weg; Einstellung wirkt sofort")
    func lidDeclinedAndSettingChange() async throws {
        let (harness, source, provider) = make()
        provider.configure(Record([("lid-closed", .bool(true))]))
        harness.demand("power")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        source.answerAdmin(false)
        harness.flush()
        #expect(harness.value("power", "lid") == .string("declined"))
        #expect(!source.markerExists)
        source.sudoWorks = true
        provider.configure(Record([("lid-closed", .bool(false))]))
        harness.flush()
        #expect(harness.value("power", "lid") == .string("off"))
        provider.configure(Record([("lid-closed", .bool(true))]))
        harness.flush()
        #expect(harness.value("power", "lid") == .string("on"))
        #expect(source.systemSleepDisabled == true)
        provider.configure(Record([("lid-closed", .bool(false))]))
        harness.flush()
        #expect(source.systemSleepDisabled == false)
        #expect(!source.markerExists)
    }

    @Test("Fremdes disablesleep wird nicht zurückgesetzt")
    func foreignSleepDisabledStays() async throws {
        let (harness, source, provider) = make { $0.systemSleepDisabled = true }
        provider.configure(Record([("lid-closed", .bool(true))]))
        harness.demand("power")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        #expect(harness.value("power", "lid") == .string("on"))
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(false)])
        #expect(source.sudoCalls.isEmpty)
        #expect(source.adminRequests.isEmpty)
        #expect(source.systemSleepDisabled == true)
    }

    @Test("Akkuschutz bei 10 % auch ohne Nachfrage, Ereignis mit Grund")
    func batteryGuard() async throws {
        let (harness, source, _) = make()
        let token = harness.demand("power", "keep-awake")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        harness.release(token)
        source.batteryState = BatteryState(level: 10, charging: false, onAC: false)
        harness.advance(60)
        #expect(!source.assertionHeld)
        source.batteryState = BatteryState(level: 10, charging: false, onAC: true)
        let awake = harness.keepAwake("power")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        harness.advance(60)
        #expect(source.assertionHeld)
        source.batteryState = BatteryState(level: 9, charging: false, onAC: false)
        harness.advance(60)
        #expect(!source.assertionHeld)
        #expect(harness.eventNames() == ["power.keep-awake-stopped"])
        #expect(harness.events.first?.fields["reason"] == .string("battery"))
        #expect(harness.value("power", "keep-awake") == .bool(false))
        harness.releaseAwake(awake)
    }

    @Test("Wiederherstellung nach Absturz über den Merker")
    func crashRecovery() {
        let (_, source, _) = make {
            $0.markerExists = true
            $0.systemSleepDisabled = true
            $0.sudoWorks = true
        }
        #expect(source.sudoCalls == [false])
        #expect(!source.markerExists)
        #expect(source.systemSleepDisabled == false)
    }

    @Test("Beenden: offene Einschalt-Frage abbrechen, sonst Deckel zurückstellen")
    func shutdown() async throws {
        let (harness, source, provider) = make()
        provider.configure(Record([("lid-closed", .bool(true))]))
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        provider.shutdown()
        #expect(source.adminCancelled == 1)
        #expect(!source.assertionHeld)
    }

    @Test("Regel alle 2 s geprüft nur bei Nachfrage, Text jede Minute, Regel entfernen")
    func ruleAndText() async throws {
        let (harness, source, _) = make()
        let token = harness.demand("power", "lid-rule-installed")
        #expect(harness.value("power", "lid-rule-installed") == .bool(false))
        source.ruleInstalled = true
        harness.advance(2)
        #expect(harness.value("power", "lid-rule-installed") == .bool(true))
        _ = try await harness.perform("power", "power.remove-lid-rule")
        #expect(source.ruleRemovals == 1)
        #expect(harness.value("power", "lid-rule-installed") == .bool(false))
        harness.release(token)
        source.ruleInstalled = true
        let text = harness.demand("power", "keep-awake-text")
        _ = try await harness.perform("power", "power.set-keep-awake", [.bool(true)])
        let since = source.now
        harness.advance(120)
        #expect(harness.value("power", "keep-awake-text") == .string(KeepAwakeText.subtitle(since: since, now: source.now, lid: .off)))
        #expect(harness.value("power", "lid-rule-installed") == .bool(false))
        harness.release(text)
    }
}

@MainActor
@Suite("Provider permissions und shortcuts")
struct PermissionsShortcutsTests {
    @Test("permissions: alle Felder, 2 s nur bei Nachfrage, Aktionen")
    func permissions() async throws {
        let harness = ProviderHarness()
        let source = FakePermissionsSource()
        harness.register(PermissionsProvider(source: source, clock: harness.clock))
        harness.advance(10)
        #expect(source.reads == 0)
        let token = harness.demand("permissions")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("permissions")).isEmpty)
        #expect(harness.value("permissions", "automation") == .null)
        #expect(harness.value("permissions", "shell.login-item") == .bool(false))
        source.accessibility = true
        harness.advance(2)
        #expect(harness.value("permissions", "accessibility") == .bool(true))
        _ = try await harness.perform("permissions", "permissions.request-accessibility")
        _ = try await harness.perform("permissions", "permissions.open", [.string("screen-recording")])
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("permissions", "permissions.open", [.string("camera")])
        }
        _ = try await harness.perform("permissions", "shell.set-login-item", [.bool(true)])
        #expect(harness.value("permissions", "shell.login-item") == .bool(true))
        source.loginItemWorks = false
        _ = try await harness.perform("permissions", "shell.set-login-item", [.bool(false)])
        #expect(harness.warnings.count == 1)
        #expect(source.requests == 1)
        #expect(source.opened == ["screen-recording"])
        harness.release(token)
        let reads = source.reads
        harness.advance(10)
        #expect(source.reads == reads)
    }

    @Test("shortcuts: Liste alle 5 s nur bei Nachfrage, run-shortcut meldet Fehlschlag")
    func shortcuts() async throws {
        let harness = ProviderHarness()
        let source = FakeShortcutsSource()
        harness.register(ShortcutsProvider(source: source, clock: harness.clock))
        #expect(source.lists == 0)
        let token = harness.demand("shortcuts", "list")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("shortcuts")).isEmpty)
        #expect(harness.value("shortcuts", "list") == .list([
            .record(Record([("name", .string("Focus")), ("id", .string("A1B2"))])),
            .record(Record([("name", .string("Backup")), ("id", .string("Backup"))])),
        ]))
        source.answersImmediately = false
        harness.advance(5)
        harness.advance(5)
        #expect(source.lists == 2)
        source.finish()
        source.shortcuts = nil
        source.answersImmediately = true
        harness.advance(5)
        #expect(harness.value("shortcuts", "list") == .list([]))
        _ = try await harness.perform("shortcuts", "run-shortcut", [.string("Focus")])
        #expect(harness.events.isEmpty)
        source.runWorks = false
        _ = try await harness.perform("shortcuts", "run-shortcut", [.string("Backup")])
        #expect(harness.eventNames() == ["shortcuts.failed"])
        #expect(harness.events[0].fields["name"] == .string("Backup"))
        harness.release(token)
        harness.advance(20)
        #expect(source.lists == 3)
    }
}
