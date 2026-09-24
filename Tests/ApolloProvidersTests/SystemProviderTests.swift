import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider system und session")
struct SystemProviderTests {
    func make() -> (ProviderHarness, FakeSystemSource) {
        let harness = ProviderHarness()
        let source = FakeSystemSource()
        harness.register(SystemProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("system")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("system")).isEmpty)
        #expect(harness.value("system", "user-image") == .image(ImageRef(source: "user-image", id: "andrin")))
        #expect(harness.value("system", "chip") == .string("Apple M4"))
        #expect(harness.value("system", "accent-color") == .string("#007AFF"))
    }

    @Test("Null-Felder: kein Night Shift, kein schaltbares Mikrofon, kein Profilbild")
    func nullableFields() async throws {
        let (harness, source) = make()
        source.nightShift = nil
        source.microphoneMuted = nil
        source.info.hasUserImage = false
        harness.demand("system")
        #expect(harness.value("system", "night-shift") == .null)
        #expect(harness.value("system", "microphone-muted") == .null)
        #expect(harness.value("system", "user-image") == .null)
        _ = try await harness.perform("system", "system.toggle-night-shift")
        _ = try await harness.perform("system", "system.toggle-microphone")
        #expect(harness.warnings.count == 2)
    }

    @Test("Dunkelmodus sofort neu, nach 0,5 s nachgelesen, Ereignis bei Wechsel")
    func darkModeRereads() async throws {
        let (harness, source) = make()
        harness.demand("system", "dark-mode")
        source.darkModeFollowsSet = false
        _ = try await harness.perform("system", "system.toggle-dark-mode")
        #expect(harness.value("system", "dark-mode") == .bool(true))
        #expect(harness.eventNames() == ["system.appearance-changed"])
        harness.advance(0.5)
        #expect(harness.value("system", "dark-mode") == .bool(false))
        #expect(harness.eventNames() == ["system.appearance-changed", "system.appearance-changed"])
        source.darkMode = true
        source.changed()
        harness.flush()
        #expect(harness.value("system", "dark-mode") == .bool(true))
        #expect(harness.events.count == 3)
        source.darkModeFollowsSet = true
        _ = try await harness.perform("system", "system.set-dark-mode", [.bool(true)])
        #expect(harness.events.count == 3)
    }

    @Test("Schalter für Night Shift und Mikrofon, Apple-Dock")
    func toggles() async throws {
        let (harness, source) = make()
        harness.demand("system")
        _ = try await harness.perform("system", "system.toggle-night-shift")
        _ = try await harness.perform("system", "system.set-microphone-muted", [.bool(true)])
        _ = try await harness.perform("system", "system.hide-apple-dock", [.bool(true)])
        #expect(source.nightShift == true)
        #expect(harness.value("system", "night-shift") == .bool(true))
        #expect(harness.value("system", "microphone-muted") == .bool(true))
        #expect(harness.value("system", "apple-dock-hidden") == .bool(true))
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("system", "system.set-dark-mode", [.string("yes")])
        }
    }

    @Test("Systemaktionen, Einstellungsbereiche, Farbpipette mit Ereignis")
    func commands() async throws {
        let (harness, source) = make()
        harness.demand("system", "dark-mode")
        _ = try await harness.perform("system", "system.screenshot")
        _ = try await harness.perform("system", "system.show-desktop")
        _ = try await harness.perform("system", "system.lock")
        _ = try await harness.perform("system", "system.display-sleep")
        _ = try await harness.perform("system", "system.hide-apps", properties: Record([("keep-frontmost", .bool(true))]))
        _ = try await harness.perform("system", "system.hide-apps")
        _ = try await harness.perform("system", "system.open-settings")
        _ = try await harness.perform("system", "system.open-settings", [.string("wifi")])
        #expect(source.commands == [
            .screenshot, .showDesktop, .lock, .displaySleep, .hideApps(keepFrontmost: true), .hideApps(keepFrontmost: false),
            .openSettings(nil), .openSettings("com.apple.wifi-settings-extension"),
        ])
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("system", "system.open-settings", [.string("kitchen")])
        }
        _ = try await harness.perform("system", "system.color-picker")
        #expect(harness.eventNames() == ["system.color-copied"])
        #expect(harness.events[0].fields["hex"] == .string("#FF8800"))
        source.pickedColor = nil
        _ = try await harness.perform("system", "system.color-picker")
        #expect(harness.events.count == 1)
    }

    @Test("Jeder Einstellungsbereich aus der Spec hat eine Kennung")
    func everyPaneResolves() {
        for pane in ["wallpaper", "appearance", "network", "wifi", "bluetooth", "sound", "battery", "notifications", "software-update", "language-region", "accessibility", "login-items", "about"] {
            #expect(SystemSettingsPane.identifier(pane) != nil, "\(pane)")
        }
    }

    @Test("Laufzeit tickt jede Minute nur bei Nachfrage, Beobachter nur solange gefragt")
    func uptimeAndDemand() {
        let (harness, source) = make()
        #expect(!source.observing)
        let token = harness.demand("system", "dark-mode")
        #expect(source.observing)
        source.uptime = 3660
        harness.advance(60)
        #expect(harness.value("system", "uptime") == .null)
        let uptime = harness.demand("system", "uptime")
        #expect(harness.value("system", "uptime") == .number(3660))
        source.uptime = 3720
        harness.advance(60)
        #expect(harness.value("system", "uptime") == .number(3720))
        harness.release(uptime)
        harness.release(token)
        #expect(!source.observing)
    }

    @Test("session reicht jede Aktion an die Quelle weiter")
    func sessionActions() async throws {
        let harness = ProviderHarness()
        let source = FakeSessionSource()
        harness.register(SessionProvider(source: source, clock: harness.clock))
        for action in ["session.logout", "session.restart", "session.shutdown", "session.sleep", "session.lock"] {
            _ = try await harness.perform("session", action)
        }
        #expect(source.runs == [.logOut, .restart, .shutDown, .sleep])
        #expect(source.locks == 1)
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("session", "session.dance")
        }
    }
}
