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

    @Test("places: jeder Ort wird geholt und unter seiner id in by-place geliefert, entfernte Orte verschwinden")
    func byPlace() {
        let zurich = Value.record(Record([("id", .string("z")), ("name", .string("Zürich")), ("latitude", .number(47.37)), ("longitude", .number(8.54))]))
        let churID = Value.record(Record([("id", .string("c")), ("name", .string("Chur")), ("latitude", .number(46.85)), ("longitude", .number(9.53))]))
        let harness = ProviderHarness()
        let source = FakeWeatherSource(clock: harness.clock)
        let provider = WeatherReportProvider(source: source, clock: harness.clock)
        provider.configure(Record([("place", churID), ("places", .list([churID, zurich]))]))
        harness.register(provider)
        harness.demand("weather")
        #expect(source.fetches.map(\.1.name).sorted() == ["Chur", "Chur", "Zürich"])
        #expect(harness.value("weather", "by-place.z.status") == .string("ready"))
        #expect(harness.value("weather", "by-place.z.current.temperature") == .number(14))
        #expect(harness.value("weather", "by-place.c.status") == .string("ready"))
        provider.configure(Record([("place", churID), ("places", .list([churID]))]))
        #expect(harness.value("weather", "by-place.z.status") == .null)
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("weather")).isEmpty)
    }

    static func report(zone: String, locale: String) -> WeatherReport {
        let timeZone = TimeZone(identifier: zone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: FakeWeatherSource.start)
        let hours = (0..<48).map { HourForecast(time: today.addingTimeInterval(Double($0) * 3600), temperature: 10, code: 2, precipitationProbability: nil, isDay: true) }
        let days = (0..<8).map { DayForecast(date: calendar.date(byAdding: .day, value: $0, to: today)!, code: 61, maxTemperature: 18, minTemperature: 7, sunrise: calendar.date(byAdding: .hour, value: 24 * $0 + 6, to: today), sunset: calendar.date(byAdding: .hour, value: 24 * $0 + 18, to: today), precipitationProbability: nil) }
        return WeatherReport(current: CurrentWeather(time: FakeWeatherSource.start, temperature: 14, apparentTemperature: 13, humidity: 50, code: 2, windSpeed: 5, isDay: true), hours: hours, days: days, timeZone: timeZone, locale: Locale(identifier: locale))
    }

    func days(zone: String, locale: String) -> [Record] {
        let (harness, source, _) = make()
        source.answer = Self.report(zone: zone, locale: locale)
        harness.demand("weather")
        guard case .list(let days) = harness.value("weather", "days") else { return [] }
        return days.compactMap { if case .record(let record) = $0 { record } else { nil } }
    }

    @Test("Tagesdatum folgt der Locale wie 0.1.4.2: en_CH 25.9., en_US 9/25")
    func dayDateFollowsLocale() {
        #expect(days(zone: "Europe/Zurich", locale: "en_CH")[1]["date-text"] == .string("25.9."))
        #expect(days(zone: "Europe/Zurich", locale: "de_CH")[1]["date-text"] == .string("25.9."))
        #expect(days(zone: "Europe/Zurich", locale: "en_US")[1]["date-text"] == .string("9/25"))
    }

    @Test("Uhrzeiten und Wochentage folgen der Zeitzone des Orts wie 0.1.4.2, nicht der des Systems", arguments: ["Asia/Tokyo", "America/Los_Angeles", "Europe/Zurich"])
    func timesFollowPlaceZone(zone: String) {
        let (harness, source, _) = make()
        let report = Self.report(zone: zone, locale: "en_US")
        source.answer = report
        harness.demand("weather")
        #expect(harness.value("weather", "time-zone") == .string(zone))
        #expect(harness.value("weather", "today.sunrise-text") == .string("06:00"))
        #expect(harness.value("weather", "today.sunset-text") == .string("18:00"))
        guard case .list(let strip) = harness.value("weather", "hourly-strip"), case .record(let second) = strip[1] else {
            Issue.record("keine Stunden")
            return
        }
        guard case .date(let time)? = second["time"] else { Issue.record("keine Zeit"); return }
        #expect(second["time-text"] == .string("\(report.calendar.component(.hour, from: time)):00"))
        let day = days(zone: zone, locale: "en_US")[1]
        guard case .date(let date)? = day["date"] else { Issue.record("kein Datum"); return }
        #expect(report.calendar.component(.hour, from: date) == 0)
        let weekday = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][report.calendar.component(.weekday, from: date) - 1]
        #expect(day["name-text"] == .string(weekday))
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
