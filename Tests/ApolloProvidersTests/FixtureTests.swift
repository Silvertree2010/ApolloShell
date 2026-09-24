import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Fixture-Modus")
struct FixtureTests {
    @Test("Die Fixture aus testing.md 3.1 lädt ohne Diagnose")
    func specFixtureLoadsCleanly() {
        let fixture = ProviderFixture.parse(SpecFixture.text, file: "fixture.kdl")
        #expect(fixture.diagnostics.isEmpty)
        #expect(Set(fixture.values.keys) == ["clock", "battery", "network", "bluetooth", "audio", "perf", "weather", "media", "spaces", "apps"])
    }

    @Test("Fixture-Provider liefert genannte Werte, Leerwerte und jedes Registry-Feld")
    func fixtureProvidersDeliverEveryField() {
        let harness = ProviderHarness()
        let fixture = ProviderFixture.parse(SpecFixture.text, file: "fixture.kdl")
        let providers = FixtureProvider.all(fixture: fixture, registry: .builtin)
        #expect(providers.count == SchemaRegistry.builtin.providers.count)
        for provider in providers { harness.register(provider) }
        for id in SchemaRegistry.builtin.providers.keys { harness.demand(id) }

        #expect(harness.value("battery", "percent") == .number(0.76))
        #expect(harness.value("network", "wifi.rssi") == .number(-52))
        #expect(harness.value("network", "wifi.noise") == .null)
        #expect(harness.value("audio", "output.name") == .string("MacBook Pro Speakers"))
        #expect(harness.value("apps", "running") == .list([]))
        guard case .list(let dock) = harness.value("apps", "dock") else {
            Issue.record("dock ist keine Liste")
            return
        }
        #expect(dock.count == 3)
        #expect(harness.value("clock", "now") == .date(ISO8601DateFormatter().date(from: "2026-09-24T07:41:00Z")!))

        for schema in SchemaRegistry.builtin.providers.values {
            #expect(harness.conformanceProblems(schema, strict: false).isEmpty, "\(schema.id)")
        }
    }

    @Test("Unbekannte Provider und Felder ergeben Warnungen mit Ort")
    func unknownNamesWarn() {
        let fixture = ProviderFixture.parse("""
        fixture {
            batery percent=0.5
            battery percnt=0.5 percent=0.4
            network { wifi on=#true rsi=-40 }
        }
        """, file: "fixture.kdl")
        #expect(fixture.diagnostics.count == 3)
        #expect(fixture.diagnostics.allSatisfy { $0.severity == .warning && $0.span?.start.line ?? 0 > 0 })
        #expect(fixture.values["battery"]?["percent"] == .number(0.4))
    }

    @Test("NaN und unendlich werden null")
    func nonFiniteNumbersBecomeNull() {
        let fixture = ProviderFixture.parse("fixture { battery percent=#nan health=#inf cycles=#-inf }", file: "fixture.kdl")
        #expect(fixture.values["battery"]?["percent"] == .null)
        #expect(fixture.values["battery"]?["health"] == .null)
        #expect(fixture.values["battery"]?["cycles"] == .null)
    }

    @Test("Aktionen werden im Fixture-Modus nur geloggt")
    func actionsAreOnlyLogged() async throws {
        let harness = ProviderHarness()
        var logged: [String] = []
        let fixture = ProviderFixture.parse(SpecFixture.text, file: "fixture.kdl")
        let provider = FixtureProvider(schema: SchemaRegistry.builtin.providers["audio"]!, values: fixture.values["audio"] ?? Record()) { action, _, _ in
            logged.append(action)
        }
        harness.register(provider)
        harness.demand("audio", "volume")
        let result = try await harness.perform("audio", "audio.set-volume", [.number(0.9)])
        #expect(result == .null)
        #expect(logged == ["audio.set-volume"])
        #expect(harness.value("audio", "volume") == .number(0.35))
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("audio", "audio.explode")
        }
    }

    @Test("Syntaxfehler in der Fixture wird Fehlerdiagnose, keine Werte")
    func syntaxErrorBecomesDiagnostic() {
        let fixture = ProviderFixture.parse("fixture { battery percent= }", file: "fixture.kdl")
        #expect(fixture.values.isEmpty)
        #expect(fixture.diagnostics.first?.severity == .error)
    }
}
