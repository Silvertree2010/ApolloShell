import Foundation
import Testing
@testable import ApolloShellCore

// Real answers for Berlin (52.52, 13.405), fetched once each on 14.09.2026 at
// 16:21 UTC, shortened to the fields that are used (MET: 16 of the 90 points
// in time, across the switch from hourly to six-hourly).

private let openMeteoBerlin = """
{"latitude":52.52,"longitude":13.4,"generationtime_ms":0.4347562789916992,"utc_offset_seconds":7200,"timezone":"Europe/Berlin","timezone_abbreviation":"GMT+2","elevation":37.0,"current":{"time":"2026-09-14T18:15","interval":900,"temperature_2m":17.6,"apparent_temperature":15.6,"relative_humidity_2m":47,"weather_code":2,"wind_speed_10m":6.4,"is_day":1},"hourly":{"time":["2026-09-14T18:00","2026-09-14T19:00","2026-09-14T20:00","2026-09-14T21:00","2026-09-14T22:00","2026-09-14T23:00"],"temperature_2m":[17.7,17.2,16.8,16.0,15.1,14.3],"weather_code":[1,2,2,2,2,1],"precipitation_probability":[0,0,0,0,0,0]},"daily":{"time":["2026-09-14","2026-09-15","2026-09-16","2026-09-17","2026-09-18","2026-09-19","2026-09-20"],"weather_code":[3,3,95,3,61,61,80],"temperature_2m_max":[17.8,24.4,19.8,19.8,18.2,21.5,17.6],"temperature_2m_min":[14.3,12.0,15.8,12.8,13.8,11.0,13.2],"sunrise":["2026-09-14T06:38","2026-09-15T06:40","2026-09-16T06:42","2026-09-17T06:43","2026-09-18T06:45","2026-09-19T06:47","2026-09-20T06:48"],"sunset":["2026-09-14T19:24","2026-09-15T19:21","2026-09-16T19:19","2026-09-17T19:16","2026-09-18T19:14","2026-09-19T19:12","2026-09-20T19:09"],"precipitation_probability_max":[5,0,90,3,30,4,35]}}
"""

