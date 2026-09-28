import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class WeatherReportProvider: BaseProvider {
    static let derivedInterval: Double = 60
    static let sourceNames: [String: WeatherProviderID] = ["open-meteo": .openMeteo, "met-norway": .metNorway, "wttr": .wttr]

    private let source: any WeatherSource
    private var place: WeatherPlace?
    private var providerID = WeatherProviderID.standard
    private var report: WeatherReport?
    private var reportSource = WeatherProviderID.standard
    private var fetchedAt: Date?
    private var lastAttemptFailed = false
    private var failures = 0
    private var fetching = false
    private var generation = 0
    private var searchGeneration = 0
    private var searchResults: [GeocodingPlace] = []
    private var searchStatus = "idle"

    public init(source: any WeatherSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("weather"), clock: clock)
    }

    override func didStart() {
        if place != nil, WeatherRefresh.needsFetch(fetchedAt: fetchedAt, now: source.now) { fetch() }
        timers.set("refresh", every: WeatherRefresh.interval, active: true) { [weak self] in
            self?.fetch()
        }
        timers.set("derived", every: Self.derivedInterval, active: true) { [weak self] in
            self?.publishAll()
        }
        publishAll()
    }

    override func didConfigure(_ settings: Record) {
        let wantedPlace = Self.place(settings["place"] ?? .null)
        let wantedProvider = Self.providerID(settings["source"] ?? .null)
        if wantedPlace != place {
            place = wantedPlace
            report = nil
            fetchedAt = nil
            resetAttempts()
            if isRunning, place != nil { fetch() }
        }
        if wantedProvider != providerID {
            providerID = wantedProvider
            resetAttempts()
            if isRunning, place != nil { fetch() }
        }
        publishAll()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "weather.refresh":
            fetch()
        case "weather.search":
            search(try arguments.string(0))
        case "weather.clear-search":
            searchGeneration += 1
            searchResults = []
            searchStatus = "idle"
            publishSearch()
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func resetAttempts() {
        lastAttemptFailed = false
        failures = 0
        fetching = false
        generation += 1
        timers.cancel("retry")
    }

    private func fetch() {
        guard !fetching, let place else { return }
        fetching = true
        let generation = generation
        let id = providerID
        publishAll()
        source.fetch(id, for: place) { [weak self] report in
            guard let self, generation == self.generation else { return }
            self.finish(report, from: id)
        }
    }

    private func finish(_ result: WeatherReport?, from id: WeatherProviderID) {
        fetching = false
        if let result {
            report = result
            reportSource = id
            fetchedAt = source.now
            lastAttemptFailed = false
            failures = 0
        } else {
            failures += 1
            lastAttemptFailed = true
            if isRunning {
                timers.once("retry", after: WeatherRefresh.retryDelay(afterFailures: failures)) { [weak self] in
                    self?.fetch()
                }
            }
        }
        publishAll()
    }

    private func search(_ query: String) {
        searchGeneration += 1
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= OpenMeteoGeocoding.minimumQueryLength else {
            searchResults = []
            searchStatus = "idle"
            publishSearch()
            return
        }
        searchStatus = "searching"
        publishSearch()
        let generation = searchGeneration
        source.search(trimmed) { [weak self] places in
            guard let self, generation == self.searchGeneration else { return }
            self.searchResults = Array((places ?? []).prefix(OpenMeteoGeocoding.count))
            self.searchStatus = places == nil ? "failed" : "done"
            self.publishSearch()
        }
    }

    private var status: String {
        if place == nil { return "no-place" }
        if report != nil { return "ready" }
        if fetching { return "loading" }
        return lastAttemptFailed ? "failed" : "loading"
    }

    private func publishAll() {
        guard isRunning else { return }
        let now = source.now
        publish("status", .string(status))
        publish("place", place.map { .record(Record([("name", .string($0.name)), ("latitude", ProviderValue.number($0.latitude)), ("longitude", ProviderValue.number($0.longitude))])) } ?? .null)
        publish("current", report.map { Self.current($0.current) } ?? .null)
        publish("today", report.flatMap { report in report.today(now: now).map { Self.today($0, report: report) } } ?? .null)
        publish("hourly-strip", .list(report.map { report in report.hourlyStrip(now: now).map { Self.slot($0, report: report) } } ?? []))
        publish("days", .list(report.map { report in report.upcomingDays(now: now).map { Self.day($0, report: report, now: now) } } ?? []))
        publish("updated", fetchedAt.map(Value.date) ?? .null)
        publish("time-zone", report.map { .string($0.calendar.timeZone.identifier) } ?? .null)
        publish("stale", .bool(WeatherRefresh.showsStand(fetchedAt: fetchedAt, lastAttemptFailed: lastAttemptFailed, now: now)))
        let attribution = reportSource.provider().attribution
        publish("attribution", .record(Record([("text", .string(attribution.text)), ("url", .string(attribution.url.absoluteString))])))
        publish("capabilities", Self.capabilities(providerID.provider().capabilities))
        publishSearch()
    }

    private func publishSearch() {
        guard isRunning else { return }
        publish("search-results", .list(searchResults.map(Self.result)))
        publish("search-status", .string(searchStatus))
    }

    static func place(_ value: Value) -> WeatherPlace? {
        guard case .record(let record) = value,
              case .number(let latitude) = record["latitude"] ?? .null, latitude.isFinite,
              case .number(let longitude) = record["longitude"] ?? .null, longitude.isFinite
        else { return nil }
        let name: String
        if case .string(let text) = record["name"] ?? .null { name = text } else { name = "" }
        return WeatherPlace(name: name, latitude: latitude, longitude: longitude)
    }

    static func providerID(_ value: Value) -> WeatherProviderID {
        guard case .string(let name) = value else { return .standard }
        return sourceNames[name] ?? .standard
    }

    static func share(_ percent: Int?) -> Value {
        ProviderValue.number(percent.map { Double($0) / 100 })
    }

    static func current(_ current: CurrentWeather) -> Value {
        .record(Record([
            ("temperature", ProviderValue.number(current.temperature)),
            ("apparent", ProviderValue.number(current.apparentTemperature)),
            ("humidity", share(current.humidity)),
            ("wind", ProviderValue.number(current.windSpeed)),
            ("code", .number(Double(current.code))),
            ("symbol", .string(WeatherCondition.symbol(code: current.code, isDay: current.isDay))),
            ("description", .string(WeatherCondition.description(code: current.code))),
            ("is-day", .bool(current.isDay)),
        ]))
    }

    static func today(_ day: DayForecast, report: WeatherReport) -> Value {
        .record(Record([
            ("min", ProviderValue.number(day.minTemperature)),
            ("max", ProviderValue.number(day.maxTemperature)),
            ("sunrise", day.sunrise.map(Value.date) ?? .null),
            ("sunset", day.sunset.map(Value.date) ?? .null),
            ("sunrise-text", day.sunrise.map { .string(WeatherText.clock($0, calendar: report.calendar)) } ?? .null),
            ("sunset-text", day.sunset.map { .string(WeatherText.clock($0, calendar: report.calendar)) } ?? .null),
        ]))
    }

    static func slot(_ slot: HourSlot, report: WeatherReport) -> Value {
        .record(Record([
            ("time", .date(slot.time)),
            ("time-text", .string(WeatherText.hourLabel(slot.time, isNow: slot.isNow, calendar: report.calendar))),
            ("now", .bool(slot.isNow)),
            ("temperature", ProviderValue.number(slot.temperature)),
            ("symbol", .string(WeatherCondition.symbol(code: slot.code, isDay: slot.isDay))),
            ("precipitation", share(slot.precipitationProbability)),
            ("precipitation-text", .string(WeatherText.precipitation(slot.precipitationProbability) ?? "")),
        ]))
    }

    static func day(_ day: DayForecast, report: WeatherReport, now: Date) -> Value {
        .record(Record([
            ("date", .date(day.date)),
            ("date-text", .string(WeatherText.shortDate(day.date, calendar: report.calendar, locale: report.calendar.locale ?? .current))),
            ("name-text", .string(WeatherText.dayLabel(day.date, today: now, calendar: report.calendar))),
            ("today", .bool(report.calendar.isDate(day.date, inSameDayAs: now))),
            ("min", ProviderValue.number(day.minTemperature)),
            ("max", ProviderValue.number(day.maxTemperature)),
            ("symbol", .string(WeatherCondition.symbol(code: day.code, isDay: true))),
            ("precipitation-text", .string(WeatherText.precipitation(day.precipitationProbability) ?? "")),
        ]))
    }

    static func capabilities(_ capabilities: WeatherCapabilities) -> Value {
        .record(Record([
            ("hour-step", .number(Double(capabilities.hourStep))),
            ("days", .number(Double(capabilities.days))),
            ("precipitation-probability", .bool(capabilities.precipitationProbability)),
            ("apparent-temperature", .bool(capabilities.apparentTemperature)),
            ("sun-times", .string(capabilities.sunTimes == .allDays ? "all-days" : "today-only")),
            ("summary", .string(capabilities.summary)),
        ]))
    }

    static func result(_ place: GeocodingPlace) -> Value {
        .record(Record([
            ("name", .string(place.name)),
            ("region", ProviderValue.string(place.admin1)),
            ("country", ProviderValue.string(place.country)),
            ("latitude", ProviderValue.number(place.latitude)),
            ("longitude", ProviderValue.number(place.longitude)),
        ]))
    }
}
