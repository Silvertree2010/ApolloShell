import Foundation

// Weather for the Dashboard (Caelestia: services/Weather.qml). Data from
// Open-Meteo (default, same source as Caelestia) or one of the other
// providers in WeatherProvider.swift - all without a key or account.
// Pure logic only here - fetching and UI live in the app.

// MARK: - Location

/// What the weather applies to. Fixed instead of CoreLocation: locating
/// would show a permission dialog. No more fixed location - instead
/// self-created favorites (see `WeatherFavorites`), stored in weather.json.
public struct WeatherLocation: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Favorites

/// Self-created locations (Nexus > Dashboard): an ordered list plus the
/// selected one, stored in weather.json. Fresh install: empty, no selected
/// location - only a favorite makes the weather fetchable.
public struct WeatherFavorites: Equatable, Sendable {
    public var locations: [WeatherLocation]
    public var selectedID: WeatherLocation.ID?

    public init(locations: [WeatherLocation] = [], selectedID: WeatherLocation.ID? = nil) {
        self.locations = locations
        self.selectedID = selectedID
    }

    public static let empty = WeatherFavorites()

    public var selected: WeatherLocation? {
        guard let selectedID else { return nil }
        return locations.first { $0.id == selectedID }
    }

    /// New favorite added at the end - not duplicated if one with the same
    /// coordinates already exists (the same location search always returns
    /// the same numbers for the same place). The first favorite is selected
    /// right away. `false` if it was already there - the list then stays
    /// unchanged.
    @discardableResult
    public mutating func add(_ location: WeatherLocation) -> Bool {
        guard !locations.contains(where: { $0.sameCoordinates(as: location) }) else { return false }
        locations.append(location)
        if selectedID == nil { selectedID = location.id }
        return true
    }

    /// Removes a favorite. If it was the selected one, none is selected
    /// afterward - the caller (Nexus, weather tab) decides whether and what
    /// to select manually.
    public mutating func remove(id: WeatherLocation.ID) {
        locations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    /// Like SwiftUI's `onMove`: `destination` counts in the list BEFORE the
    /// move ("insert before row n"), see `Array.move` in Reorder.swift -
    /// `move(fromOffsets:toOffset:)` itself belongs to SwiftUI, and
    /// ApolloShellCore stays without a UI.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        locations.move(fromOffsets: source, toOffset: destination)
    }

    /// Only an existing favorite can be selected.
    public mutating func select(id: WeatherLocation.ID) {
        guard locations.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Contents of weather.json. New format: `{"favorites":[...],"selectedID":...}`.
    /// Also recognizes the old format of a single location
    /// (`{"name","latitude","longitude"}`) and turns it into a favorite -
    /// so an existing file becomes the first favorite and the selected
    /// location on first launch, without losing anything. If the file is
    /// missing, broken, or empty: no favorites.
    public static func load(from data: Data?) -> WeatherFavorites {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else { return .empty }
        return favorites(from: file)
    }

    /// `load(from:)` from the real weather.json (`ShellFiles.live`) -
    /// a shared spot instead of the same three lines at every place that
    /// creates a new weather widget with the existing favorites (click in
    /// the gallery of edit mode, dropped on a Bento page, migration of old
    /// settings on first launch).
    public static func loadLive() -> WeatherFavorites {
        load(from: ShellFiles.read(ShellFiles.live.weather))
    }

    /// The rules of `load(from:)`, also for `Codable` (0.2: locations per weather widget).
    private static func favorites(from file: File) -> WeatherFavorites {
        if let favoriteFiles = file.favorites {
            let locations = favoriteFiles.compactMap(\.location)
            let selectedID = file.selectedID.flatMap { id in locations.contains { $0.id == id } ? id : nil }
                ?? locations.first?.id
            return WeatherFavorites(locations: locations, selectedID: selectedID)
        }
        // Migration: old file with exactly one location, without "favorites".
        guard let latitude = file.latitude, let longitude = file.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return .empty }
        let name = file.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = WeatherLocation(name: name.isEmpty ? "Location" : name, latitude: latitude, longitude: longitude)
        return WeatherFavorites(locations: [location], selectedID: location.id)
    }

    private var file: File {
        File(favorites: locations.map { File.Location(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) },
             selectedID: selectedID, name: nil, latitude: nil, longitude: nil)
    }