private let metBerlin = """
{"type":"Feature","properties":{"meta":{"updated_at":"2026-09-14T13:36:31Z"},"timeseries":[{"time":"2026-09-14T16:00:00Z","data":{"instant":{"details":{"air_temperature":17.8,"relative_humidity":51.6,"wind_speed":2.3}},"next_1_hours":{"summary":{"symbol_code":"clearsky_day"}},"next_6_hours":{"summary":{"symbol_code":"fair_night"}}}},{"time":"2026-09-14T17:00:00Z","data":{"instant":{"details":{"air_temperature":16.8,"relative_humidity":56.1,"wind_speed":1.5}},"next_1_hours":{"summary":{"symbol_code":"clearsky_night"}},"next_6_hours":{"summary":{"symbol_code":"fair_night"}}}},{"time":"2026-09-14T18:00:00Z","data":{"instant":{"details":{"air_temperature":15.6,"relative_humidity":63.7,"wind_speed":1.3}},"next_1_hours":{"summary":{"symbol_code":"clearsky_night"}},"next_6_hours":{"summary":{"symbol_code":"partlycloudy_night"}}}},{"time":"2026-09-14T19:00:00Z","data":{"instant":{"details":{"air_temperature":15.1,"relative_humidity":67.2,"wind_speed":1.2}},"next_1_hours":{"summary":{"symbol_code":"fair_night"}},"next_6_hours":{"summary":{"symbol_code":"partlycloudy_night"}}}},{"time":"2026-09-15T07:00:00Z","data":{"instant":{"details":{"air_temperature":14.4,"relative_humidity":74.3,"wind_speed":1.8}},"next_1_hours":{"summary":{"symbol_code":"clearsky_day"}},"next_6_hours":{"summary":{"symbol_code":"fair_day"}}}},{"time":"2026-09-15T08:00:00Z","data":{"instant":{"details":{"air_temperature":16.7,"relative_humidity":67.9,"wind_speed":1.8}},"next_1_hours":{"summary":{"symbol_code":"clearsky_day"}},"next_6_hours":{"summary":{"symbol_code":"fair_day"}}}},{"time":"2026-09-15T13:00:00Z","data":{"instant":{"details":{"air_temperature":23.5,"relative_humidity":52.8,"wind_speed":2.6}},"next_1_hours":{"summary":{"symbol_code":"cloudy"}},"next_6_hours":{"summary":{"symbol_code":"fair_day"}}}},{"time":"2026-09-17T05:00:00Z","data":{"instant":{"details":{"air_temperature":11.9,"relative_humidity":94.7,"wind_speed":2.3}},"next_1_hours":{"summary":{"symbol_code":"clearsky_day"}}}},{"time":"2026-09-17T06:00:00Z","data":{"instant":{"details":{"air_temperature":12.5,"relative_humidity":93.1,"wind_speed":2.7}},"next_6_hours":{"summary":{"symbol_code":"cloudy"}}}},{"time":"2026-09-17T12:00:00Z","data":{"instant":{"details":{"air_temperature":18.3,"relative_humidity":54.3,"wind_speed":3.7}},"next_6_hours":{"summary":{"symbol_code":"fair_day"}}}},{"time":"2026-09-17T18:00:00Z","data":{"instant":{"details":{"air_temperature":15.9,"relative_humidity":67.2,"wind_speed":2.3}},"next_6_hours":{"summary":{"symbol_code":"fair_night"}}}},{"time":"2026-09-18T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.9,"relative_humidity":73.9,"wind_speed":2.7}},"next_6_hours":{"summary":{"symbol_code":"cloudy"}}}},{"time":"2026-09-18T06:00:00Z","data":{"instant":{"details":{"air_temperature":13.1,"relative_humidity":69.9,"wind_speed":3.5}},"next_6_hours":{"summary":{"symbol_code":"partlycloudy_day"}}}},{"time":"2026-09-18T12:00:00Z","data":{"instant":{"details":{"air_temperature":19.3,"relative_humidity":52.9,"wind_speed":3.9}},"next_6_hours":{"summary":{"symbol_code":"fair_day"}}}},{"time":"2026-09-18T18:00:00Z","data":{"instant":{"details":{"air_temperature":16.8,"relative_humidity":59.3,"wind_speed":2.6}},"next_6_hours":{"summary":{"symbol_code":"fair_night"}}}},{"time":"2026-09-24T00:00:00Z","data":{"instant":{"details":{"air_temperature":11.5,"relative_humidity":77.9,"wind_speed":1.5}}}}]}}
"""

/// Sunrise 3.0, not shortened.
private let sunBerlin = """
{"copyright":"MET Norway","licenseURL":"https://api.met.no/license_data.html","type":"Feature","geometry":{"type":"Point","coordinates":[13.405,52.52]},"when":{"interval":["2026-09-13T23:01:00Z","2026-09-14T23:06:00Z"]},"properties":{"body":"Sun","sunrise":{"time":"2026-09-14T06:38+02:00","azimuth":83.3},"sunset":{"time":"2026-09-14T19:24+02:00","azimuth":276.36},"solarnoon":{"time":"2026-09-14T13:01+02:00","disc_centre_elevation":40.79,"visible":true},"solarmidnight":{"time":"2026-09-14T01:02+02:00","disc_centre_elevation":-33.98,"visible":false}}}
"""

