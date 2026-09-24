import Testing
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider-Infrastruktur")
struct InfrastructureTests {
    @Test("Nachfrage gilt für das Feld, seine Kinder und seine Eltern")
    func demandPrefixRule() {
        let demand = DemandSet([DependencyPath("network", ["wifi", "rssi"]), DependencyPath("perf", ["live"])])
        #expect(demand.wants("wifi.rssi"))
        #expect(demand.wants("wifi"))
        #expect(!demand.wants("wifi.bars"))
        #expect(demand.wants("live.cpu"))
        #expect(!demand.wants("cpu"))
        #expect(DemandSet([DependencyPath("battery")]).wants("health"))
        #expect(!DemandSet([]).wants("health"))
        #expect(demand.wantsAny(["cpu", "wifi.rssi"]))
    }

    @Test("Takt läuft nur, solange er aktiv ist, und feuert auf Wunsch sofort")
    func timerRunsOnlyWhileActive() {
        let clock = ManualRuntimeClock()
        let timers = ProviderTimers(clock: clock)
        var fired = 0
        timers.set("poll", every: 2, active: true, immediately: true) { fired += 1 }
        #expect(fired == 1)
        clock.advance(by: 2)
        clock.advance(by: 2)
        #expect(fired == 3)
        timers.set("poll", every: 2, active: true) { fired += 100 }
        clock.advance(by: 2)
        #expect(fired == 103)
        timers.set("poll", every: 2, active: false) { fired += 1 }
        clock.advance(by: 10)
        #expect(fired == 103)
        #expect(!timers.isActive("poll"))
        timers.set("poll", every: 1, active: true) { fired += 1 }
        timers.cancelAll()
        clock.advance(by: 10)
        #expect(fired == 103)
    }

    @Test("Prüfer findet fehlende Felder, falsche Typen und unerlaubtes null")
    func conformanceFindsProblems() {
        let schema = ProviderSchema(id: "demo", fields: [
            FieldSchema(path: ["a"], type: .number, update: .push, doc: ""),
            FieldSchema(path: ["b", "c"], type: .string, nullable: true, update: .push, doc: ""),
            FieldSchema(path: ["d"], type: .enumeration(["x", "y"]), update: .push, doc: ""),
            FieldSchema(path: ["e"], type: .bool, update: .push, doc: ""),
        ], doc: "")
        let good = Value.record(Record([
            ("a", .number(1)), ("b", .record(Record([("c", .null)]))), ("d", .string("x")), ("e", .bool(true)),
        ]))
        #expect(ProviderConformance.problems(schema: schema, root: good, strictNullability: true).isEmpty)

        let bad = Value.record(Record([
            ("a", .string("1")), ("b", .record(Record())), ("d", .string("z")), ("e", .null),
        ]))
        let problems = ProviderConformance.problems(schema: schema, root: bad, strictNullability: true)
        #expect(problems.count == 4)
        #expect(ProviderConformance.problems(schema: schema, root: bad, strictNullability: false).count == 3)
    }

    @Test("Argumente werden geprüft und unbekannte Aktionen gemeldet")
    func argumentsAreChecked() throws {
        let arguments = ActionArguments("audio.set-volume", [.number(0.5), .bool(true), .string("x")], Record([("in", .string("finder"))]))
        #expect(try arguments.number(0) == 0.5)
        #expect(try arguments.bool(1) == true)
        #expect(try arguments.string(2) == "x")
        #expect(arguments.property("in") == .string("finder"))
        #expect(throws: ProviderActionError.self) { try arguments.number(1) }
        #expect(throws: ProviderActionError.self) { try arguments.number(5) }
        #expect(throws: ProviderActionError.self) { try arguments.number(0, range: 0...0.4) }
    }

    @Test("Basis-Provider stoppt seine Takte beim Stopp")
    func baseProviderStopsTimers() {
        let harness = ProviderHarness()
        let provider = TickingProvider(clock: harness.clock)
        harness.register(provider)
        #expect(provider.ticks == 0)
        let token = harness.demand("ticking", "count")
        harness.advance(1)
        harness.advance(1)
        #expect(harness.value("ticking", "count") == .number(3))
        harness.release(token)
        harness.advance(5)
        #expect(provider.ticks == 3)
        #expect(!provider.isRunning)
    }
}

@MainActor
final class TickingProvider: BaseProvider {
    var ticks = 0

    init(clock: any RuntimeClock) {
        super.init(schema: ProviderSchema(id: "ticking", fields: [
            FieldSchema(path: ["count"], type: .number, update: .poll(seconds: 1), doc: ""),
        ], doc: ""), clock: clock)
    }

    override func didChangeDemand() {
        timers.set("tick", every: 1, active: demand.wants("count"), immediately: true) { [weak self] in
            guard let self else { return }
            ticks += 1
            publish("count", .number(Double(ticks)))
        }
    }
}
