import Testing
import Foundation
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider clock")
struct ClockProviderTests {
    func make(_ base: String = "2026-09-24T07:41:30Z") -> (ProviderHarness, FakeClockSource) {
        let harness = ProviderHarness()
        let source = FakeClockSource(clock: harness.clock, base: base)
        harness.register(ClockProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld mit passendem Typ, Wochentag 1 = Montag")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("clock")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("clock")).isEmpty)
        #expect(harness.value("clock", "hour") == .number(9))
        #expect(harness.value("clock", "minute") == .number(41))
        #expect(harness.value("clock", "second") == .number(30))
        #expect(harness.value("clock", "day") == .number(24))
        #expect(harness.value("clock", "month") == .number(9))
        #expect(harness.value("clock", "year") == .number(2026))
        #expect(harness.value("clock", "weekday") == .number(4))
        #expect(harness.value("clock", "time-zone") == .string("Europe/Zurich"))
    }

    @Test("Sonntag ist Wochentag 7")
    func sundayIsSeven() {
        let (harness, _) = make("2026-09-27T10:00:00Z")
        harness.demand("clock", "weekday")
        #expect(harness.value("clock", "weekday") == .number(7))
    }

    @Test("Ohne Sekunden-Nachfrage tickt die Uhr zur vollen Minute")
    func ticksOnFullMinute() {
        let (harness, source) = make()
        harness.demand("clock", "minute")
        harness.advance(29.5)
        #expect(harness.value("clock", "minute") == .number(41))
        let reads = source.reads
        harness.advance(0.6)
        #expect(harness.value("clock", "minute") == .number(42))
        harness.advance(30)
        #expect(source.reads == reads + 1)
        harness.advance(30)
        #expect(harness.value("clock", "minute") == .number(43))
    }

    @Test("Mit Nachfrage nach second tickt die Uhr jede Sekunde, danach wieder minütlich")
    func ticksEverySecondWhileSecondIsDemanded() {
        let (harness, source) = make()
        harness.demand("clock", "minute")
        let token = harness.demand("clock", "second")
        harness.advance(1.01)
        #expect(harness.value("clock", "second") == .number(31))
        harness.advance(1.005)
        #expect(harness.value("clock", "second") == .number(32))
        harness.release(token)
        let reads = source.reads
        harness.advance(20)
        #expect(source.reads == reads)
        harness.advance(10)
        #expect(source.reads == reads + 1)
    }

    @Test("Zeitzonenwechsel wird sofort geliefert")
    func timeZoneChangeIsPushed() {
        let (harness, source) = make()
        harness.demand("clock", "hour", "time-zone")
        source.changeTimeZone("Asia/Tokyo")
        harness.flush()
        #expect(harness.value("clock", "time-zone") == .string("Asia/Tokyo"))
        #expect(harness.value("clock", "hour") == .number(16))
    }

    @Test("Ohne Nachfrage läuft nichts, Stopp beendet Takt und Beobachter")
    func startsAndStopsWithDemand() {
        let (harness, source) = make()
        harness.advance(120)
        #expect(source.reads == 0)
        #expect(!source.observing)
        let token = harness.demand("clock", "minute")
        #expect(source.observing)
        harness.release(token)
        #expect(!source.observing)
        let reads = source.reads
        harness.advance(600)
        #expect(source.reads == reads)
    }
}
