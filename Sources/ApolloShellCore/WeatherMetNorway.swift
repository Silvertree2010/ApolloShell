import Foundation

public struct MetNorwayProvider: WeatherProvider {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    public var id: WeatherProviderID { .metNorway }

    public var attribution: WeatherAttribution {
        WeatherAttribution(name: "MET Norway",
                           url: URL(string: "https://www.met.no/en/free-meteorological-data/Licensing-and-crediting")!)
    }

    public var capabilities: WeatherCapabilities {
        WeatherCapabilities(hourStep: 1, days: 9, precipitationProbability: false, apparentTemperature: false,
                            sunTimes: .todayOnly)
    }

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
        sun.queryItems = [lat, lon,
                          URLQueryItem(name: "date", value: WeatherQuery.day(now, in: timeZone)),
                          URLQueryItem(name: "offset", value: WeatherQuery.offset(timeZone, at: now))]
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

        let hours = steps.compactMap { step -> HourForecast? in
            guard let temperature = step.temperature, let condition = step.nextHour else { return nil }
            return HourForecast(time: step.time, temperature: temperature, code: condition.code,
                                precipitationProbability: nil, isDay: condition.isDay)
        }

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
                windSpeed: step.windSpeed.map { $0 * 3.6 }, isDay: condition.isDay ?? true
            ),
            hours: hours,
            days: Self.days(steps, calendar: calendar, sun: sun),
            timeZone: timeZone
        )
        if condition.isDay == nil { report.current.isDay = report.isDay(at: step.time) }
        return report
    }

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

public enum MetNorwaySymbol {
    public struct Condition: Equatable, Sendable {
        public let code: Int
        public let isDay: Bool?
    }

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
