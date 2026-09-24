import Testing
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("SignalStore Nachfrage")
struct SignalStoreDemandTests {
    @Test("Aktives Binding fragt ein Feld, inaktives nicht")
    func activeSubscriptionCountsAsDemand() {
        let store = SignalStore(scheduler: ManualFlushScheduler())
        #expect(store.demandedPaths(root: "perf").isEmpty)

        let token = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        #expect(store.demandedPaths(root: "perf") == [DependencyPath("perf", ["cpu"])])

        store.unsubscribe(token)
        #expect(store.demandedPaths(root: "perf").isEmpty)
    }

    @Test("Zwei Leser, einer geht: weiter gefragt")
    func remainsInDemandWithOneReaderLeft() {
        let store = SignalStore(scheduler: ManualFlushScheduler())
        let first = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        let second = store.subscribe(DependencyPath("perf", ["cpu"])) {}

        store.unsubscribe(first)
        #expect(store.demandedPaths(root: "perf") == [DependencyPath("perf", ["cpu"])])

        store.unsubscribe(second)
        #expect(store.demandedPaths(root: "perf").isEmpty)
    }

    @Test("demand(_:) fragt mehrere Felder ohne Rückruf")
    func demandGroupTracksMultiplePaths() {
        let store = SignalStore(scheduler: ManualFlushScheduler())
        let token = store.demand([DependencyPath("apps", ["running"]), DependencyPath("apps", ["dock"])])

        #expect(store.demandedPaths(root: "apps") == [DependencyPath("apps", ["running"]), DependencyPath("apps", ["dock"])])

        store.unsubscribe(token)
        #expect(store.demandedPaths(root: "apps").isEmpty)
    }

    @Test("Nachfrage-Beobachter feuert nur bei echter Änderung der Menge, je Wurzel")
    func demandObserverFiresOnlyOnRealChange() {
        let store = SignalStore(scheduler: ManualFlushScheduler())
        var changes: [String] = []
        store.addDemandObserver { changes.append($0) }

        let a = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        let b = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        #expect(changes == ["perf"])

        store.unsubscribe(a)
        #expect(changes == ["perf"])

        store.unsubscribe(b)
        #expect(changes == ["perf", "perf"])
    }
}
