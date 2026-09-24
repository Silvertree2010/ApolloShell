import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider battery")
struct BatteryProviderTests {
    func make(_ reading: BatteryReading? = BatteryReading(level: 76, charging: false, onAC: false, minutesToEmpty: 185)) -> (ProviderHarness, FakeBatterySource) {
        let harness = ProviderHarness()
        let source = FakeBatterySource(reading)
        harness.register(BatteryProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld mit Texten aus 0.1.4.2")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("battery")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("battery")).isEmpty)
        #expect(harness.value("battery", "present") == .bool(true))
        #expect(harness.value("battery", "percent") == .number(0.76))
        #expect(harness.value("battery", "on-power") == .bool(false))
        #expect(harness.value("battery", "full") == .bool(false))
        #expect(harness.value("battery", "minutes-to-empty") == .number(185))
        #expect(harness.value("battery", "minutes-to-full") == .null)
        #expect(harness.value("battery", "state-text") == .string("Battery"))
        #expect(harness.value("battery", "time-text") == .string("3h 5m Left"))
        #expect(harness.value("battery", "symbol") == .string("battery.75percent"))
        #expect(harness.value("battery", "health") == .number(0.91))
        #expect(harness.value("battery", "cycles") == .number(312))
        #expect(harness.value("battery", "low-power-mode") == .bool(false))
        #expect(harness.value("battery", "tank-text") != .null)
    }

    @Test("Laden: Symbol mit Blitz, Zeit bis voll, voll am Netz")
    func chargingTexts() {
        let (harness, source) = make(BatteryReading(level: 40, charging: true, onAC: true, minutesToFull: 50))
        harness.demand("battery", "symbol", "state-text", "time-text", "full")
        #expect(harness.value("battery", "symbol") == .string("battery.100percent.bolt"))
        #expect(harness.value("battery", "state-text") == .string("Charging"))
        #expect(harness.value("battery", "time-text") == .string("Full in 50m"))
        source.change { $0 = BatteryReading(level: 100, charging: false, onAC: true, charged: true) }
        harness.flush()
        #expect(harness.value("battery", "full") == .bool(true))
        #expect(harness.value("battery", "time-text") == .string("Fully Charged"))
    }

    @Test("Ohne Akku: present falsch, Stand null")
    func noBattery() {
        let (harness, _) = make(nil)
        harness.demand("battery")
        #expect(harness.value("battery", "present") == .bool(false))
        #expect(harness.value("battery", "percent") == .null)
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("battery"), strict: false).isEmpty)
    }

    @Test("Grundwerte push plus alle 60 s, Details alle 2 s nur bei Nachfrage")
    func pollingFollowsDemand() {
        let (harness, source) = make()
        harness.advance(120)
        #expect(source.reads == 0)
        let token = harness.demand("battery", "percent")
        #expect(source.observing)
        let reads = source.reads
        harness.advance(59)
        #expect(source.reads == reads)
        harness.advance(1)
        #expect(source.reads == reads + 1)
        #expect(source.detailReads == 0)

        let details = harness.demand("battery", "health")
        #expect(source.detailReads == 1)
        harness.advance(2)
        harness.advance(2)
        #expect(source.detailReads == 3)
        harness.release(details)
        harness.advance(10)
        #expect(source.detailReads == 3)

        source.change { $0.level = 70 }
        harness.flush()
        #expect(harness.value("battery", "percent") == .number(0.7))

        harness.release(token)
        #expect(!source.observing)
        let after = source.reads
        harness.advance(600)
        #expect(source.reads == after)
    }

    @Test("Ereignisse: Warnstufen im Akkubetrieb, Ladegerät an und ab, erster Wert zählt nicht")
    func events() {
        let (harness, source) = make(BatteryReading(level: 21, charging: false, onAC: false))
        let awake = harness.keepAwake("battery")
        #expect(harness.events.isEmpty)
        source.change { $0.level = 20 }
        source.change { $0.level = 19 }
        source.change { $0.level = 10 }
        #expect(harness.eventNames() == ["battery.warning", "battery.warning"])
        let first = harness.events[0].fields
        #expect(first["level"] == .string("20"))
        #expect(first["percent"] == .number(0.2))
        #expect(first["title"] == .string("Low Battery"))
        #expect(first["critical"] == .bool(false))
        source.change { $0.onAC = true; $0.charging = true }
        source.change { $0.onAC = false; $0.charging = false; $0.level = 5 }
        #expect(harness.eventNames().suffix(3) == ["battery.charger-connected", "battery.charger-disconnected", "battery.warning"])
        #expect(harness.events.last?.fields["critical"] == .bool(true))
        harness.releaseAwake(awake)
        #expect(!source.observing)
    }
}