private let wttrBerlin = """
{"current_condition":[{"observation_time":"04:09 PM","temp_C":"20","FeelsLikeC":"17","humidity":"38","weatherCode":"119","windspeedKmph":"10"}],"weather":[{"date":"2026-09-14","maxtempC":"21","mintempC":"14","astronomy":[{"sunrise":"06:39 AM","sunset":"07:24 PM"}],"hourly":[{"time":"0","tempC":"17","weatherCode":"176","chanceofrain":"29","chanceofsnow":"0"},{"time":"300","tempC":"16","weatherCode":"119","chanceofrain":"26","chanceofsnow":"0"},{"time":"600","tempC":"15","weatherCode":"122","chanceofrain":"23","chanceofsnow":"0"},{"time":"900","tempC":"14","weatherCode":"116","chanceofrain":"9","chanceofsnow":"0"},{"time":"1200","tempC":"18","weatherCode":"122","chanceofrain":"12","chanceofsnow":"0"},{"time":"1500","tempC":"21","weatherCode":"119","chanceofrain":"5","chanceofsnow":"0"},{"time":"1800","tempC":"20","weatherCode":"119","chanceofrain":"5","chanceofsnow":"0"},{"time":"2100","tempC":"17","weatherCode":"119","chanceofrain":"8","chanceofsnow":"0"}]},{"date":"2026-09-15","maxtempC":"25","mintempC":"14","astronomy":[{"sunrise":"06:40 AM","sunset":"07:22 PM"}],"hourly":[{"time":"0","tempC":"16","weatherCode":"122","chanceofrain":"13","chanceofsnow":"0"},{"time":"300","tempC":"15","weatherCode":"122","chanceofrain":"12","chanceofsnow":"0"},{"time":"600","tempC":"14","weatherCode":"113","chanceofrain":"4","chanceofsnow":"0"},{"time":"900","tempC":"16","weatherCode":"113","chanceofrain":"3","chanceofsnow":"0"},{"time":"1200","tempC":"22","weatherCode":"113","chanceofrain":"2","chanceofsnow":"0"},{"time":"1500","tempC":"25","weatherCode":"116","chanceofrain":"3","chanceofsnow":"0"},{"time":"1800","tempC":"23","weatherCode":"122","chanceofrain":"12","chanceofsnow":"0"},{"time":"2100","tempC":"22","weatherCode":"122","chanceofrain":"13","chanceofsnow":"0"}]},{"date":"2026-09-16","maxtempC":"21","mintempC":"16","astronomy":[{"sunrise":"06:42 AM","sunset":"07:20 PM"}],"hourly":[{"time":"0","tempC":"21","weatherCode":"122","chanceofrain":"14","chanceofsnow":"0"},{"time":"300","tempC":"20","weatherCode":"122","chanceofrain":"15","chanceofsnow":"0"},{"time":"600","tempC":"19","weatherCode":"122","chanceofrain":"17","chanceofsnow":"0"},{"time":"900","tempC":"19","weatherCode":"353","chanceofrain":"61","chanceofsnow":"0"},{"time":"1200","tempC":"18","weatherCode":"353","chanceofrain":"52","chanceofsnow":"0"},{"time":"1500","tempC":"17","weatherCode":"122","chanceofrain":"17","chanceofsnow":"0"},{"time":"1800","tempC":"21","weatherCode":"122","chanceofrain":"11","chanceofsnow":"0"},{"time":"2100","tempC":"17","weatherCode":"122","chanceofrain":"11","chanceofsnow":"0"}]}]}
"""

private let berlin = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
private let berlinZone = TimeZone(identifier: "Europe/Berlin")!

private func utc(_ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0, month: Int = 9) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlinZone
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

/// The time of the fetch.
private let fetched = utc(14, 16, 21, second: 22)

private func data(_ text: String) -> Data { Data(text.utf8) }

private func metReport(sun: Bool = true) throws -> WeatherReport {
    try MetNorwayProvider(timeZone: berlinZone).decode([data(metBerlin), sun ? data(sunBerlin) : nil], now: fetched)
}

private func wttrReport() throws -> WeatherReport {
    try WttrProvider(timeZone: berlinZone).decode([data(wttrBerlin)], now: fetched)
}

// MARK: - Shared

@Suite("Weather providers: choice, attribution, identifier")
struct WeatherProviderCommonTests {
    @Test("The identifier in settings.json and the matching provider", arguments: [
        ("openMeteo", "Open-Meteo", "open-meteo.com"),
        ("metNorway", "MET Norway", "www.met.no"),
        ("wttr", "wttr.in", "wttr.in"),
    ])
    func providers(raw: String, name: String, host: String) throws {
        let id = try #require(WeatherProviderID(rawValue: raw))
        let provider = id.provider(timeZone: berlinZone)
        #expect(provider.id == id)
        #expect(provider.attribution.name == name)
        #expect(provider.attribution.text == "Weather data: \(name)")
        #expect(provider.attribution.url.host == host)
        #expect(provider.attribution.url.scheme == "https")
    }

