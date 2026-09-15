import Foundation

/// MET Norway (Norwegisches Meteorologisches Institut, die Daten hinter
/// yr.no): Locationforecast 2.0 "compact", dazu Sunrise 3.0 fuer Sonnenauf-
/// und -untergang von heute.
///
/// Die Antwort nennt keine Zeitzone, nur UTC-Zeiten. Tage und "14 Uhr"
/// gelten deshalb in `timeZone` - in der App die Zone des Macs: der Wetterort
/// liegt fast immer dort, wo der Mac steht. Fuer einen Ort in einer anderen
/// Zone waeren die Tagesgrenzen um den Versatz verschoben.
///
/// Was compact nicht hat: Regenwahrscheinlichkeit, gefuehlte Temperatur,
/// Tageswerte. Hoechst- und Tiefstwerte kommen aus den Einzelwerten des
/// Tages - im stuendlichen Teil (gut zwei Tage) genau, danach aus vier
/// Werten je Tag, also etwas zu flach. Heute zaehlen nur die kommenden
/// Stunden: MET liefert keine vergangenen.
public struct MetNorwayProvider: WeatherProvider {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public var id: WeatherProviderID { .metNorway }

    /// Gewuenschte Nennung laut MET: "MET Norway", mit Link auf ihre
    /// Lizenz- und Quellenseite (CC BY 4.0 und NLOD).
    public var attribution: WeatherAttribution {
        WeatherAttribution(name: "MET Norway",
                           url: URL(string: "https://www.met.no/en/free-meteorological-data/Licensing-and-crediting")!)
    }

    public var capabilities: WeatherCapabilities {
        WeatherCapabilities(hourStep: 1, days: 9, precipitationProbability: false, apparentTemperature: false,
                            sunTimes: .todayOnly)
    }

    /// Vorhersage (Pflicht) und Sonnenzeiten fuer heute (optional: ohne sie
    /// fehlen nur Auf- und Untergang). Sunrise 3.0 gilt fuer einen Tag je
    /// Anfrage; mehr als heute waeren sechs Anfragen mehr fuer Werte, die nur
    /// der heutige Tag in der Kopfkarte zeigt.
    public func requests(for location: WeatherLocation, now: Date) -> [WeatherRequest] {
        let lat = URLQueryItem(name: "lat", value: WeatherQuery.coordinate(location.latitude))
        let lon = URLQueryItem(name: "lon", value: WeatherQuery.coordinate(location.longitude))
        var forecast = URLComponents()
        forecast.scheme = "https"
        forecast.host = "api.met.no"
        forecast.path = "/weatherapi/locationforecast/2.0/compact"
        forecast.queryItems = [lat, lon]
        var sun = forecast
        sun.path = "/weatherapi/sunrise/3.0/sun"
        // "+02:00" bleibt so stehen (URLComponents kodiert "+" in der Abfrage
        // nicht); MET liest es als Versatz - gemessen 14.09., Antwort in +02:00.
        sun.queryItems = [lat, lon,
                          URLQueryItem(name: "date", value: WeatherQuery.day(now, in: timeZone)),
                          URLQueryItem(name: "offset", value: WeatherQuery.offset(timeZone, at: now))]
        // Statische Teile, kann nicht scheitern.
        return [WeatherRequest(url: forecast.url!), WeatherRequest(url: sun.url!, optional: true)]
    }

