import Foundation

// Wetteranbieter: woher das Dashboard sein Wetter holt. Alle ohne Schluessel
// und ohne Konto. Jeder Anbieter baut seine Anfragen selbst und liest seine
// Antworten zu einem `WeatherReport` mit WMO-Codes - so bleiben Symbole,
// Texte und Oberflaeche fuer alle gleich, egal wie der Anbieter das Wetter
// benennt (MET Norway: "lightrainshowers_day", wttr.in: 353).

// MARK: - Kennung

/// Wert in settings.json (`providers.weather`). Die Rohwerte sind das
/// Dateiformat - nicht umbenennen.
public enum WeatherProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case openMeteo
    case metNorway
    case wttr

    public var id: Self { self }

    /// Ohne Einstellung: Open-Meteo, wie vor der Auswahl.
    public static let standard = openMeteo

    /// Der Anbieter dazu. `timeZone`: fuer Anbieter, deren Antwort keine
    /// Zeitzone nennt (MET Norway, wttr.in) - siehe dort.
    public func provider(timeZone: TimeZone = .current) -> any WeatherProvider {
        switch self {
        case .openMeteo: OpenMeteoProvider()
        case .metNorway: MetNorwayProvider(timeZone: timeZone)
        case .wttr: WttrProvider(timeZone: timeZone)
        }
    }
}

// MARK: - Beschreibung

/// Quellenangabe. Open-Meteo und MET Norway stehen unter CC BY 4.0: wer ihre
/// Daten zeigt, muss die Quelle nennen und verlinken.
public struct WeatherAttribution: Equatable, Sendable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }

    /// "Wetterdaten: MET Norway" - die Zeile im Wetter-Reiter.
    public var text: String { String(localized: "Wetterdaten: \(name)") }
}

/// Was ein Anbieter liefert. Die Oberflaeche richtet sich nach den Daten
/// selbst (drei Tage sind drei Karten); das hier beschreibt die Anbieter in
/// Nexus, damit man weiss, was man mit der Wahl verliert.
public struct WeatherCapabilities: Equatable, Sendable {
    /// Abstand der Stundenwerte in Stunden.
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

    /// "7 Tage · stündlich" oder "3 Tage · alle 3 Stunden", dazu was fehlt.
    public var summary: String {
        var parts = [String(localized: "\(days) Tage"),
                     hourStep == 1 ? String(localized: "stündlich") : String(localized: "alle \(hourStep) Stunden")]
        var missing: [String] = []
        if !precipitationProbability { missing.append(String(localized: "Regenwahrscheinlichkeit")) }
        if !apparentTemperature { missing.append(String(localized: "gefühlte Temperatur")) }
        if !missing.isEmpty { parts.append(String(localized: "ohne \(missing.joined(separator: " und "))")) }
        if sunTimes == .todayOnly { parts.append(String(localized: "Sonnenzeiten nur für heute")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Anfragen

/// Kennung fuer alle Anfragen. MET Norway verlangt sie in den
/// Nutzungsbedingungen (App-Name plus Adresse, sonst 403); die anderen
/// bekommen sie aus Hoeflichkeit auch.
public enum WeatherUserAgent {
    /// Die oeffentliche Projektseite. Keine persoenliche Mail: die Kennung
    /// geht an Dritte.
    public static let projectURL = "https://github.com/Silvertree2010/ApolloShell"

    /// "ApolloShell/0.1 (+https://github.com/Silvertree2010/ApolloShell)". Ohne Version
    /// (aus `swift build` gestartet, ohne Info.plist): "dev".
    public static func value(version: String?) -> String {
        let version = version?.trimmingCharacters(in: .whitespaces) ?? ""
        return "ApolloShell/\(version.isEmpty ? "dev" : version) (+\(projectURL))"
    }
}

public struct WeatherRequest: Equatable, Sendable {
    public let url: URL
    /// Zusatz (z. B. Sonnenzeiten): scheitert er, gilt der Bericht trotzdem,
    /// nur ohne diese Angaben. Die erste Anfrage ist nie optional.
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
    /// Die Pflichtantwort fehlt.
    case missingResponse
    /// Ohne aktuelle Temperatur und Wetterlage gibt es nichts anzuzeigen.
    case noCurrentWeather
}

// MARK: - Anbieter

public protocol WeatherProvider: Sendable {
    var id: WeatherProviderID { get }
    var attribution: WeatherAttribution { get }
    var capabilities: WeatherCapabilities { get }
    /// Die erste ist Pflicht, weitere duerfen scheitern (`optional`).
    func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest]
    /// `bodies` in der Reihenfolge von `requests`; `nil` = optionale Anfrage
    /// gescheitert.
    func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport
}

extension WeatherProvider {
    /// Die Pflichtantwort, sonst Fehler.
    func primary(_ bodies: [Data?]) throws -> Data {
        guard let first = bodies.first, let data = first else { throw WeatherProviderError.missingResponse }
        return data
    }
}

/// Open-Meteo (Weather.swift): die Vorgabe. Nennt die Zeitzone des Orts
/// selbst (`timezone=auto`), braucht also keine.
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

// MARK: - Gemeinsame Helfer

enum WeatherQuery {
    /// Hoechstens vier Nachkommastellen (~10 m): MET Norway weist mehr mit
    /// 403 ab, und die Ortssuche liefert fuenf. Ohne Nullen am Ende, immer
    /// mit Punkt - `String(format:)` ohne Locale ist dafuer fest.
    static func coordinate(_ value: Double) -> String {
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// "+02:00" fuer die Zone zum Zeitpunkt `date` (Sommerzeit beachtet).
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        return String(format: "%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }

    /// "2026-09-14" im Kalender der Zone.
    static func day(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

enum WeatherTime {
    /// Zeit mit Zone: "2026-09-14T16:00:00Z" (MET Locationforecast) oder
    /// "2026-09-14T06:38+02:00" (MET Sunrise, ohne Sekunden). Von Hand wie
    /// `OpenMeteo.localDate`: ISO8601DateFormatter will Sekunden.
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
            // Ohne Zone waere die Zeit mehrdeutig.
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
