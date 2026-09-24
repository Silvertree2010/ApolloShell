import Foundation

/// wttr.in im JSON-Format (`format=j1`) - die Quelle, die Caelestia frueher
/// nahm. Die Daten dahinter sind von World Weather Online: drei Tage, je acht
/// Werte alle drei Stunden, Zahlen als Text ("17").
///
/// Zeiten: Stunden ("0", "300" … "2100") und Sonnenzeiten ("06:39 AM") sind
/// Ortszeit ohne Zone, `observation_time` ist UTC ohne Datum (gemessen 14.09.:
/// Abruf 16:21 UTC, Beobachtung "04:09 PM", Stunden und Sonnenaufgang in
/// Berliner Sommerzeit). Deshalb wie bei MET Norway `timeZone` = die Zone des
/// Macs.
public struct WttrProvider: WeatherProvider {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public var id: WeatherProviderID { .wttr }

    public var attribution: WeatherAttribution {
        WeatherAttribution(name: "wttr.in", url: URL(string: "https://wttr.in/")!)
    }

    public var capabilities: WeatherCapabilities {
        WeatherCapabilities(hourStep: 3, days: 3, precipitationProbability: true, apparentTemperature: true,
                            sunTimes: .allDays)
    }

    public func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wttr.in"
        components.path = "/\(WeatherQuery.coordinate(location.latitude)),\(WeatherQuery.coordinate(location.longitude))"
        components.queryItems = [URLQueryItem(name: "format", value: "j1")]
        return [WeatherRequest(url: components.url!)]
    }

    public func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: primary(bodies))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var hours: [HourForecast] = []
        var days: [DayForecast] = []
        for day in raw.weather ?? [] {
            guard let text = day.date, let date = OpenMeteo.localDate(text, calendar: calendar) else { continue }
            var dayHours: [HourForecast] = []
            for hour in day.hourly ?? [] {
                guard let clock = hour.time?.value.map(Int.init),
                      let time = calendar.date(bySettingHour: clock / 100, minute: clock % 100, second: 0, of: date),
                      let temperature = hour.tempC?.value,
                      let code = hour.weatherCode?.value
                else { continue }
                dayHours.append(HourForecast(time: time, temperature: temperature, code: WttrCode.wmo(Int(code)),
                                             precipitationProbability: Self.chance(hour)))
            }
            hours += dayHours
            // Tageslage: der Wert um 12 Uhr, wie wttr.in selbst "Mittag" zeigt.
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            guard let max = day.maxtempC?.value, let min = day.mintempC?.value,
                  let middle = dayHours.min(by: { abs($0.time.timeIntervalSince(noon)) < abs($1.time.timeIntervalSince(noon)) })
            else { continue }
            let astronomy = day.astronomy?.first
            days.append(DayForecast(
                date: date, code: middle.code, maxTemperature: max, minTemperature: min,
                sunrise: astronomy?.sunrise.flatMap { Self.time($0, on: date, calendar: calendar) },
                sunset: astronomy?.sunset.flatMap { Self.time($0, on: date, calendar: calendar) },
                precipitationProbability: dayHours.compactMap(\.precipitationProbability).max()
            ))
        }

        guard let c = raw.currentCondition?.first,
              let temperature = c.tempC?.value,
              let code = c.weatherCode?.value
        else { throw WeatherProviderError.noCurrentWeather }
        var report = WeatherReport(
            current: CurrentWeather(
                time: c.observationTime.flatMap { Self.observation($0, now: now) } ?? now,
                temperature: temperature, apparentTemperature: c.feelsLikeC?.value,
                humidity: c.humidity?.value.map { Int($0.rounded()) }, code: WttrCode.wmo(Int(code)),
                windSpeed: c.windspeedKmph?.value, isDay: true
            ),
            hours: hours, days: days, timeZone: timeZone
        )
        // WWO-Codes kennen kein Tag/Nacht: nach den Sonnenzeiten des Tages.
        report.current.isDay = report.isDay(at: report.current.time)
        return report
    }

    /// Regen- oder Schneewahrscheinlichkeit, die hoehere - "Niederschlag"
    /// wie bei Open-Meteo.
    private static func chance(_ hour: Raw.Hour) -> Int? {
        let values = [hour.chanceofrain?.value, hour.chanceofsnow?.value].compactMap { $0 }
        return values.max().map { Int($0.rounded()) }
    }

    /// "06:39 AM" am Tag `date` (Ortszeit). "No sunrise" im Polarsommer: nil.
    static func time(_ text: String, on date: Date, calendar: Calendar) -> Date? {
        guard let (hour, minute) = clock12(text) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    /// `observation_time` ist UTC ohne Datum: der juengste solche Zeitpunkt
    /// bis kurz nach `now` (eine Stunde Spielraum fuer schiefe Uhren).
    static func observation(_ text: String, now: Date) -> Date? {
        guard let (hour, minute) = clock12(text) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let sameDay = utc.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        return sameDay > now.addingTimeInterval(3600) ? sameDay.addingTimeInterval(-86400) : sameDay
    }

    /// "12:05 AM" -> 0:05, "12:30 PM" -> 12:30, "07:24 PM" -> 19:24.
    static func clock12(_ text: String) -> (Int, Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).uppercased().split(separator: " ")
        guard parts.count == 2, parts[1] == "AM" || parts[1] == "PM" else { return nil }
        let clock = parts[0].split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2, (1...12).contains(clock[0]), (0..<60).contains(clock[1]) else { return nil }
        return (clock[0] % 12 + (parts[1] == "PM" ? 12 : 0), clock[1])
    }

    /// wttr.in liefert Zahlen als Text; nimmt zur Sicherheit auch echte
    /// Zahlen. Unlesbar: nil statt Fehler fuer die ganze Antwort.
    struct Number: Decodable {
        let value: Double?

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let number = try? c.decode(Double.self) {
                value = number
            } else if let text = try? c.decode(String.self) {
                value = Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                value = nil
            }
        }
    }

    private struct Raw: Decodable {
        struct Current: Decodable {
            let observationTime: String?
            let tempC: Number?
            let feelsLikeC: Number?
            let humidity: Number?
            let weatherCode: Number?
            let windspeedKmph: Number?

            enum CodingKeys: String, CodingKey {
                case humidity, weatherCode, windspeedKmph
                case observationTime = "observation_time"
                case tempC = "temp_C"
                case feelsLikeC = "FeelsLikeC"
            }
        }

        struct Day: Decodable {
            let date: String?
            let maxtempC: Number?
            let mintempC: Number?
            let astronomy: [Astronomy]?
            let hourly: [Hour]?
        }

        struct Astronomy: Decodable {
            let sunrise: String?
            let sunset: String?
        }

        struct Hour: Decodable {
            let time: Number?
            let tempC: Number?
            let weatherCode: Number?
            let chanceofrain: Number?
            let chanceofsnow: Number?
        }

        let currentCondition: [Current]?
        let weather: [Day]?

        enum CodingKeys: String, CodingKey {
            case weather
            case currentCondition = "current_condition"
        }
    }
}