    /// For writing to weather.json - sorted keys, indented: readable by
    /// hand, and identical favorites produce byte-identical files.
    public func fileData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(file)) ?? Data()
    }

    private struct File: Codable {
        struct Location: Codable {
            let id: UUID?
            let name: String?
            let latitude: Double
            let longitude: Double

            /// `nil` if the coordinates are not on Earth - such an entry is
            /// dropped when reading instead of discarding the whole file.
            var location: WeatherLocation? {
                guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
                let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return WeatherLocation(id: id ?? UUID(), name: trimmed.isEmpty ? "Location" : trimmed,
                                       latitude: latitude, longitude: longitude)
            }
        }

        let favorites: [Location]?
        let selectedID: WeatherLocation.ID?
        // Only for migrating from the old, single-line file.
        let name: String?
        let latitude: Double?
        let longitude: Double?
    }
}

/// Same format as weather.json - this is how weather widgets carry their
/// own locations in settings.json (0.2). Read using the rules of `load(from:)`.
extension WeatherFavorites: Codable {
    public init(from decoder: any Decoder) throws {
        self = Self.favorites(from: try File(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        try file.encode(to: encoder)
    }
}

private extension WeatherLocation {
    /// Same location, without comparing the identifier - for the
    /// duplicate check when adding.
    func sameCoordinates(as other: WeatherLocation) -> Bool {
        latitude == other.latitude && longitude == other.longitude
    }
}

// MARK: - Report

public struct CurrentWeather: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var apparentTemperature: Double?
    public var humidity: Int?
    public var code: Int
    public var windSpeed: Double?
    public var isDay: Bool

    public init(time: Date, temperature: Double, apparentTemperature: Double?, humidity: Int?,
                code: Int, windSpeed: Double?, isDay: Bool) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.code = code
        self.windSpeed = windSpeed
        self.isDay = isDay
    }
}

public struct HourForecast: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var code: Int
    public var precipitationProbability: Int?
    /// Day or night, if the provider states it per hour (MET Norway in
    /// the symbol name); otherwise `nil` and the sun times decide.
    public var isDay: Bool?

    public init(time: Date, temperature: Double, code: Int, precipitationProbability: Int?, isDay: Bool? = nil) {
        self.time = time
        self.temperature = temperature
        self.code = code
        self.precipitationProbability = precipitationProbability
        self.isDay = isDay
    }
}

public struct DayForecast: Equatable, Sendable {
    /// Start of day in the location's time zone.
    public var date: Date
    public var code: Int
    public var maxTemperature: Double
    public var minTemperature: Double
    public var sunrise: Date?
    public var sunset: Date?
    public var precipitationProbability: Int?

    public init(date: Date, code: Int, maxTemperature: Double, minTemperature: Double,
                sunrise: Date?, sunset: Date?, precipitationProbability: Int?) {
        self.date = date
        self.code = code
        self.maxTemperature = maxTemperature
        self.minTemperature = minTemperature
        self.sunrise = sunrise
        self.sunset = sunset
        self.precipitationProbability = precipitationProbability
    }
}

/// A column of the hourly strip.
public struct HourSlot: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var code: Int
    public var isDay: Bool
    public var precipitationProbability: Int?
    /// The current hour ("Now").
    public var isNow: Bool
}

public struct WeatherReport: Equatable, Sendable {
    public var current: CurrentWeather
    public var hours: [HourForecast]
    public var days: [DayForecast]
    /// Weekdays starting Monday, time zone of the location: "Today" and
    /// "2 PM" apply where the weather is.
    public let calendar: Calendar

