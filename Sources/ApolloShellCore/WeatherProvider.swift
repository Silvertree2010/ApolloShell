import Foundation

// The weather providers: where the dashboard gets its weather. All without a
// key and without an account. Every provider builds its requests itself and
// reads its answers into a `WeatherReport` with WMO codes - that way symbols,
// texts and the user interface stay the same for all of them, no matter what
// the provider calls the weather (MET Norway: "lightrainshowers_day", wttr.in: 353).

// MARK: - Identifier

/// The value in settings.json (`providers.weather`). The raw values are the
/// file format - do not rename them.
public enum WeatherProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case openMeteo
    case metNorway
    case wttr

    public var id: Self { self }

    /// Without a setting: Open-Meteo, as before the choice existed.
    public static let standard = openMeteo

    /// The provider for it. `timeZone`: for providers whose answer names no
    /// time zone (MET Norway, wttr.in) - see there.
    public func provider(timeZone: TimeZone = .current) -> any WeatherProvider {
        switch self {
        case .openMeteo: OpenMeteoProvider()
        case .metNorway: MetNorwayProvider(timeZone: timeZone)
        case .wttr: WttrProvider(timeZone: timeZone)
        }
    }
}

// MARK: - Description

/// The attribution. Open-Meteo and MET Norway are under CC BY 4.0: whoever
/// shows their data has to name the source and link to it.
public struct WeatherAttribution: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    /// "Weather data: MET Norway" - the line in the weather tab.
    public var text: String { String(localized: "Weather data: \(name)") }
}

/// What a provider delivers. The user interface follows the data itself
/// (three days are three cards); this describes the providers in Nexus, so
/// that one knows what one loses with the choice.
public struct WeatherCapabilities: Equatable, Sendable {
    /// The gap between the hourly values in hours.
    public let hourStep: Int
    public let days: Int
    public let precipitationProbability: Bool
    public let apparentTemperature: Bool
    public let sunTimes: SunTimes

    public enum SunTimes: Equatable, Sendable {
        case allDays
        case todayOnly
    }

    public init(hourStep: Int, days: Int, precipitationProbability: Bool, apparentTemperature: Bool, sunTimes: SunTimes) {
        self.hourStep = hourStep
        self.days = days
        self.precipitationProbability = precipitationProbability
        self.apparentTemperature = apparentTemperature
        self.sunTimes = sunTimes
    }

    /// "7 days · hourly" or "3 days · every 3 hours", plus what is missing.
    public var summary: String {
        var parts = [String(localized: "\(days) days"),
                     hourStep == 1 ? String(localized: "hourly") : String(localized: "every \(hourStep) hours")]
        var missing: [String] = []
        if !precipitationProbability { missing.append(String(localized: "chance of rain")) }
        if !apparentTemperature { missing.append(String(localized: "feels-like temperature")) }
        if !missing.isEmpty { parts.append(String(localized: "without \(missing.joined(separator: " and "))")) }
        if sunTimes == .todayOnly { parts.append(String(localized: "sun times for today only")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Requests

/// The identifier for all requests. MET Norway asks for it in their terms (an
/// app name plus an address, otherwise 403); the others get it out of
/// politeness too.
public enum WeatherUserAgent {
    /// The public project page. No personal mail: the identifier goes to third
    /// parties.
    public static let projectURL = "https://github.com/Silvertree2010/ApolloShell"

    /// "ApolloShell/0.1 (+https://github.com/Silvertree2010/ApolloShell)".
    /// Without a version (started from `swift build`, without an Info.plist): "dev".
    public static func value(version: String?) -> String {
        let version = version?.trimmingCharacters(in: .whitespaces) ?? ""
        return "ApolloShell/\(version.isEmpty ? "dev" : version) (+\(projectURL))"
    }
}

public struct WeatherRequest: Equatable, Sendable {
    public let url: URL
    /// An extra (the sun times, say): when it fails, the report still holds,
    /// only without those entries. The first request is never optional.
    public let optional: Bool

    public init(url: URL, optional: Bool = false) {
        self.url = url
        self.optional = optional
    }

    public func urlRequest(userAgent: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

public enum WeatherProviderError: Error, Equatable {
    /// The required answer is missing.
    case missingResponse
    /// Without a current temperature and condition there is nothing to show.
    case noCurrentWeather
}

// MARK: - Providers

public protocol WeatherProvider: Sendable {
    var id: WeatherProviderID { get }
    var attribution: WeatherAttribution { get }
    var capabilities: WeatherCapabilities { get }
    /// The first one is required, further ones may fail (`optional`).
    func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest]
    /// `bodies` in the order of `requests`; `nil` = the optional request
    /// failed.
    func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport
}

extension WeatherProvider {
    /// The required answer, otherwise an error.
    func primary(_ bodies: [Data?]) throws -> Data {
        guard let first = bodies.first, let data = first else { throw WeatherProviderError.missingResponse }
        return data
    }
}

/// Open-Meteo (Weather.swift): the default. Names the time zone of the place
/// itself (`timezone=auto`), so it needs none.
public struct OpenMeteoProvider: WeatherProvider {
    public init() {}

    public var id: WeatherProviderID { .openMeteo }

    public var attribution: WeatherAttribution {
        WeatherAttribution(name: "Open-Meteo", url: URL(string: "https://open-meteo.com/")!)
    }

    public var capabilities: WeatherCapabilities {
        WeatherCapabilities(hourStep: 1, days: 7, precipitationProbability: true, apparentTemperature: true,
                            sunTimes: .allDays)
    }

    public func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest] {
        [WeatherRequest(url: OpenMeteo.url(for: location))]
    }

    public func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport {
        try OpenMeteo.decode(primary(bodies))
    }
}

// MARK: - Shared helpers

enum WeatherQuery {
    /// At most four decimals (~10 m): MET Norway turns more down with a 403,
    /// and the place search delivers five. Without zeros at the end, always
    /// with a point - `String(format:)` without a locale is fixed that way.
    static func coordinate(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// "+02:00" for the zone at the time `date` (daylight saving taken into account).
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }

    /// "2026-09-14" in the calendar of the zone.
    static func day(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum WeatherTime {
    /// A time with a zone: "2026-09-14T16:00:00Z" (MET Locationforecast) or
    /// "2026-09-14T06:38+02:00" (MET Sunrise, without seconds). By hand like
    /// `OpenMeteo.localDate`: ISO8601DateFormatter wants seconds.
    static func isoDate(_ text: String) -> Date? {
        guard let t = text.firstIndex(of: "T") else { return nil }
        var body = Substring(text)
        var offset = 0
        if body.hasSuffix("Z") {
            body.removeLast()
        } else if let sign = body[t...].lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let zone = body[body.index(after: sign)...].split(separator: ":").compactMap { Int($0) }
            guard zone.count == 2 else { return nil }
            offset = (zone[0] * 3600 + zone[1] * 60) * (body[sign] == "-" ? -1 : 1)
            body = body[..<sign]
        } else {
            // Without a zone the time would be ambiguous.
            return nil
        }
        let parts = body.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 5 || parts.count == 6, let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3],
                                                  minute: parts[4], second: parts.count == 6 ? parts[5] : 0))
    }
}
