import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider network")
struct NetworkProviderTests {
    func make(_ source: FakeWifiSource = FakeWifiSource()) -> (ProviderHarness, FakeWifiSource) {
        let harness = ProviderHarness()
        harness.register(NetworkProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld mit Logik aus 0.1.4.2")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("network")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("network")).isEmpty)
        #expect(harness.value("network", "wifi.on") == .bool(true))
        #expect(harness.value("network", "wifi.connected") == .bool(true))
        #expect(harness.value("network", "wifi.bars") == .number(3))
        #expect(harness.value("network", "wifi.quality") == .string("Excellent"))
        #expect(harness.value("network", "wifi.snr") == .number(40))
        #expect(harness.value("network", "wifi.tx-rate") == .number(866))
        #expect(harness.value("network", "wifi.standard") == .string("Wi-Fi 6 (802.11ax)"))
        #expect(harness.value("network", "wifi.band") == .string("5 GHz"))
        #expect(harness.value("network", "wifi.channel") == .string("36"))
        #expect(harness.value("network", "wifi.interface") == .string("en0"))
        #expect(harness.value("network", "wifi.symbol") == .string("wifi"))
    }

    @Test("Ohne WLAN-Interface: on null, Details null")
    func noInterface() {
        let (harness, _) = make(FakeWifiSource(nil))
        harness.demand("network")
        #expect(harness.value("network", "wifi.on") == .null)
        #expect(harness.value("network", "wifi.connected") == .bool(false))
        #expect(harness.value("network", "wifi.symbol") == .string("wifi.slash"))
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("network")).isEmpty)
    }

    @Test("Grundwerte alle 5 s, Details alle 2 s nur bei Nachfrage")
    func pollingFollowsDemand() {
        let (harness, source) = make()
        harness.advance(30)
        #expect(source.reads == 0)
        let token = harness.demand("network", "wifi.symbol")
        let reads = source.reads
        harness.advance(4.9)
        #expect(source.reads == reads)
        harness.advance(0.1)
        #expect(source.reads == reads + 1)
        #expect(harness.value("network", "wifi.rssi") == .null)

        let details = harness.demand("network", "wifi.rssi")
        #expect(harness.value("network", "wifi.rssi") == .number(-52))
        let withDetails = source.reads
        harness.advance(2)
        #expect(source.reads == withDetails + 1)
        harness.release(details)
        let afterDetails = source.reads
        harness.advance(2.9)
        #expect(source.reads == afterDetails)
        harness.release(token)
        harness.advance(60)
        #expect(source.reads == afterDetails)
    }

    @Test("Aktionen schalten WLAN, Ereignis bei Zustandswechsel")
    func actionsAndEvents() async throws {
        let (harness, source) = make()
        harness.demand("network", "wifi.on")
        #expect(harness.events.isEmpty)
        _ = try await harness.perform("network", "network.toggle-wifi")
        #expect(source.powerCalls == [false])
        #expect(harness.value("network", "wifi.on") == .bool(false))
        #expect(harness.eventNames() == ["network.wifi-changed"])
        _ = try await harness.perform("network", "network.set-wifi", [.bool(true)])
        #expect(source.powerCalls == [false, true])
        _ = try await harness.perform("network", "network.open-settings")
        #expect(source.openedSettings == 1)
    }

    @Test("Schalten ohne Interface warnt statt zu werfen")
    func switchingWithoutInterfaceWarns() async throws {
        let (harness, _) = make(FakeWifiSource(nil))
        harness.demand("network", "wifi.on")
        _ = try await harness.perform("network", "network.set-wifi", [.bool(true)])
        #expect(harness.warnings.count == 1)
    }
}