/// Wettercodes von World Weather Online (wttr.in `weatherCode`) als WMO-Code.
/// Liste: die 48 Codes von WWO (113 "Sunny" bis 395 "Moderate or heavy snow
/// with thunder"). "Patchy … possible/nearby" ist bei WWO ein Schauer-Wetter,
/// deshalb Schauer (80, 85, 83).
public enum WttrCode {
    public static let table: [Int: Int] = [
        113: 0, 116: 2, 119: 3, 122: 3, 143: 45, 248: 45, 260: 48,
        176: 80, 179: 85, 182: 83, 185: 56, 200: 95,
        227: 73, 230: 75,
        263: 51, 266: 51, 281: 56, 284: 57,
        293: 61, 296: 61, 299: 63, 302: 63, 305: 65, 308: 65, 311: 66, 314: 67,
        317: 68, 320: 69,
        323: 71, 326: 71, 329: 73, 332: 73, 335: 75, 338: 75, 350: 79,
        353: 80, 356: 81, 359: 82, 362: 83, 365: 84, 368: 85, 371: 86, 374: 79, 377: 79,
        386: 95, 389: 95, 392: 95, 395: 95,
    ]

    /// Unbekannt: `WeatherCondition.unknownCode` ("Unknown", Thermometer).
    public static func wmo(_ code: Int) -> Int {
        table[code] ?? WeatherCondition.unknownCode
    }
}