    @Test("The default is Open-Meteo")
    func standard() {
        #expect(WeatherProviderID.standard == .openMeteo)
        #expect(WeatherProviderID.allCases.count == 3)
    }

    @Test("Capabilities for Nexus", arguments: [
        ("openMeteo", "7 days · hourly"),
        ("metNorway", "9 days · hourly · without chance of rain and feels-like temperature · sun times for today only"),
        ("wttr", "3 days · every 3 hours"),
    ])
    func summary(raw: String, text: String) throws {
        let id = try #require(WeatherProviderID(rawValue: raw))
        #expect(id.provider().capabilities.summary == text)
    }

    @Test("User agent: app, version, project address - no mail", arguments: [
        (Optional("0.1"), "ApolloShell/0.1 (+https://github.com/Silvertree2010/ApolloShell)"),
        (nil, "ApolloShell/dev (+https://github.com/Silvertree2010/ApolloShell)"),
        (Optional("  "), "ApolloShell/dev (+https://github.com/Silvertree2010/ApolloShell)"),
    ])
    func userAgent(version: String?, value: String) {
        #expect(WeatherUserAgent.value(version: version) == value)
        #expect(!value.contains("@"))
    }

    @Test("Every request carries the identifier", arguments: ["openMeteo", "metNorway", "wttr"])
    func requestHeader(raw: String) throws {
        let provider = try #require(WeatherProviderID(rawValue: raw)).provider(timeZone: berlinZone)
        for request in provider.requests(for: berlin, now: fetched) {
            #expect(request.urlRequest(userAgent: "ApolloShell/0.1 (+x)").value(forHTTPHeaderField: "User-Agent")
                == "ApolloShell/0.1 (+x)")
        }
        #expect(provider.requests(for: berlin, now: fetched).first?.optional == false)
    }

    @Test("Coordinates: at most four places, without zeros at the end", arguments: [
        (52.52, "52.52"), (13.405, "13.405"), (48.856614, "48.8566"), (-73.98513, "-73.9851"),
        (10.0, "10"), (0.00001, "0"), (-0.00001, "0"), (2.35225, "2.3523"),
    ])
    func coordinate(value: Double, text: String) {
        #expect(WeatherQuery.coordinate(value) == text)
    }

    @Test("The time zone offset with daylight saving", arguments: [
        ("Europe/Berlin", 9, "+02:00"), ("Europe/Berlin", 1, "+01:00"), ("America/St_Johns", 9, "-02:30"),
        ("Asia/Kolkata", 9, "+05:30"), ("UTC", 9, "+00:00"),
    ])
    func offset(zone: String, month: Int, text: String) throws {
        let tz = try #require(TimeZone(identifier: zone))
        #expect(WeatherQuery.offset(tz, at: utc(14, 12, month: month)) == text)
    }

    @Test("The day in the zone of the place", arguments: [
        ("Europe/Berlin", 14, 23, "2026-09-15"), ("America/New_York", 15, 2, "2026-09-14"), ("UTC", 14, 12, "2026-09-14"),
    ])
    func day(zone: String, day: Int, hour: Int, text: String) throws {
        let tz = try #require(TimeZone(identifier: zone))
        #expect(WeatherQuery.day(utc(day, hour, 30), in: tz) == text)
    }

    @Test("ISO times with a zone, without seconds too", arguments: [
        ("2026-09-14T16:00:00Z", 14, 16, 0), ("2026-09-14T06:38+02:00", 14, 4, 38),
        ("2026-09-14T06:38-02:30", 14, 9, 8), ("2026-09-15T01:10+05:30", 14, 19, 40),
    ])
    func isoDate(text: String, day: Int, hour: Int, minute: Int) {
        #expect(WeatherTime.isoDate(text) == utc(day, hour, minute))
    }

    @Test("ISO time without a zone or broken: nil", arguments: [
        "2026-09-14T06:38", "2026-09-14", "broken", "2026-09-14T06:38+2", "",
    ])
    func isoDateInvalid(text: String) {
        #expect(WeatherTime.isoDate(text) == nil)
    }

    @Test("New WMO codes of the other providers", arguments: [
        (68, "Light Sleet", "cloud.sleet.fill"), (69, "Sleet", "cloud.sleet.fill"),
        (79, "Ice Pellets", "cloud.sleet.fill"), (83, "Light Sleet Showers", "cloud.sleet.fill"),
        (84, "Sleet Showers", "cloud.sleet.fill"), (-1, "Unknown", "thermometer.medium"),
    ])
    func extraCodes(code: Int, text: String, symbol: String) {
        #expect(WeatherCondition.description(code: code) == text)
        #expect(WeatherCondition.symbol(code: code, isDay: true) == symbol)
    }

    @Test("The hour row: day/night per hour comes before the sun times")
    func hourIsDay() {
        let day = DayForecast(date: local(14, 0), code: 0, maxTemperature: 20, minTemperature: 10,
                              sunrise: local(14, 6), sunset: local(14, 20), precipitationProbability: nil)
        let report = WeatherReport(
            current: CurrentWeather(time: local(14, 9), temperature: 15, apparentTemperature: nil, humidity: nil,
                                    code: 0, windSpeed: nil, isDay: true),
            hours: [HourForecast(time: local(14, 9), temperature: 15, code: 0, precipitationProbability: nil),
                    HourForecast(time: local(14, 10), temperature: 16, code: 0, precipitationProbability: nil, isDay: false),
                    HourForecast(time: local(14, 11), temperature: 17, code: 0, precipitationProbability: nil)],
            days: [day], timeZone: berlinZone
        )
        let strip = report.hourlyStrip(now: local(14, 9, 30), step: 1)
        #expect(strip.map(\.isDay) == [true, false, true])
    }
}

