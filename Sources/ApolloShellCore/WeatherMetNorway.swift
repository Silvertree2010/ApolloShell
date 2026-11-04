import Foundation

/// MET Norway (the Norwegian Meteorological Institute, the data behind
/// yr.no): Locationforecast 2.0 "compact", plus Sunrise 3.0 for today's
/// sunrise and sunset.
///
/// The answer names no time zone, only UTC times. Days and "14:00" therefore
/// hold in `timeZone` - in the app the zone of the Mac: the weather place
/// almost always lies where the Mac stands. For a place in another zone the
/// day boundaries would be shifted by the offset.
///
/// What compact does not have: the chance of rain, the feels-like temperature,
/// daily values. The highs and lows come out of the single values of the day -
/// exact in the hourly part (a good two days), after that out of four values a
/// day, so a little too flat. Today only the coming hours count: MET delivers
/// no past ones.
public struct MetNorwayProvider: WeatherProvider {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public var id: WeatherProviderID { .metNorway }

    /// The attribution MET asks for: "MET Norway", with a link to their
    /// licence and source page (CC BY 4.0 and NLOD).
    public var attribution: WeatherAttribution {
        WeatherAttribution(name: "MET Norway",
                           url: URL(string: "https://www.met.no/en/free-meteorological-data/Licensing-and-crediting")!)
    }

    public var capabilities: WeatherCapabilities {
        WeatherCapabilities(hourStep: 1, days: 9, precipitationProbability: false, apparentTemperature: false,
                            sunTimes: .todayOnly)
    }

    /// The forecast (required) and the sun times for today (optional: without
    /// them only the sunrise and sunset are missing). Sunrise 3.0 holds for one
    /// day per request; more than today would be six more requests for values
    /// only today shows in the header card.
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
        // "+02:00" stays as it is (URLComponents does not encode "+" in the
        // query); MET reads it as an offset - measured 14.09., the answer in +02:00.
        sun.queryItems = [lat, lon,
                          URLQueryItem(name: "date", value: WeatherQuery.day(now, in: timeZone)),
                          URLQueryItem(name: "offset", value: WeatherQuery.offset(timeZone, at: now))]
        // Static parts, cannot fail.
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

        // Only the hourly part (next_1_hours, a good two days): after that come
        // six-hour steps, which the hour row should not mix in.
        let hours = steps.compactMap { step -> HourForecast? in
            guard let temperature = step.temperature, let condition = step.nextHour else { return nil }
            return HourForecast(time: step.time, temperature: temperature, code: condition.code,
                                precipitationProbability: nil, isDay: condition.isDay)
        }

        // Now = the last value up to now (the row begins with the current
        // hour); when everything lies in the future, the first one.
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
        // m/s as usual with MET; what is shown is km/h.
                windSpeed: step.windSpeed.map { $0 * 3.6 }, isDay: condition.isDay ?? true
            ),
            hours: hours,
            days: Self.days(steps, calendar: calendar, sun: sun),
            timeZone: timeZone
        )
        // Symbols without day/night ("cloudy", "rain"): by the sun times.
        if condition.isDay == nil { report.current.isDay = report.isDay(at: step.time) }
        return report
    }

    /// One day per calendar day of the zone. The condition: the six-hour
    /// symbol whose middle lies closest to noon (09-15 in the hourly part,
    /// 08-14 after that) - the way the day symbol at yr.no means the weather
    /// during the day, not the night. Without a symbol (the last, partial day)
    /// the day falls away.
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

    /// Sunrise 3.0: `properties.sunrise.time` "2026-09-14T06:38+02:00". In the
    /// polar summer or winter one or both are missing (`null`).
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

    /// Only what is needed; the keys by hand as with Open-Meteo.
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

/// MET symbol names ("lightrainshowers_day") as a WMO code plus day/night. The
/// list: github.com/metno/weathericons, legend.csv (41 names, two of them with
/// the typo "lights..." - MET delivers them that way too).
public enum MetNorwaySymbol {
    public struct Condition: Equatable, Sendable {
        public let code: Int
        /// `nil`: a symbol without a day/night variant (clouds, rain).
        public let isDay: Bool?
    }

    /// The steps as with WMO: light / moderate / heavy. Sleet has WMO codes of
    /// its own (68/69, showers 83/84) - not "freezing", which would be
    /// something else. Every combination with a thunderstorm becomes 95, the
    /// way Open-Meteo reports it without hail too.
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

    /// "_day" day, "_night" night. "_polartwilight" (the sun just below the
    /// horizon, polar winter) as night: a sun in the symbol would mean it is
    /// shining. Unknown names: `WeatherCondition.unknownCode` - the hour stays
    /// standing with its temperature instead of being missing entirely.
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
