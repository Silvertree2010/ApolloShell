import Testing
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("ProviderHost")
struct ProviderHostTests {
    func makeHost() -> (SignalStore, ManualFlushScheduler, ProviderHost) {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let host = ProviderHost(store: store)
        return (store, scheduler, host)
    }

    @Test("Provider ohne Nachfrage und ohne on startet nie")
    func neverStartsWithoutDemand() {
        let (_, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        scheduler.runPending()
        #expect(provider.startCount == 0)
    }

    @Test("Erste Nachfrage startet den Provider, Ende der Nachfrage stoppt ihn")
    func startsOnDemandAndStopsWithoutIt() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        scheduler.runPending()

        let token = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        scheduler.runPending()
        #expect(provider.startCount == 1)
        #expect(provider.stopCount == 0)
        #expect(provider.lastDemand == [DependencyPath("perf", ["cpu"])])

        store.unsubscribe(token)
        scheduler.runPending()
        #expect(provider.stopCount == 1)
    }

    @Test("Zehnmal auf und zu in einem Durchlauf ergibt höchstens eine Meldung")
    func rapidToggleWithinOnePassCoalesces() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        scheduler.runPending()

        for _ in 0..<10 {
            let token = store.subscribe(DependencyPath("perf", ["cpu"])) {}
            store.unsubscribe(token)
        }
        scheduler.runPending()

        #expect(provider.startCount <= 1)
        #expect(provider.stopCount <= 1)
    }

    @Test("on hält die Quelle wach ohne Binding")
    func keepAwakeStartsWithoutBinding() {
        let (_, scheduler, host) = makeHost()
        let provider = StubProvider(id: "wifi")
        host.register(provider)
        let token = host.keepAwake("wifi")
        scheduler.runPending()

        #expect(provider.startCount == 1)

        host.unsubscribe(token)
        scheduler.runPending()
        #expect(provider.stopCount == 1)
    }

    @Test("demandChanged wird nur bei echter Änderung der Felder aufgerufen")
    func demandChangedFiresOnlyOnRealFieldChange() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "apps")
        host.register(provider)
        let first = store.subscribe(DependencyPath("apps", ["running"])) {}
        scheduler.runPending()
        #expect(provider.demandChangedCount == 1)

        let second = store.subscribe(DependencyPath("apps", ["running"])) {}
        scheduler.runPending()
        #expect(provider.demandChangedCount == 1)

        store.unsubscribe(first)
        store.unsubscribe(second)
        scheduler.runPending()
        #expect(provider.stopCount == 1)
    }

    @Test("publish schreibt Felder unter der Provider-Wurzel in den Store")
    func publishWritesUnderProviderRoot() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        store.subscribe(DependencyPath("perf", ["cpu"])) {}
        scheduler.runPending()

        provider.lastContext?.publish(["cpu"], .number(0.42))
        #expect(store.value(DependencyPath("perf", ["cpu"])) == .number(0.42))
    }

    @Test("Werte eines gestoppten Providers bleiben stehen")
    func stoppedProviderValuesRemainVisible() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        let token = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        scheduler.runPending()
        provider.lastContext?.publish(["cpu"], .number(0.9))

        store.unsubscribe(token)
        scheduler.runPending()
        #expect(provider.stopCount == 1)
        #expect(store.value(DependencyPath("perf", ["cpu"])) == .number(0.9))
    }

    @Test("emit ruft onEvent mit dem Ereignis auf")
    func emitForwardsToOnEvent() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "apps")
        host.register(provider)
        var events: [(String, Record)] = []
        host.onEvent = { events.append(($0, $1)) }
        store.subscribe(DependencyPath("apps", ["running"])) {}
        scheduler.runPending()

        provider.lastContext?.emit("apps.launched", Record([("id", .string("com.test"))]))
        #expect(events.count == 1)
        #expect(events.first?.0 == "apps.launched")
    }

    @Test("Zähler laufender Provider für apollo stats")
    func runningProviderCountReflectsState() {
        let (store, scheduler, host) = makeHost()
        let provider = StubProvider(id: "perf")
        host.register(provider)
        #expect(host.runningProviderCount == 0)

        let token = store.subscribe(DependencyPath("perf", ["cpu"])) {}
        scheduler.runPending()
        #expect(host.runningProviderCount == 1)

        store.unsubscribe(token)
        scheduler.runPending()
        #expect(host.runningProviderCount == 0)
    }
}