// MARK: - Open-Meteo

@Suite("Weather providers: Open-Meteo")
struct OpenMeteoProviderTests {
    @Test("One request, the same as before")
    func requests() {
        let requests = OpenMeteoProvider().requests(for: berlin, now: fetched)
        #expect(requests == [WeatherRequest(url: OpenMeteo.url(for: berlin))])
        #expect(requests[0].url.absoluteString.hasPrefix("https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.405&"))
    }

    @Test("Berlin: the location's zone, now, hours, seven days")
    func decode() throws {
        let r = try OpenMeteoProvider().decode([data(openMeteoBerlin)], now: fetched)
        #expect(r.calendar.timeZone.identifier == "Europe/Berlin")
        #expect(r.current.time == local(14, 18, 15))
        #expect(r.current.temperature == 17.6 && r.current.apparentTemperature == 15.6)
        #expect(r.current.code == 2 && r.current.isDay && r.current.humidity == 47)
        #expect(r.hours.count == 6 && r.hours[0].time == local(14, 18))
        #expect(r.days.count == 7)
        #expect(r.days[2].code == 95 && r.days[2].precipitationProbability == 90)
        #expect(r.days[0].sunrise == local(14, 6, 38) && r.days[0].sunset == local(14, 19, 24))
        #expect(r.hourSpacing == 3600)
    }

    @Test("without a response: error")
    func missing() {
        #expect(throws: WeatherProviderError.missingResponse) {
            try OpenMeteoProvider().decode([], now: fetched)
        }
    }
}

// MARK: - MET Norway

