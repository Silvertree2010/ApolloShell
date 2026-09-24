import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("BindingEngine")
struct BindingEngineTests {
    func makeEngine() -> (SignalStore, ManualFlushScheduler, BindingEngine) {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        return (store, scheduler, engine)
    }

    @Test("Ein Binding wird nur bei Änderung einer Abhängigkeit neu ausgewertet")
    func onlyReevaluatesOnDependencyChange() {
        let (store, _, engine) = makeEngine()
        var values: [Value] = []
        let handle = engine.bind(BindingTestHarness.source("{perf.cpu}"), scope: LocalScope(), active: true) { values.append($0) }
        #expect(handle.currentValue == .null)
        #expect(values.count == 1)

        store.set(DependencyPath("other", ["field"]), .number(1))
        engine.flush()
        #expect(values.count == 1)

        store.set(DependencyPath("perf", ["cpu"]), .number(0.5))
        engine.flush()
        #expect(values.count == 2)
        #expect(handle.currentValue == .number(0.5))
    }

    @Test("100 Änderungen in einem Durchlauf ergeben genau eine Auswertung je Binding")
    func batchedChangesEvaluateOnce() {
        let (store, _, engine) = makeEngine()
        var callCount = 0
        let handle = engine.bind(BindingTestHarness.source("{perf.cpu}"), scope: LocalScope(), active: true) { _ in callCount += 1 }
        callCount = 0

        for index in 0..<100 {
            store.set(DependencyPath("perf", ["cpu"]), .number(Double(index)))
        }
        engine.flush()
        #expect(callCount == 1)
        #expect(handle.currentValue == .number(99))
    }

    @Test("list[i] hängt an list und i")
    func listIndexDependsOnBothPaths() {
        let source = BindingTestHarness.source("{list[i]}")
        #expect(source.dependencies.contains(DependencyPath("list", [])))
        #expect(source.dependencies.contains(DependencyPath("i", [])))
    }

    @Test("relative hängt an clock.now")
    func relativeDependsOnClockNow() {
        let source = BindingTestHarness.source("{value | relative}", locals: ["value"])
        #expect(source.dependencies.contains(DependencyPath("clock", ["now"])))
    }

    @Test("Rang-Reihenfolge: abgeleitete var vor Struktur vor Properties")
    func rankOrderingDuringFlush() {
        let (store, _, engine) = makeEngine()
        var order: [String] = []

        engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), rank: .property, active: true) { _ in order.append("property") }
        engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), rank: .structure(depth: 2), active: true) { _ in order.append("structure") }
        engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), rank: .derived(order: 0), active: true) { _ in order.append("derived") }
        order.removeAll()

        store.set(DependencyPath("shared", ["value"]), .number(1))
        engine.flush()

        #expect(order == ["derived", "structure", "property"])
    }

    @Test("Reentranz: onChange setzt ein Signal, das im selben Flush ankommt")
    func reentrantWriteSettlesInSameFlush() {
        let (store, _, engine) = makeEngine()
        var secondaryValues: [Value] = []

        engine.bind(BindingTestHarness.source("{trigger.value}"), scope: LocalScope(), active: true) { value in
            store.set(DependencyPath("downstream", ["value"]), value)
        }
        let secondary = engine.bind(BindingTestHarness.source("{downstream.value}"), scope: LocalScope(), active: true) { secondaryValues.append($0) }
        secondaryValues.removeAll()

        store.set(DependencyPath("trigger", ["value"]), .number(42))
        engine.flush()

        #expect(secondaryValues == [.number(42)])
        #expect(secondary.currentValue == .number(42))
    }

    @Test("Endlos-Anstoss endet nach 8 Runden mit Warnung")
    func infiniteBounceStopsAfterEightRounds() {
        let (store, _, engine) = makeEngine()
        var warnings: [Diagnostic] = []
        engine.onWarning = { warnings.append($0) }
        var evaluations = 0

        engine.bind(BindingTestHarness.source("{loop.value}"), scope: LocalScope(), active: true) { value in
            evaluations += 1
            let next: Double = { if case .number(let number) = value { number + 1 } else { 1 } }()
            store.set(DependencyPath("loop", ["value"]), .number(next))
        }
        evaluations = 0

        store.set(DependencyPath("loop", ["value"]), .number(0))
        engine.flush()

        #expect(evaluations == 8)
        #expect(warnings.count == 1)
    }

    @Test("Verschachteltes flush() kehrt sofort zurück")
    func nestedFlushReturnsImmediately() {
        let (store, _, engine) = makeEngine()
        var callCount = 0
        engine.bind(BindingTestHarness.source("{signal.value}"), scope: LocalScope(), active: true) { _ in
            callCount += 1
            engine.flush()
        }
        callCount = 0

        store.set(DependencyPath("signal", ["value"]), .number(1))
        engine.flush()

        #expect(callCount == 1)
    }

    @Test("Beendetes Binding in der Warteschlange wird nicht ausgewertet")
    func cancelledBindingSkipsEvaluation() {
        let (store, _, engine) = makeEngine()
        var firstCount = 0
        var secondCount = 0
        let first = engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), active: true) { _ in firstCount += 1 }
        engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), active: true) { _ in secondCount += 1 }
        firstCount = 0
        secondCount = 0

        first.cancel()
        store.set(DependencyPath("shared", ["value"]), .number(9))
        engine.flush()

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    @Test("10 000 Bindings: ein geändertes Signal wertet genau die Abonnenten aus")
    func tenThousandBindingsEvaluateOnlySubscribers() {
        let (store, _, engine) = makeEngine()
        for index in 0..<10_000 {
            engine.bind(BindingTestHarness.source("{isolated.field\(index)}"), scope: LocalScope(), active: true) { _ in }
        }
        var sharedHits = 0
        for _ in 0..<5 {
            engine.bind(BindingTestHarness.source("{shared.value}"), scope: LocalScope(), active: true) { _ in sharedHits += 1 }
        }
        sharedHits = 0
        let before = engine.evaluationCount

        store.set(DependencyPath("shared", ["value"]), .number(1))
        engine.flush()

        #expect(sharedHits == 5)
        #expect(engine.evaluationCount - before == 5)
    }

    @Test("Ein inaktives, schmutziges Binding wird beim Aktivieren neu ausgewertet")
    func inactiveBindingEvaluatesOnActivation() {
        let (store, _, engine) = makeEngine()
        var values: [Value] = []
        let handle = engine.bind(BindingTestHarness.source("{perf.cpu}"), scope: LocalScope(), active: false) { values.append($0) }
        #expect(values.isEmpty)

        store.set(DependencyPath("perf", ["cpu"]), .number(0.7))
        engine.flush()
        #expect(values.isEmpty)
        #expect(handle.currentValue == .null)

        handle.isActive = true
        #expect(values == [.number(0.7)])
        #expect(handle.currentValue == .number(0.7))
    }

    @Test("self.* wird auf self:<identity> umgeschrieben")
    func selfRootIsRewritten() {
        let (store, _, engine) = makeEngine()
        var values: [Value] = []
        let scope = LocalScope().adding("$self", .string("abc"))
        engine.bind(BindingTestHarness.source("{self.hover}"), scope: scope, active: true) { values.append($0) }
        values.removeAll()

        store.set(DependencyPath("self:abc", ["hover"]), .bool(true))
        engine.flush()

        #expect(values == [.bool(true)])
    }
}
