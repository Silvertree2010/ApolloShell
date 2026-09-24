import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Provider weather")
struct WeatherProviderTests {
    static let chur = Value.record(Record([("name", .string("Chur")), ("latitude", .number(46.85)), ("longitude", .number(9.53))]))

    func make(place: Value = chur) -> (ProviderHarness, FakeWeatherSource, WeatherReportProvider) {
        let harness = ProviderHarness()
        let source = FakeWeatherSource(clock: harness.clock)
        let provider = WeatherReportProvider(source: source, clock: harness.clock)
        provider.configure(Record([("place", place)]))
        harness.register(provider)
        return (harness, source, provider)
    }

    @Test("Liefert jedes Registry-Feld, Records vollständig, NaN wird null, Anteile 0…1")
    func deliversAllFields() {
        let (harness, _, _) = make()
        harness.demand("weather")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("weather")).isEmpty)
        #expect(harness.value("weather", "status") == .string("ready"))
        #expect(harness.value("weather", "place.name") == .string("Chur"))
        #expect(harness.value("weather", "current.temperature") == .number(14))
        #expect(harness.value("weather", "current.apparent") == .null)
        #expect(harness.value("weather", "current.humidity") == .number(0.71))
        #expect(harness.value("weather", "current.symbol") == .string("cloud.sun.fill"))
        #expect(harness.value("weather", "today.max") == .number(18))
        guard case .list(let strip) = harness.value("weather", "hourly-strip"), case .list(let days) = harness.value("weather", "days") else {
            Issue.record("keine Listen")
            return
        }
        #expect(strip.count == 12)
        #expect(days.count == 7)
        guard case .record(let first) = strip[0], case .record(let second) = strip[1] else { Issue.record("kein Record"); return }
        #expect(first["now"] == .bool(true))
        #expect(first["precipitation-text"] == .string(""))
        #expect(second["precipitation"] == .number(0.1))
        #expect(harness.value("weather", "updated") == .date(FakeWeatherSource.start))
        #expect(harness.value("weather", "stale") == .bool(false))
        #expect(harness.value("weather", "attribution.text") == .string(OpenMeteoProvider().attribution.text))
        #expect(harness.value("weather", "capabilities.hour-step") == .number(1))
        #expect(harness.value("weather", "search-status") == .string("idle"))
    }

    @Test("Ohne Ort kein Abruf, Status no-place")
    func noPlace() {
        let (harness, source, _) = make(place: .null)
        harness.demand("weather", "status")
        #expect(harness.value("weather", "status") == .string("no-place"))
        #expect(source.fetches.isEmpty)
    }

    @Test("Nur bei Nachfrage: frische Daten nicht neu, nach 15 min neu, dann alle 30 min")
    func refreshRules() {
        let (harness, source, _) = make()
        harness.advance(3600)
        #expect(source.fetches.isEmpty)
        let token = harness.demand("weather", "current")
        #expect(source.fetches.count == 1)
        harness.release(token)
        harness.advance(600)
        let again = harness.demand("weather", "current")
        #expect(source.fetches.count == 1)
        harness.release(again)
        harness.advance(300)
        let third = harness.demand("weather", "current")
        #expect(source.fetches.count == 2)
        harness.advance(1800)
        #expect(source.fetches.count == 3)
        harness.release(third)
        harness.advance(7200)
        #expect(source.fetches.count == 3)
    }

    @Test("Fehlschläge: Wiederholung nach 10, 30, 60, dann 300 s; alte Daten bleiben, stale")
    func retries() {
        let (harness, source, _) = make()
        harness.demand("weather", "status", "stale")
        source.answer = nil
        harness.advance(1800)
        #expect(source.fetches.count == 2)
        #expect(harness.value("weather", "status") == .string("ready"))
        #expect(harness.value("weather", "stale") == .bool(true))
        for (delay, count) in [(10.0, 3), (30.0, 4), (60.0, 5), (300.0, 6), (300.0, 7)] {
            harness.advance(delay - 0.25)
            #expect(source.fetches.count == count - 1)
            harness.advance(0.25)
            #expect(source.fetches.count == count)
        }
    }

    @Test("Erster Abruf scheitert: failed; loading während des Abrufs")
    func loadingAndFailed() {
        let harness = ProviderHarness()
        let source = FakeWeatherSource(clock: harness.clock)
        source.answersImmediately = false
        let provider = WeatherReportProvider(source: source, clock: harness.clock)
        provider.configure(Record([("place", Self.chur)]))
        harness.register(provider)
        harness.demand("weather", "status")
        #expect(harness.value("weather", "status") == .string("loading"))
        source.answer = nil
        source.finish()
        harness.flush()
        #expect(harness.value("weather", "status") == .string("failed"))
        #expect(harness.value("weather", "stale") == .null || harness.value("weather", "stale") == .bool(false))
    }

    @Test("Anbieterwechsel lädt sofort, alte Daten und Quelle bleiben bis neue da sind")
    func providerSwitch() {
        let (harness, source, provider) = make()
        harness.demand("weather", "attribution", "current")
        source.answersImmediately = false
        provider.configure(Record([("place", Self.chur), ("source", .string("met-norway"))]))
        harness.flush()
        #expect(source.fetches.count == 2)
        #expect(source.fetches[1].0 == .metNorway)
        #expect(harness.value("weather", "attribution.text") == .string(OpenMeteoProvider().attribution.text))
        #expect(harness.value("weather", "current.temperature") == .number(14))
        source.finish()
        harness.flush()
        #expect(harness.value("weather", "attribution.text") == .string(WeatherProviderID.metNorway.provider().attribution.text))
        provider.configure(Record([("place", .null), ("source", .string("met-norway"))]))
        harness.flush()
        #expect(harness.value("weather", "status") == .string("no-place"))
        #expect(harness.value("weather", "current") == .null)
    }

    @Test("Ortssuche ab 2 Zeichen, höchstens 5 Treffer, zurücksetzen")
    func search() async throws {
        let (harness, source, _) = make()
        harness.demand("weather", "search-results", "search-status")
        _ = try await harness.perform("weather", "weather.search", [.string("C")])
        #expect(source.searches.isEmpty)
        #expect(harness.value("weather", "search-status") == .string("idle"))
        source.searchAnswer = (1...7).map { GeocodingPlace(id: $0, name: "Ort \($0)", latitude: 1, longitude: 2, admin1: nil, country: "CH") }
        _ = try await harness.perform("weather", "weather.search", [.string("Ch")])
        #expect(harness.value("weather", "search-status") == .string("done"))
        guard case .list(let results) = harness.value("weather", "search-results") else { Issue.record("keine Liste"); return }
        #expect(results.count == 5)
        #expect(results[0] == .record(Record([("name", .string("Ort 1")), ("region", .null), ("country", .string("CH")), ("latitude", .number(1)), ("longitude", .number(2))])))
        source.searchAnswer = nil
        _ = try await harness.perform("weather", "weather.search", [.string("Chur")])
        #expect(harness.value("weather", "search-status") == .string("failed"))
        _ = try await harness.perform("weather", "weather.clear-search")
        #expect(harness.value("weather", "search-results") == .list([]))
        #expect(harness.value("weather", "search-status") == .string("idle"))
        let before = source.fetches.count
        _ = try await harness.perform("weather", "weather.refresh")
        #expect(source.fetches.count == before + 1)
    }
}