@Suite("Weather providers: MET Norway")
struct MetNorwayProviderTests {
    @Test("The forecast and today's sun times (optional), four places")
    func requests() {
        let requests = MetNorwayProvider(timeZone: berlinZone).requests(for: berlin, now: fetched)
        #expect(requests.map(\.url.absoluteString) == [
            "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=52.52&lon=13.405",
            "https://api.met.no/weatherapi/sunrise/3.0/sun?lat=52.52&lon=13.405&date=2026-09-14&offset=+02:00",
        ])
        #expect(requests.map(\.optional) == [false, true])
        let long = WeatherLocation(name: "Paris", latitude: 48.856614, longitude: 2.352222)
        #expect(MetNorwayProvider(timeZone: berlinZone).requests(for: long, now: fetched)[0].url.query
            == "lat=48.8566&lon=2.3522")
    }

    @Test("Now: the current hour, wind in km/h, without a feels-like temperature")
    func current() throws {
        let r = try metReport()
        #expect(r.calendar.timeZone == berlinZone)
        #expect(r.current.time == utc(14, 16))
        #expect(r.current.temperature == 17.8)
        #expect(r.current.humidity == 52)
        #expect(abs((r.current.windSpeed ?? 0) - 8.28) < 0.001)
        #expect(r.current.code == 0 && r.current.isDay)
        #expect(r.current.apparentTemperature == nil)
    }

    @Test("Hours: only the hourly part, day/night out of the symbol")
    func hours() throws {
        let r = try metReport()
        #expect(r.hours.count == 8)
        #expect(r.hours.map(\.code) == [0, 0, 0, 1, 0, 0, 3, 0])
        #expect(r.hours.map(\.isDay) == [true, false, false, false, true, true, nil, true])
        #expect(r.hours.allSatisfy { $0.precipitationProbability == nil })
        #expect(r.hourSpacing == 3600)
    }

    @Test("Days: the noon symbol, the extremes of the day, a partial last day falls away")
    func days() throws {
        let r = try metReport()
        #expect(r.days.map(\.date) == [local(14, 0), local(15, 0), local(17, 0), local(18, 0)])
        #expect(r.days.map(\.code) == [1, 1, 3, 2])
        #expect(r.days.map(\.maxTemperature) == [17.8, 23.5, 18.3, 19.3])
        #expect(r.days.map(\.minTemperature) == [15.1, 14.4, 11.9, 12.9])
        #expect(r.days.allSatisfy { $0.precipitationProbability == nil })
    }

    @Test("Sun times only for today; without Sunrise, only without them")
    func sun() throws {
        let r = try metReport()
        #expect(r.days[0].sunrise == local(14, 6, 38) && r.days[0].sunset == local(14, 19, 24))
        #expect(r.days[1].sunrise == nil)
        let without = try metReport(sun: false)
        #expect(without.days[0].sunrise == nil && without.current.code == 0)
        let broken = try MetNorwayProvider(timeZone: berlinZone).decode([data(metBerlin), data("<html>")], now: fetched)
        #expect(broken.days[0].sunset == nil)
    }

    @Test("The hour row: Now, then every two hours with night out of the symbol")
    func strip() throws {
        let strip = try metReport().hourlyStrip(now: fetched)
        #expect(strip.first?.isNow == true && strip.first?.time == utc(14, 16))
        #expect(strip[1].time == utc(14, 18) && !strip[1].isDay)
    }

    @Test("Without the required answer or without values: an error")
    func failures() {
        let provider = MetNorwayProvider(timeZone: berlinZone)
        #expect(throws: WeatherProviderError.missingResponse) { try provider.decode([nil, data(sunBerlin)], now: fetched) }
        #expect(throws: WeatherProviderError.noCurrentWeather) {
            try provider.decode([data(#"{"properties":{"timeseries":[]}}"#)], now: fetched)
        }
        #expect(throws: (any Error).self) { try provider.decode([data("<html>503</html>")], now: fetched) }
    }

    @Test("Symbol names to a WMO code and day/night", arguments: [
        ("clearsky_day", 0, Optional(true)), ("clearsky_night", 0, false), ("fair_day", 1, true),
        ("partlycloudy_polartwilight", 2, false), ("cloudy", 3, nil), ("fog", 45, nil),
        ("lightrain", 61, nil), ("heavyrain", 65, nil), ("rainshowers_night", 81, false),
        ("lightsleet", 68, nil), ("sleet", 69, nil), ("lightsleetshowers_day", 83, true),
        ("snow", 73, nil), ("heavysnowshowers_day", 86, true),
        ("lightssleetshowersandthunder_day", 95, true), ("rainandthunder", 95, nil), ("neuessymbol", -1, nil),
    ])
    func symbol(name: String, code: Int, isDay: Bool?) {
        #expect(MetNorwaySymbol.condition(name) == MetNorwaySymbol.Condition(code: code, isDay: isDay))
    }

    @Test("All 41 symbol names of MET have a text and a weather symbol", arguments: [
        "clearsky", "fair", "partlycloudy", "cloudy", "fog",
        "lightrainshowers", "rainshowers", "heavyrainshowers",
        "lightrainshowersandthunder", "rainshowersandthunder", "heavyrainshowersandthunder",
        "lightsleetshowers", "sleetshowers", "heavysleetshowers",
        "lightssleetshowersandthunder", "sleetshowersandthunder", "heavysleetshowersandthunder",
        "lightsnowshowers", "snowshowers", "heavysnowshowers",
        "lightssnowshowersandthunder", "snowshowersandthunder", "heavysnowshowersandthunder",
        "lightrain", "rain", "heavyrain", "lightrainandthunder", "rainandthunder", "heavyrainandthunder",
        "lightsleet", "sleet", "heavysleet", "lightsleetandthunder", "sleetandthunder", "heavysleetandthunder",
        "lightsnow", "snow", "heavysnow", "lightsnowandthunder", "snowandthunder", "heavysnowandthunder",
    ])
    func allSymbolsCovered(name: String) {
        let code = MetNorwaySymbol.condition(name + "_day").code
        #expect(MetNorwaySymbol.codes.count == 41)
        #expect(WeatherCondition.description(code: code) != "Unbekannt")
        #expect(WeatherCondition.symbol(code: code, isDay: false) != "thermometer.medium")
    }
}

// MARK: - wttr.in

@Suite("Weather providers: wttr.in")
struct WttrProviderTests {
    @Test("The request: coordinates in the path, JSON")
    func requests() {
        let requests = WttrProvider(timeZone: berlinZone).requests(for: berlin, now: fetched)
        #expect(requests.map(\.url.absoluteString) == ["https://wttr.in/52.52,13.405?format=j1"])
    }

    @Test("Now: the observation in UTC, the day by the sun times")
    func current() throws {
        let r = try wttrReport()
        #expect(r.current.time == utc(14, 16, 9))
        #expect(r.current.temperature == 20 && r.current.apparentTemperature == 17)
        #expect(r.current.humidity == 38 && r.current.windSpeed == 10)
        #expect(r.current.code == 3)
        #expect(r.current.isDay) // 18:09 local time, sunset 19:24
    }

    @Test("Hours every three hours, local time, the chance of rain or snow")
    func hours() throws {
        let r = try wttrReport()
        #expect(r.hours.count == 24)
        #expect(r.hours[0].time == local(14, 0) && r.hours[0].code == 80 && r.hours[0].precipitationProbability == 29)
        #expect(r.hours[23].time == local(16, 21))
        #expect(r.hourSpacing == 3 * 3600)
    }

    @Test("Three days: the condition at 12 o'clock, sun times every day")
    func days() throws {
        let r = try wttrReport()
        #expect(r.days.map(\.date) == [local(14, 0), local(15, 0), local(16, 0)])
        #expect(r.days.map(\.code) == [3, 0, 80])
        #expect(r.days.map(\.maxTemperature) == [21, 25, 21])
        #expect(r.days.map(\.minTemperature) == [14, 14, 16])
        #expect(r.days.map(\.precipitationProbability) == [29, 13, 61])
        #expect(r.days[0].sunrise == local(14, 6, 39) && r.days[0].sunset == local(14, 19, 24))
        #expect(r.days[2].sunset == local(16, 19, 20))
        #expect(r.upcomingDays(now: fetched).count == 3)
    }

    @Test("The hour row with three-hour values: Now, then every value")
    func strip() throws {
        let strip = try wttrReport().hourlyStrip(now: fetched)
        #expect(strip.count == 12)
        #expect(strip[0].isNow && strip[0].time == local(14, 18) && strip[0].temperature == 20)
        #expect(strip[1].time == local(14, 21) && !strip[1].isDay && strip[1].temperature == 17)
        #expect(strip[11].time == local(16, 3))
    }

    @Test("Numbers as a number too; an observation just before midnight belongs to the day before")
    func numbers() throws {
        let json = #"{"current_condition":[{"temp_C":-3,"weatherCode":338,"observation_time":"11:50 PM"}],"weather":[]}"#
        let r = try WttrProvider(timeZone: berlinZone).decode([data(json)], now: utc(15, 0, 5))
        #expect(r.current.temperature == -3 && r.current.code == 75)
        #expect(r.current.time == utc(14, 23, 50))
        #expect(r.current.apparentTemperature == nil && r.current.humidity == nil)
        #expect(r.days.isEmpty && r.hours.isEmpty)
    }

    @Test("The observation time: the latest point up to just after now", arguments: [
        ("04:09 PM", 14, 16, 21, 14, 16, 9), ("11:50 PM", 15, 0, 5, 14, 23, 50),
        ("12:30 AM", 14, 0, 45, 14, 0, 30), ("01:00 AM", 14, 0, 30, 14, 1, 0),
    ])
    func observation(text: String, nowDay: Int, nowHour: Int, nowMinute: Int, day: Int, hour: Int, minute: Int) {
        #expect(WttrProvider.observation(text, now: utc(nowDay, nowHour, nowMinute)) == utc(day, hour, minute))
    }

    @Test("The 12-hour clock", arguments: [
        ("06:39 AM", 6, 39), ("07:24 PM", 19, 24), ("12:05 AM", 0, 5), ("12:30 PM", 12, 30), (" 9:07 pm ", 21, 7),
    ])
    func clock(text: String, hour: Int, minute: Int) throws {
        let parsed = try #require(WttrProvider.clock12(text))
        #expect(parsed.0 == hour && parsed.1 == minute)
    }

    @Test("No time (polar summer, broken): nil", arguments: ["No sunrise", "13:00 PM", "06:39", ""])
    func clockInvalid(text: String) {
        #expect(WttrProvider.clock12(text) == nil)
    }

    @Test("Without current values: an error")
    func failures() {
        let provider = WttrProvider(timeZone: berlinZone)
        #expect(throws: WeatherProviderError.noCurrentWeather) { try provider.decode([data(#"{"weather":[]}"#)], now: fetched) }
        #expect(throws: WeatherProviderError.missingResponse) { try provider.decode([nil], now: fetched) }
    }

    @Test("WWO codes to WMO", arguments: [
        (113, 0), (116, 2), (119, 3), (122, 3), (143, 45), (176, 80), (179, 85), (182, 83), (185, 56), (200, 95),
        (248, 45), (260, 48), (266, 51), (296, 61), (302, 63), (308, 65), (314, 67), (317, 68), (320, 69),
        (326, 71), (332, 73), (338, 75), (350, 79), (353, 80), (356, 81), (359, 82), (365, 84), (368, 85),
        (371, 86), (389, 95), (395, 95), (999, -1),
    ])
    func code(wwo: Int, wmo: Int) {
        #expect(WttrCode.wmo(wwo) == wmo)
    }

    @Test("All 48 WWO codes have a text and a weather symbol", arguments: [
        113, 116, 119, 122, 143, 176, 179, 182, 185, 200, 227, 230, 248, 260, 263, 266, 281, 284, 293, 296,
        299, 302, 305, 308, 311, 314, 317, 320, 323, 326, 329, 332, 335, 338, 350, 353, 356, 359, 362, 365,
        368, 371, 374, 377, 386, 389, 392, 395,
    ])
    func allCodesCovered(wwo: Int) {
        let code = WttrCode.wmo(wwo)
        #expect(WttrCode.table.count == 48)
        #expect(WeatherCondition.description(code: code) != "Unbekannt")
        #expect(WeatherCondition.symbol(code: code, isDay: true) != "thermometer.medium")
    }
}