    /// `locale`: default `.current` - follows the language choice in
    /// Nexus > General (weekdays, month names in "Today"/long date).
    /// Previously fixed to `de_CH`; the week still starts on Monday
    /// (`firstWeekday`), that is a setting, not a language question.
    public init(current: CurrentWeather, hours: [HourForecast], days: [DayForecast], timeZone: TimeZone,
                locale: Locale = .current) {
        self.current = current
        self.hours = hours
        self.days = days
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    /// Spacing of the hourly values: one hour for Open-Meteo and MET
    /// Norway, three for wttr.in. The most common spacing (median), so a
    /// single gap does not distort it; without two values, one hour.
    public var hourSpacing: TimeInterval {
        let gaps = zip(hours, hours.dropFirst()).map { $1.time.timeIntervalSince($0.time) }.filter { $0 > 0 }.sorted()
        return gaps.isEmpty ? 3600 : gaps[gaps.count / 2]
    }

    /// Hourly strip starting at the current value, roughly every `step`
    /// hours - for values every three hours (wttr.in) that means every value.
    ///
    /// The first column shows the current values, provided they come from
    /// the same slot - otherwise "Now" would say something different from
    /// the big number next to it. If the data is old (fetch failed), the
    /// strip still moves forward with the clock and uses the forecast.
    public func hourlyStrip(now: Date, count: Int = 12, step: Int = 2) -> [HourSlot] {
        let spacing = hourSpacing
        guard let first = hours.firstIndex(where: { $0.time.addingTimeInterval(spacing) > now }) else { return [] }
        let indexStep = max(1, Int((Double(max(step, 1)) * 3600 / spacing).rounded()))
        return stride(from: first, to: hours.count, by: indexStep).prefix(count).map { index in
            let hour = hours[index]
            let isNow = index == first && hour.time <= now
            if isNow, hour.time <= current.time, current.time < hour.time.addingTimeInterval(spacing) {
                return HourSlot(time: hour.time, temperature: current.temperature, code: current.code,
                                isDay: current.isDay, precipitationProbability: hour.precipitationProbability,
                                isNow: true)
            }
            return HourSlot(time: hour.time, temperature: hour.temperature, code: hour.code,
                            isDay: hour.isDay ?? isDay(at: hour.time),
                            precipitationProbability: hour.precipitationProbability, isNow: isNow)
        }
    }

    /// Day or night based on sunrise and sunset of the day. If the day is
    /// missing from the data, roughly 7 AM to 7 PM.
    public func isDay(at date: Date) -> Bool {
        if let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
           let sunrise = day.sunrise, let sunset = day.sunset {
            return sunrise <= date && date < sunset
        }
        return (7..<19).contains(calendar.component(.hour, from: date))
    }

    /// Days from today onward; past ones are dropped if the data is from
    /// yesterday.
    public func upcomingDays(now: Date, count: Int = 7) -> [DayForecast] {
        let today = calendar.startOfDay(for: now)
        return Array(days.filter { $0.date >= today }.prefix(count))
    }

    public func today(now: Date) -> DayForecast? {
        days.first { calendar.isDate($0.date, inSameDayAs: now) }
    }
}

// MARK: - Open-Meteo

public enum OpenMeteo {
    public enum DecodeError: Error, Equatable {
        /// Without a current temperature and condition there is nothing to show.
        case noCurrentWeather
    }