    public func decode(_ bodies: [Data?], now: Date) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: primary(bodies))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let steps: [Step] = raw.properties.timeseries.compactMap { entry in
            guard let time = WeatherTime.isoDate(entry.time) else { return nil }
            let details = entry.data.instant.details
            return Step(time: time, temperature: details.airTemperature, humidity: details.relativeHumidity,
                        windSpeed: details.windSpeed,
                        nextHour: entry.data.next1Hours?.summary?.symbolCode.map(MetNorwaySymbol.condition),
                        nextSixHours: entry.data.next6Hours?.summary?.symbolCode.map(MetNorwaySymbol.condition))
        }

        // Nur der stuendliche Teil (next_1_hours, gut zwei Tage): danach
        // kommen Sechs-Stunden-Schritte, die die Stundenleiste nicht mischen soll.
        let hours = steps.compactMap { step -> HourForecast? in
            guard let temperature = step.temperature, let condition = step.nextHour else { return nil }
            return HourForecast(time: step.time, temperature: temperature, code: condition.code,
                                precipitationProbability: nil, isDay: condition.isDay)
        }

        // Jetzt = der letzte Wert bis jetzt (die Reihe beginnt mit der
        // laufenden Stunde); liegt alles in der Zukunft, der erste.
        let usable = steps.filter { $0.temperature != nil && ($0.nextHour ?? $0.nextSixHours) != nil }
        guard let step = usable.last(where: { $0.time <= now }) ?? usable.first,
              let temperature = step.temperature,
              let condition = step.nextHour ?? step.nextSixHours
        else { throw WeatherProviderError.noCurrentWeather }

        let sun = bodies.count > 1 ? bodies[1].flatMap(Self.sunTimes) : nil
        var report = WeatherReport(
            current: CurrentWeather(
                time: step.time, temperature: temperature, apparentTemperature: nil,
                humidity: step.humidity.map { Int($0.rounded()) }, code: condition.code,
                // m/s wie bei MET ueblich; angezeigt wird km/h.
                windSpeed: step.windSpeed.map { $0 * 3.6 }, isDay: condition.isDay ?? true
            ),
            hours: hours,
            days: Self.days(steps, calendar: calendar, sun: sun),
            timeZone: timeZone
        )
        // Symbole ohne Tag/Nacht ("cloudy", "rain"): nach Sonnenzeiten.
        if condition.isDay == nil { report.current.isDay = report.isDay(at: step.time) }
        return report
    }

    /// Ein Tag je Kalendertag der Zone. Lage: das Sechs-Stunden-Symbol, dessen
    /// Mitte Mittag am naechsten liegt (09-15 Uhr im stuendlichen Teil,
    /// 08-14 Uhr danach) - wie das Tagessymbol bei yr.no das Wetter tagsueber
    /// meint, nicht die Nacht. Ohne Symbol (letzter, angebrochener Tag) faellt
    /// der Tag weg.
    private static func days(_ steps: [Step], calendar: Calendar, sun: (sunrise: Date?, sunset: Date?)?) -> [DayForecast] {
        let byDay = Dictionary(grouping: steps) { calendar.startOfDay(for: $0.time) }
        return byDay.keys.sorted().compactMap { day in
            let list = byDay[day] ?? []
            let temperatures = list.compactMap(\.temperature)
            guard let max = temperatures.max(), let min = temperatures.min(),
                  let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)
            else { return nil }
            func distance(_ step: Step, centre: TimeInterval) -> TimeInterval {
                abs(step.time.addingTimeInterval(centre).timeIntervalSince(noon))
            }
            let code = list.filter { $0.nextSixHours != nil }
                .min { distance($0, centre: 3 * 3600) < distance($1, centre: 3 * 3600) }?.nextSixHours?.code
                ?? list.filter { $0.nextHour != nil }
                .min { distance($0, centre: 1800) < distance($1, centre: 1800) }?.nextHour?.code
            guard let code else { return nil }
            let sunToday = sun.flatMap { times in
                (times.sunrise ?? times.sunset).map { calendar.isDate($0, inSameDayAs: day) } == true ? times : nil
            }
            return DayForecast(date: day, code: code, maxTemperature: max, minTemperature: min,
                               sunrise: sunToday?.sunrise, sunset: sunToday?.sunset, precipitationProbability: nil)
        }
    }

    /// Sunrise 3.0: `properties.sunrise.time` "2026-09-14T06:38+02:00". Im
    /// Polarsommer/-winter fehlt einer oder beide (`null`).
    static func sunTimes(_ data: Data) -> (sunrise: Date?, sunset: Date?)? {
        struct Raw: Decodable {
            struct Event: Decodable { let time: String? }
            struct Properties: Decodable {
                let sunrise: Event?
                let sunset: Event?
            }
            let properties: Properties?
        }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), let p = raw.properties else { return nil }
        let times = (sunrise: p.sunrise?.time.flatMap(WeatherTime.isoDate), sunset: p.sunset?.time.flatMap(WeatherTime.isoDate))
        return times.sunrise == nil && times.sunset == nil ? nil : times
    }

    private struct Step {
        let time: Date
        let temperature: Double?
        let humidity: Double?
        let windSpeed: Double?
        let nextHour: MetNorwaySymbol.Condition?
        let nextSixHours: MetNorwaySymbol.Condition?
    }

    /// Nur was gebraucht wird; Schluessel von Hand wie bei Open-Meteo.
    private struct Raw: Decodable {
        struct Properties: Decodable {
            let timeseries: [Entry]
        }

        struct Entry: Decodable {
            let time: String
            let data: EntryData
        }

        struct EntryData: Decodable {
            let instant: Instant
            let next1Hours: Period?
            let next6Hours: Period?

            enum CodingKeys: String, CodingKey {
                case instant
                case next1Hours = "next_1_hours"
                case next6Hours = "next_6_hours"
            }
        }

        struct Instant: Decodable {
            let details: Details
        }

        struct Details: Decodable {
            let airTemperature: Double?
            let relativeHumidity: Double?
            let windSpeed: Double?

            enum CodingKeys: String, CodingKey {
                case airTemperature = "air_temperature"
                case relativeHumidity = "relative_humidity"
                case windSpeed = "wind_speed"
            }
        }

        struct Period: Decodable {
            struct Summary: Decodable {
                let symbolCode: String?

                enum CodingKeys: String, CodingKey {
                    case symbolCode = "symbol_code"
                }
            }

            let summary: Summary?
        }

        let properties: Properties
    }
}

