import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider spaces")
struct SpacesProviderTests {
    func make(_ source: FakeSpacesSource = FakeSpacesSource()) -> (ProviderHarness, FakeSpacesSource) {
        let harness = ProviderHarness()
        harness.register(SpacesProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    static func entry(_ id: Double, _ index: Double, active: Bool = false, fullscreen: Bool = false) -> Value {
        .record(Record([("id", .number(id)), ("index", .number(index)), ("active", .bool(active)), ("fullscreen", .bool(fullscreen))]))
    }

    @Test("Liefert jedes Registry-Feld für den Hauptbildschirm, Vollbild zählt mit")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("spaces")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("spaces")).isEmpty)
        #expect(harness.value("spaces", "list") == .list([
            Self.entry(1, 1), Self.entry(2, 2, active: true), Self.entry(9, 3, fullscreen: true), Self.entry(3, 4),
        ]))
        #expect(harness.value("spaces", "current") == .number(2))
        #expect(harness.value("spaces", "count") == .number(4))
        guard case .list(let all) = harness.value("spaces", "all") else {
            Issue.record("all fehlt")
            return
        }
        #expect(all.count == 2)
    }

    @Test("push mit zweiter Prüfung nach 0,5 s, sonst alle 5 s")
    func pushAndPoll() {
        let (harness, source) = make()
        harness.advance(30)
        #expect(source.reads == 0)
        let token = harness.demand("spaces", "current")
        #expect(source.observing)
        let reads = source.reads
        source.activate(3)
        harness.flush()
        #expect(harness.value("spaces", "current") == .number(4))
        #expect(source.reads == reads + 1)
        harness.advance(0.5)
        #expect(source.reads == reads + 2)
        harness.advance(4.5)
        #expect(source.reads == reads + 3)
        harness.release(token)
        #expect(!source.observing)
        harness.advance(30)
        #expect(source.reads == reads + 3)
    }

    @Test("Wechsel in Schritten mit 0,12 s Abstand, Ereignis bei Änderung")
    func switchInSteps() async throws {
        let (harness, source) = make()
        harness.demand("spaces", "current")
        _ = try await harness.perform("spaces", "spaces.switch", [.number(4)])
        #expect(source.steps == [true])
        harness.advance(0.25)
        #expect(source.steps == [true, true])
        _ = try await harness.perform("spaces", "spaces.previous")
        _ = try await harness.perform("spaces", "spaces.next")
        _ = try await harness.perform("spaces", "spaces.mission-control")
        #expect(source.steps == [true, true, false, true])
        #expect(source.missionControlCount == 1)
        source.activate(1)
        #expect(harness.eventNames() == ["spaces.changed"])
    }

    @Test("Ohne Bedienungshilfen warnt der Wechsel und tut nichts")
    func switchWithoutAccessibilityWarns() async throws {
        let source = FakeSpacesSource()
        source.accessibilityTrusted = false
        let (harness, _) = make(source)
        harness.demand("spaces", "current")
        _ = try await harness.perform("spaces", "spaces.switch", [.number(1)])
        #expect(source.steps.isEmpty)
        #expect(harness.warnings.filter { $0.severity == .warning }.count == 1)
    }

    @Test("Fehlt SkyLight: leere Liste, current null, Aktionen warnen")
    func missingPrivateAPI() async throws {
        let source = FakeSpacesSource()
        source.available = false
        let (harness, _) = make(source)
        harness.demand("spaces")
        #expect(harness.value("spaces", "list") == .list([]))
        #expect(harness.value("spaces", "current") == .null)
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("spaces"), strict: false).isEmpty)
        _ = try await harness.perform("spaces", "spaces.next")
        #expect(source.steps.isEmpty)
    }
}