    /// Request like Caelestia (getWeatherUrl), plus rain probability per
    /// day. `forecast_hours=48` instead of the full 7 days: the strip needs
    /// 24 hours from now, the rest is a reserve in case a fetch fails and
    /// the data becomes a few hours old.
    public static func url(for location: WeatherLocation) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "forecast_hours", value: "48"),
        ]
        // Static parts, cannot fail.
        return components.url!
    }

    /// Open-Meteo returns local time without a zone ("2026-09-14T06:58")
    /// and the zone separately. Converted using the named zone, not
    /// `utc_offset_seconds`: the offset only applies to now, it would be
    /// wrong across a time change within the weekly forecast.
    public static func decode(_ data: Data) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: data)

        let zone = raw.timezone.flatMap(TimeZone.init(identifier:))
            ?? raw.utcOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:))
            ?? TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        guard let c = raw.current,
              let time = localDate(c.time, calendar: calendar),
              let temperature = c.temperature2m,
              let code = c.weatherCode
        else { throw DecodeError.noCurrentWeather }
        let current = CurrentWeather(
            time: time,
            temperature: temperature,
            apparentTemperature: c.apparentTemperature,
            humidity: c.relativeHumidity2m.map { Int($0.rounded()) },
            code: code,
            windSpeed: c.windSpeed10m,
            isDay: (c.isDay ?? 1) != 0
        )

        // Skip individual gaps (null) instead of discarding everything.
        var hours: [HourForecast] = []
        if let h = raw.hourly {
            for (i, text) in h.time.enumerated() {
                guard let time = localDate(text, calendar: calendar),
                      let temperature = element(h.temperature2m, i),
                      let code = element(h.weatherCode, i)
                else { continue }
                hours.append(HourForecast(time: time, temperature: temperature, code: code,
                                          precipitationProbability: element(h.precipitationProbability, i)))
            }
        }

        var days: [DayForecast] = []
        if let d = raw.daily {
            for (i, text) in d.time.enumerated() {
                guard let date = localDate(text, calendar: calendar),
                      let code = element(d.weatherCode, i),
                      let max = element(d.temperature2mMax, i),
                      let min = element(d.temperature2mMin, i)
                else { continue }
                days.append(DayForecast(
                    date: date, code: code, maxTemperature: max, minTemperature: min,
                    sunrise: element(d.sunrise, i).flatMap { localDate($0, calendar: calendar) },
                    sunset: element(d.sunset, i).flatMap { localDate($0, calendar: calendar) },
                    precipitationProbability: element(d.precipitationProbabilityMax, i)
                ))
            }
        }

        return WeatherReport(current: current, hours: hours, days: days, timeZone: zone)
    }

    /// "2026-09-14T06:58" or "2026-09-14" as local time. Done by hand
    /// instead of DateFormatter: the format is fixed, so there is no
    /// dependency on locale settings.
    static func localDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 3 || parts.count == 5 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 0, minute: 0)
        if parts.count == 5 {
            components.hour = parts[3]
            components.minute = parts[4]
        }
        return calendar.date(from: components)
    }

    private static func element<T>(_ array: [T?]?, _ index: Int) -> T? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Keys done by hand instead of `.convertFromSnakeCase`: that turns
    /// "temperature_2m" into `temperature2M` (measured 09/14), not
    /// `temperature2m` - the fields would stay silently empty.
    private struct Raw: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature2m: Double?
            let apparentTemperature: Double?
            let relativeHumidity2m: Double?
            let weatherCode: Int?
            let windSpeed10m: Double?
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double?]?
            let weatherCode: [Int?]?
            let precipitationProbability: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]?
            let temperature2mMax: [Double?]?
            let temperature2mMin: [Double?]?
            let sunrise: [String?]?
            let sunset: [String?]?
            let precipitationProbabilityMax: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time, sunrise, sunset
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
            }
        }

        let timezone: String?
        let utcOffsetSeconds: Int?
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?

        enum CodingKeys: String, CodingKey {
            case timezone, current, hourly, daily
            case utcOffsetSeconds = "utc_offset_seconds"
        }
    }
}

// MARK: - Condition

/// WMO weather code (Open-Meteo `weather_code`) as an SF Symbol and
/// English text. Groups like Caelestia (Icons.weatherIcons,
/// getWeatherCondition), texts more finely graded because "Rain" and
/// "Heavy Rain" mean something different once you step outside.
public enum WeatherCondition {
    /// For codes from other providers with no equivalent: "Unknown" with
    /// a thermometer. Negative so it is never a real WMO code.
    public static let unknownCode = -1

    /// Filled variants: only those have multicolor layers (sun yellow,
    /// rain blue). Day/night only where there is a moon counterpart.
    ///
    /// 68/69 (sleet), 79 (ice pellets), and 83/84 (sleet showers) are
    /// never delivered by Open-Meteo, but MET Norway and wttr.in do -
    /// real WMO codes instead of "freezing rain", which is something else.
    public static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67, 68, 69, 79, 83, 84: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95: "cloud.bolt.rain.fill"
        case 96, 99: "cloud.hail.fill"
        default: "thermometer.medium"
        }
    }

    public static func description(code: Int) -> String {
        switch code {
        case 0: String(localized: "Clear")
        case 1: String(localized: "Mostly Clear")
        case 2: String(localized: "Partly Cloudy")
        case 3: String(localized: "Overcast")
        case 45, 48: String(localized: "Fog")
        case 51: String(localized: "Light Drizzle")
        case 53: String(localized: "Drizzle")
        case 55: String(localized: "Heavy Drizzle")
        case 56, 57: String(localized: "Freezing Drizzle")
        case 61: String(localized: "Light Rain")
        case 63: String(localized: "Rain")
        case 65: String(localized: "Heavy Rain")
        case 66, 67: String(localized: "Freezing Rain")
        case 68: String(localized: "Light Sleet")
        case 69: String(localized: "Sleet")
        case 71: String(localized: "Light Snow")
        case 73: String(localized: "Snow")
        case 75: String(localized: "Heavy Snow")
        case 77: String(localized: "Snow Grains")
        case 79: String(localized: "Ice Pellets")
        case 80: String(localized: "Light Rain Showers")
        case 81: String(localized: "Rain Showers")
        case 82: String(localized: "Violent Rain Showers")
        case 83: String(localized: "Light Sleet Showers")
        case 84: String(localized: "Sleet Showers")
        case 85: String(localized: "Light Snow Showers")
        case 86: String(localized: "Heavy Snow Showers")
        case 95: String(localized: "Thunderstorm")
        case 96, 99: String(localized: "Thunderstorm with Hail")
        default: String(localized: "Unknown")
        }
    }
}

