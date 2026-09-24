import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Skript-Quellen poll und listen")
struct ScriptSourcesTests {
    func make(_ kind: ScriptKind, _ specs: [ScriptSourceSpec]) -> (ProviderHarness, FakeScriptRunner, ScriptSourcesProvider) {
        let harness = ProviderHarness()
        let runner = FakeScriptRunner(clock: harness.clock)
        let provider = ScriptSourcesProvider(kind: kind, sources: specs, runner: runner, clock: harness.clock)
        harness.register(provider)
        return (harness, runner, provider)
    }

    @Test("Vorgaben: interval 5 s, mindestens 500 ms, timeout 10 s, format text")
    func defaults() {
        let spec = ScriptSourceSpec(name: "vpn", command: "true")
        #expect(spec.interval == 5)
        #expect(spec.timeout == 10)
        #expect(spec.format == .text)
        #expect(ScriptSourceSpec(name: "x", command: "true", interval: 0.1).interval == 0.5)
    }

    @Test("poll: nur solange gefragt, Takt, Text ohne Zeilenumbruch, Initialwert, Felder im Schema")
    func pollRunsOnDemand() {
        let (harness, runner, provider) = make(.poll, [ScriptSourceSpec(name: "vpn", command: "scutil", interval: 10, initial: .string("?"), timeout: 30)])
        #expect(provider.schema.fields.map(\.path) == [["vpn"], ["vpn-error"]])
        harness.advance(30)
        #expect(runner.runs.isEmpty)
        runner.answersImmediately = false
        let token = harness.demand("poll", "vpn")
        #expect(harness.value("poll", "vpn") == .string("?"))
        #expect(harness.conformanceProblems(provider.schema).isEmpty)
        runner.last.completion?(0, "connected\n")
        harness.flush()
        #expect(harness.value("poll", "vpn") == .string("connected"))
        #expect(harness.value("poll", "vpn-error") == .null)
        harness.advance(10)
        #expect(runner.runs.count == 2)
        harness.advance(10)
        #expect(runner.runs.count == 2)
        runner.last.completion?(0, "down")
        harness.release(token)
        harness.advance(30)
        #expect(runner.runs.count == 2)
    }

    @Test("poll: Zeitlimit beendet den Prozess, alter Wert bleibt, Fehler gesetzt; Exit-Status ungleich 0")
    func pollTimeout() {
        let (harness, runner, _) = make(.poll, [ScriptSourceSpec(name: "slow", command: "sleep 99", interval: 60, timeout: 2)])
        harness.demand("poll", "slow")
        #expect(harness.value("poll", "slow") == .string("connected"))
        runner.answersImmediately = false
        harness.advance(60)
        harness.advance(2)
        #expect(runner.last.terminated)
        #expect(harness.value("poll", "slow") == .string("connected"))
        #expect(harness.value("poll", "slow-error") == .string("timed out after 2s"))
        runner.last.completion?(0, "late")
        harness.flush()
        #expect(harness.value("poll", "slow") == .string("connected"))
        runner.answersImmediately = true
        runner.status = 3
        harness.advance(60)
        #expect(harness.value("poll", "slow-error") == .string("exit status 3"))
        #expect(harness.value("poll", "slow") == .string("connected"))
    }

    @Test("Formate json und lines, ungültiges JSON ergibt null und Fehler")
    func formats() {
        let (harness, runner, _) = make(.poll, [
            ScriptSourceSpec(name: "brew", command: "brew", format: .json),
            ScriptSourceSpec(name: "files", command: "ls", format: .lines),
        ])
        runner.output = "{\"count\": 3, \"ok\": true}"
        harness.demand("poll", "brew")
        #expect(harness.value("poll", "brew.count") == .number(3))
        #expect(harness.value("poll", "brew.ok") == .bool(true))
        runner.output = "a\nb\n"
        harness.demand("poll", "files")
        #expect(harness.value("poll", "files") == .list([.string("a"), .string("b")]))
        runner.output = "{nope"
        harness.advance(5)
        #expect(harness.value("poll", "brew") == .null)
        #expect(harness.value("poll", "brew-error") != .null)
    }

    @Test("when schaltet die Quelle ab und wieder an")
    func whenCondition() {
        let (harness, runner, provider) = make(.poll, [ScriptSourceSpec(name: "vpn", command: "scutil")])
        provider.configure(Record([("vpn", .record(Record([("when", .bool(false))])))]))
        harness.demand("poll", "vpn")
        #expect(runner.runs.isEmpty)
        provider.configure(Record([("vpn", .record(Record([("when", .bool(true))])))]))
        harness.flush()
        #expect(runner.runs.count == 1)
    }

    @Test("listen: jede Zeile ein Wert, Neustart nach 2…32 s, Aufgeben nach fünf frühen Enden, Stopp beendet")
    func listenRestarts() {
        let (harness, runner, _) = make(.listen, [ScriptSourceSpec(name: "space", command: "watch.sh", format: .json)])
        #expect(runner.runs.isEmpty)
        let token = harness.demand("listen", "space")
        #expect(runner.runs.count == 1)
        runner.last.onLine?("{\"index\": 2}")
        harness.flush()
        #expect(harness.value("listen", "space.index") == .number(2))
        for (attempt, delay) in [2.0, 4, 8, 16, 32].enumerated() {
            runner.last.onExit?(1)
            harness.advance(delay - 0.25)
            #expect(runner.runs.count == attempt + 1)
            harness.advance(0.25)
            #expect(runner.runs.count == attempt + 2)
        }
        runner.last.onExit?(1)
        harness.advance(100)
        #expect(runner.runs.count == 6)
        #expect(harness.value("listen", "space-error") != .null)
        harness.release(token)
        let again = harness.demand("listen", "space")
        #expect(runner.runs.count == 7)
        harness.release(again)
        #expect(runner.last.terminated)
    }
}