/// MET-Symbolnamen ("lightrainshowers_day") als WMO-Code plus Tag/Nacht.
/// Liste: github.com/metno/weathericons, legend.csv (41 Namen, zwei davon
/// mit Tippfehler "lights..." - so liefert MET sie auch aus).
public enum MetNorwaySymbol {
    public struct Condition: Equatable, Sendable {
        public let code: Int
        /// `nil`: Symbol ohne Tag/Nacht-Variante (Wolken, Regen).
        public let isDay: Bool?
    }

    /// Stufen wie bei WMO: leicht / maessig / stark. Schneeregen hat eigene
    /// WMO-Codes (68/69, Schauer 83/84) - nicht "gefrierend", das waere etwas
    /// anderes. Jede Kombination mit Gewitter wird 95, wie Open-Meteo sie
    /// ohne Hagel auch meldet.
    public static let codes: [String: Int] = [
        "clearsky": 0, "fair": 1, "partlycloudy": 2, "cloudy": 3, "fog": 45,
        "lightrain": 61, "rain": 63, "heavyrain": 65,
        "lightrainshowers": 80, "rainshowers": 81, "heavyrainshowers": 82,
        "lightsleet": 68, "sleet": 69, "heavysleet": 69,
        "lightsleetshowers": 83, "sleetshowers": 84, "heavysleetshowers": 84,
        "lightsnow": 71, "snow": 73, "heavysnow": 75,
        "lightsnowshowers": 85, "snowshowers": 86, "heavysnowshowers": 86,
        "lightrainandthunder": 95, "rainandthunder": 95, "heavyrainandthunder": 95,
        "lightrainshowersandthunder": 95, "rainshowersandthunder": 95, "heavyrainshowersandthunder": 95,
        "lightsleetandthunder": 95, "sleetandthunder": 95, "heavysleetandthunder": 95,
        "lightssleetshowersandthunder": 95, "sleetshowersandthunder": 95, "heavysleetshowersandthunder": 95,
        "lightsnowandthunder": 95, "snowandthunder": 95, "heavysnowandthunder": 95,
        "lightssnowshowersandthunder": 95, "snowshowersandthunder": 95, "heavysnowshowersandthunder": 95,
    ]

    /// "_day" Tag, "_night" Nacht. "_polartwilight" (Sonne knapp unter dem
    /// Horizont, Polarwinter) als Nacht: eine Sonne im Symbol hiesse, sie
    /// scheine. Unbekannte Namen: `WeatherCondition.unknownCode` - die Stunde
    /// bleibt mit ihrer Temperatur stehen, statt ganz zu fehlen.
    public static func condition(_ symbol: String) -> Condition {
        let parts = symbol.split(separator: "_", maxSplits: 1)
        let base = parts.first.map(String.init) ?? ""
        let isDay: Bool? = switch parts.count > 1 ? String(parts[1]) : "" {
        case "day": true
        case "night", "polartwilight": false
        default: nil
        }
        return Condition(code: codes[base] ?? WeatherCondition.unknownCode, isDay: isDay)
    }
}
