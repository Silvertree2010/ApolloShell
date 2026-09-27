import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WeatherProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case openMeteo
    case metNorway
    case wttr

    public var id: Self { self }

    public static let standard = openMeteo

    public func provider(timeZone: TimeZone = .current) -> any WeatherProvider {
        switch self {
        case .openMeteo: OpenMeteoProvider()
        case .metNorway: MetNorwayProvider(timeZone: timeZone)
        case .wttr: WttrProvider(timeZone: timeZone)
        }
    }
}

public struct WeatherAttribution: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public var text: String { String(localized: "Weather data: \(name)") }
}

public struct WeatherCapabilities: Equatable, Sendable {
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

    public var summary: String {
        var parts = [String(localized: "\(days) days"),
                     hourStep == 1 ? String(localized: "hourly") : String(localized: "every \(hourStep) hours")]
        var missing: [String] = []
        if !precipitationProbability { missing.append(String(localized: "chance of rain")) }
        if !apparentTemperature { missing.append(String(localized: "feels-like temperature")) }
        if !missing.isEmpty { parts.append(String(localized: "without \(missing.joined(separator: " und "))")) }
        if sunTimes == .todayOnly { parts.append(String(localized: "sun times for today only")) }
        return parts.joined(separator: " · ")
    }
}

public enum WeatherUserAgent {
    public static let projectURL = "https://github.com/Silvertree2010/ApolloShell"

    public static func value(version: String?) -> String {
        let version = version?.trimmingCharacters(in: .whitespaces) ?? ""
        return "ApolloShell/\(version.isEmpty ? "dev" : version) (+\(projectURL))"
    }
}

public struct WeatherRequest: Equatable, Sendable {
    public let url: URL
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
    case missingResponse
    case noCurrentWeather
}

public protocol WeatherProvider: Sendable {
    var id: WeatherProviderID { get }
    var attribution: WeatherAttribution { get }
    var capabilities: WeatherCapabilities { get }
    func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest]
    func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport
}

extension WeatherProvider {
    func primary(_ bodies: [Data?]) throws -> Data {
        guard let first = bodies.first, let data = first else { throw WeatherProviderError.missingResponse }
        return data
    }
}

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

enum WeatherQuery {
    static func coordinate(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }

    static func day(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum WeatherTime {
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
