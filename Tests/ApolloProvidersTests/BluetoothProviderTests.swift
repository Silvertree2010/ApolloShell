import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider bluetooth")
struct BluetoothProviderTests {
    func make(_ source: FakeBluetoothSource = FakeBluetoothSource()) -> (ProviderHarness, FakeBluetoothSource) {
        let harness = ProviderHarness()
        harness.register(BluetoothProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld, Geräte mit Symbol und Akku-Record")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("bluetooth")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("bluetooth")).isEmpty)
        #expect(harness.value("bluetooth", "on") == .bool(true))
        #expect(harness.value("bluetooth", "status") == .string("ready"))
        #expect(harness.value("bluetooth", "paired") == .number(2))
        #expect(harness.value("bluetooth", "connected") == .number(1))
        #expect(harness.value("bluetooth", "devices") == .list([
            .record(Record([
                ("name", .string("AirPods Pro")), ("kind", .string("headphones")), ("symbol", .string("airpodspro")),
                ("battery", .record(Record([("main", .null), ("left", .number(0.8)), ("right", .number(0.75)), ("case", .number(0.4))]))),
            ])),
        ]))
    }

    @Test("Status reading bis zum ersten Ergebnis, unavailable wenn unlesbar")
    func statusFollowsReads() {
        let source = FakeBluetoothSource()
        source.answersImmediately = false
        let (harness, _) = make(source)
        harness.demand("bluetooth", "status", "on")
        #expect(harness.value("bluetooth", "status") == .string("reading"))
        #expect(harness.value("bluetooth", "on") == .null)
        source.finish()
        harness.flush()
        #expect(harness.value("bluetooth", "status") == .string("ready"))
        source.snapshot = nil
        harness.advance(30)
        source.finish()
        harness.flush()
        #expect(harness.value("bluetooth", "status") == .string("unavailable"))
        #expect(harness.value("bluetooth", "on") == .null)
    }

    @Test("Zustand alle 30 s, Geräteliste alle 10 s nur bei Nachfrage, nie zwei Abfragen gleichzeitig")
    func pollingFollowsDemand() {
        let source = FakeBluetoothSource()
        let (harness, _) = make(source)
        harness.advance(100)
        #expect(source.requests == 0)
        let token = harness.demand("bluetooth", "on")
        #expect(source.requests == 1)
        harness.advance(29)
        #expect(source.requests == 1)
        harness.advance(1)
        #expect(source.requests == 2)
        let devices = harness.demand("bluetooth", "devices")
        #expect(source.requests == 3)
        harness.advance(10)
        #expect(source.requests == 4)
        harness.release(devices)
        harness.advance(19)
        #expect(source.requests == 4)

        source.answersImmediately = false
        harness.advance(1)
        #expect(source.requests == 5)
        harness.advance(30)
        #expect(source.requests == 5)
        source.finish()
        harness.release(token)
        harness.advance(100)
        #expect(source.requests == 5)
    }

    @Test("Ergebnis nach dem Stopp wird verworfen")
    func lateResultIsDropped() {
        let source = FakeBluetoothSource()
        source.answersImmediately = false
        let (harness, _) = make(source)
        let token = harness.demand("bluetooth", "on")
        harness.release(token)
        source.finish()
        harness.flush()
        #expect(harness.value("bluetooth", "on") == .null)
    }

    @Test("Ereignis bei Änderung, Aktion öffnet Einstellungen")
    func eventsAndActions() async throws {
        let (harness, source) = make()
        harness.demand("bluetooth", "on")
        #expect(harness.events.isEmpty)
        source.snapshot = StatusPopoutBluetoothSnapshot(powerOn: false, devices: [])
        harness.advance(30)
        #expect(harness.eventNames() == ["bluetooth.changed"])
        _ = try await harness.perform("bluetooth", "bluetooth.open-settings")
        #expect(source.openedSettings == 1)
    }
}