// MARK: - Text

/// All numbers and times as text, fixed to a specific format rather than
/// via a formatter that follows the system language: this keeps the
/// result testably consistent.
public enum WeatherText {
    /// "12°", "-3°". Rounded like Apple Weather; -0.4 becomes "0°", not "-0°".
    public static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    /// "H:22° L:14°" like Apple Weather in English.
    public static func range(max: Double, min: Double) -> String {
        String(localized: "H:\(temperature(max)) L:\(temperature(min))")
    }

    public static func wind(_ kmh: Double) -> String {
        "\(Int(kmh.rounded())) km/h"
    }

    public static func humidity(_ percent: Int) -> String {
        "\(percent) %"
    }

    /// Rain probability only from 20% up: below that it is noise, and a
    /// strip full of "3%" reads like rainy weather.
    public static func precipitation(_ percent: Int?) -> String? {
        guard let percent, percent >= 20 else { return nil }
        return "\(percent) %"
    }

    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Shows how old the displayed data is, when it is not fresh.
    public static func stand(_ date: Date, calendar: Calendar) -> String {
        String(localized: "As of \(clock(date, calendar: calendar))")
    }

    /// "Now" or "2:00".
    public static func hourLabel(_ date: Date, isNow: Bool, calendar: Calendar) -> String {
        isNow ? String(localized: "Now") : String(localized: "\(calendar.component(.hour, from: date)):00")
    }

    /// "Today", otherwise two letters like in the calendar ("Mo", "Tu").
    public static func dayLabel(_ date: Date, today: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: today) { return String(localized: "Today") }
        let symbol = calendar.shortStandaloneWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return String(symbol.replacingOccurrences(of: ".", with: "").prefix(2))
    }

    /// Day and month short, in the language's format: "15.9." (de), "9/15" (en).
    public static func shortDate(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.defaultDigits)
        )
    }

    /// "Monday, September 14".
    public static func longDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekday = calendar.standaloneWeekdaySymbols[(c.weekday ?? 1) - 1]
        let month = calendar.monthSymbols[(c.month ?? 1) - 1]
        return "\(weekday), \(month) \(c.day ?? 0)"
    }
}

// MARK: - Refresh rules

public enum WeatherRefresh {
    /// Only fetch on open if the data is older than this: someone opening
    /// the Dashboard several times a minute should not query the provider
    /// every time. Also matches MET Norway (at most every 10 minutes,
    /// measured 09/14: their response is valid for a good 10 minutes
    /// according to Expires).
    public static let maxAge: TimeInterval = 15 * 60
    /// Cadence while the Dashboard stays open.
    public static let interval: TimeInterval = 30 * 60
    /// From here on the data counts as stale, even without a reported
    /// error (e.g. closed for a long time, new fetch still running).
    public static let staleAfter: TimeInterval = 45 * 60

    /// After a failure, while the Dashboard is open: try again soon
    /// instead of only after 30 minutes. Measured 09/14: right after
    /// waking up, the fetch timed out (network/VPN not ready yet), a few
    /// minutes later the same fetch succeeded.
    public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ...1: 10
        case 2: 30
        case 3: 60
        default: 300
        }
    }

    public static func needsFetch(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= maxAge
    }

    /// Show "As of HH:MM"? Only when there is old data that is not fresh -
    /// without data there is nothing to show, and fresh data needs no timestamp.
    public static func showsStand(fetchedAt: Date?, lastAttemptFailed: Bool, now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return lastAttemptFailed || now.timeIntervalSince(fetchedAt) > staleAfter
    }
}
