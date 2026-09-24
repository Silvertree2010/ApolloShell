import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider perf")
struct PerfProviderTests {
    func make() -> (ProviderHarness, FakePerfSource) {
        let harness = ProviderHarness()
        let source = FakePerfSource(clock: harness.clock)
        harness.register(PerfProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld nach zwei Messungen")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("perf")
        harness.advance(2)
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("perf")).isEmpty)
        #expect(harness.value("perf", "cpu") == .number(0.42))
        #expect(harness.value("perf", "memory") == .number(0.61))
        #expect(harness.value("perf", "net-down") == .number(2000))
        #expect(harness.value("perf", "live.cpu") == .number(0.42))
        #expect(harness.value("perf", "live.gpu") == .number(0.25))
        #expect(harness.value("perf", "live.disk") == .number(0.5))
        #expect(harness.value("perf", "live.net-down") == .number(2000))
        #expect(harness.value("perf", "chip") == .string("Apple M4 Pro"))
        #expect(harness.value("perf", "cores") == .number(14))
        #expect(harness.value("perf", "gpu-cores") == .number(20))
    }

    @Test("Leiste alle 2 s ohne GPU und Platte, live jede Sekunde mit")
    func twoRates() {
        let (harness, source) = make()
        harness.advance(10)
        #expect(source.requests.isEmpty)
        let bar = harness.demand("perf", "cpu")
        #expect(source.requests == [PerfSampleRequest(gpu: false, disk: false)])
        harness.advance(1)
        #expect(source.requests.count == 1)
        harness.advance(1)
        #expect(source.requests.count == 2)
        let live = harness.demand("perf", "live.cpu")
        let before = source.requests.count
        harness.advance(1)
        #expect(source.requests.count == before + 1)
        #expect(source.requests.last == PerfSampleRequest(gpu: true, disk: true))
        harness.release(live)
        harness.release(bar)
        let after = source.requests.count
        harness.advance(60)
        #expect(source.requests.count == after)
    }

    @Test("Verläufe beginnen bei neuer Nachfrage leer, höchstens 30 Werte, Gesamtzähler bleibt")
    func historiesResetTotalsStay() {
        let (harness, _) = make()
        let live = harness.demand("perf", "live")
        harness.advance(40)
        guard case .list(let history) = harness.value("perf", "live.cpu-history") else {
            Issue.record("Verlauf fehlt")
            return
        }
        #expect(history.count == 30)
        guard case .list(let net) = harness.value("perf", "live.net-history") else {
            Issue.record("Netzverlauf fehlt")
            return
        }
        #expect(net.last == .record(Record([("down", .number(2000)), ("up", .number(1000))])))
        guard case .number(let total) = harness.value("perf", "live.net-total-down") else {
            Issue.record("Gesamtzähler fehlt")
            return
        }
        #expect(total == 80000)
        harness.release(live)
        harness.advance(10)
        harness.demand("perf", "live")
        #expect(harness.value("perf", "live.cpu-history") == .list([]))
        guard case .number(let resumed) = harness.value("perf", "live.net-total-down") else {
            Issue.record("Gesamtzähler fehlt")
            return
        }
        #expect(resumed >= total)
    }
}
