import Foundation
import Testing
@testable import ApolloShellCore

/// A real answer from Open-Meteo for a test place (fetched 14.09.2026,
/// 01:00), shortened: the units gone, only the first 6 hours.
private let fixture = """
{"latitude":47.0,"longitude":9.52,"utc_offset_seconds":7200,"timezone":"Europe/Zurich","timezone_abbreviation":"GMT+2","elevation":510.0,
"current":{"time":"2026-09-14T01:00","interval":900,"temperature_2m":16.4,"apparent_temperature":17.4,"relative_humidity_2m":85,"weather_code":61,"wind_speed_10m":1.5,"is_day":0},
"hourly":{"time":["2026-09-14T01:00","2026-09-14T02:00","2026-09-14T03:00","2026-09-14T04:00","2026-09-14T05:00","2026-09-14T06:00"],
"temperature_2m":[16.4,16.8,16.4,15.9,15.2,15.1],"weather_code":[61,61,61,61,80,45],"precipitation_probability":[45,48,50,55,45,43]},
"daily":{"time":["2026-09-14","2026-09-15","2026-09-16","2026-09-17","2026-09-18","2026-09-19","2026-09-20"],
"weather_code":[80,2,95,61,3,3,3],"temperature_2m_max":[22.4,26.5,24.3,18.0,20.3,23.1,24.2],"temperature_2m_min":[14.7,14.2,12.2,10.2,12.1,11.9,13.6],
"sunrise":["2026-09-14T06:58","2026-09-15T06:59","2026-09-16T07:00","2026-09-17T07:01","2026-09-18T07:03","2026-09-19T07:04","2026-09-20T07:05"],
"sunset":["2026-09-14T19:35","2026-09-15T19:33","2026-09-16T19:31","2026-09-17T19:29","2026-09-18T19:27","2026-09-19T19:26","2026-09-20T19:24"],
"precipitation_probability_max":[70,0,93,78,15,14,13]}}
"""

/// A fixed zone, so that nothing hangs on the machine.
private let zurichCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "de_CH")
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    calendar.firstWeekday = 2
    return calendar
}()

private func zurich(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    zurichCalendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func report() throws -> WeatherReport {
    try OpenMeteo.decode(Data(fixture.utf8))
}

@Suite("Weather: reading Open-Meteo")
struct OpenMeteoDecodingTests {
    @Test("The current values out of the real answer")
    func current() throws {
        let r = try report()
        #expect(r.calendar.timeZone.identifier == "Europe/Zurich")
        #expect(r.current.time == zurich(14, 1))
        #expect(r.current.temperature == 16.4)
        #expect(r.current.apparentTemperature == 17.4)
        #expect(r.current.humidity == 85)
        #expect(r.current.code == 61)
        #expect(r.current.windSpeed == 1.5)
        #expect(r.current.isDay == false)
    }

    @Test("Hours: local time in Central Europe, 01:00 CEST is 23:00 UTC the day before")
    func hours() throws {
        let r = try report()
        #expect(r.hours.count == 6)
        #expect(r.hours[0].time == zurich(14, 1))
        #expect(r.hours[0].time.timeIntervalSince1970 == 1_789_340_400) // 2026-09-13T23:00Z
        #expect(r.hours[4].code == 80)
        #expect(r.hours[5].precipitationProbability == 43)
    }

    @Test("Days: highs and lows, sun, chance of rain")
    func days() throws {
        let r = try report()
        #expect(r.days.count == 7)
        #expect(r.days[0].date == zurich(14, 0))
        #expect(r.days[1].maxTemperature == 26.5)
        #expect(r.days[1].minTemperature == 14.2)
        #expect(r.days[0].sunrise == zurich(14, 6, 58))
        #expect(r.days[0].sunset == zurich(14, 19, 35))
        #expect(r.days[2].code == 95)
        #expect(r.days[2].precipitationProbability == 93)
    }

    @Test("Gaps (null): an hour without a temperature falls away, a missing chance becomes nil")
    func nulls() throws {
        let json = """
        {"timezone":"Europe/Zurich","current":{"time":"2026-09-14T01:00","temperature_2m":3.0,"weather_code":0},
        "hourly":{"time":["2026-09-14T01:00","2026-09-14T02:00"],"temperature_2m":[null,2.0],"weather_code":[0,0],"precipitation_probability":[null,null]},
        "daily":{"time":["2026-09-14"],"weather_code":[0],"temperature_2m_max":[9.0],"temperature_2m_min":[1.0],"sunrise":[null],"sunset":[null]}}
        """
        let r = try OpenMeteo.decode(Data(json.utf8))
        #expect(r.hours.count == 1)
        #expect(r.hours[0].time == zurich(14, 2))
        #expect(r.hours[0].precipitationProbability == nil)
        #expect(r.days[0].sunrise == nil)
        #expect(r.days[0].precipitationProbability == nil)
        #expect(r.current.humidity == nil)
        #expect(r.current.isDay) // ohne Angabe lieber Tag als Nacht
    }

    @Test("Without a zone name: the offset out of utc_offset_seconds")
    func offsetFallback() throws {
        let json = """
        {"utc_offset_seconds":3600,"current":{"time":"2026-01-10T12:00","temperature_2m":-1.0,"weather_code":71}}
        """
        let r = try OpenMeteo.decode(Data(json.utf8))
        #expect(r.calendar.timeZone.secondsFromGMT() == 3600)
        #expect(r.hours.isEmpty && r.days.isEmpty)
    }

    @Test("Without current values or broken: an error instead of an empty report")
    func failures() {
        #expect(throws: OpenMeteo.DecodeError.noCurrentWeather) {
            try OpenMeteo.decode(Data(#"{"timezone":"Europe/Zurich"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try OpenMeteo.decode(Data("<html>502</html>".utf8))
        }
    }

    @Test("The request: coordinates, all fields, local time")
    func url() {
        let location = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
        let url = OpenMeteo.url(for: location).absoluteString
        #expect(url.hasPrefix("https://api.open-meteo.com/v1/forecast?latitude=52.52&longitude=13.405&"))
        #expect(url.contains("current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"))
        #expect(url.contains("hourly=temperature_2m,weather_code,precipitation_probability"))
        #expect(url.contains("daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"))
        #expect(url.contains("timezone=auto"))
        #expect(url.contains("forecast_days=7"))
    }
}

@Suite("Weather: the place out of weather.json (migration from a single place)")
struct WeatherLocationTests {
    @Test("Without a file: no favourites")
    func missing() {
        #expect(WeatherFavorites.load(from: nil) == .empty)
    }

    @Test("A valid old file becomes the first, chosen favourite")
    func valid() {
        let data = Data(#"{"name":"Oslo","latitude":59.9139,"longitude":10.7522}"#.utf8)
        let favorites = WeatherFavorites.load(from: data)
        #expect(favorites.locations.map(\.name) == ["Oslo"])
        #expect(favorites.selected?.name == "Oslo")
    }

    @Test("Broken or off the Earth: no favourites")
    func invalid() {
        #expect(WeatherFavorites.load(from: Data("{".utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":95,"longitude":9}"#.utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":"47"}"#.utf8)) == .empty)
    }

    @Test("Without a name: the coordinates count, the name 'Location'")
    func unnamed() {
        let data = Data(#"{"latitude":48.2082,"longitude":16.3738}"#.utf8)
        #expect(WeatherFavorites.load(from: data).selected?.name == "Location")
    }
}

@Suite("Weather: code to symbol and text")
struct WeatherConditionTests {
    @Test("Symbols with day/night", arguments: [
        (0, true, "sun.max.fill"), (0, false, "moon.stars.fill"),
        (1, true, "sun.max.fill"), (2, true, "cloud.sun.fill"), (2, false, "cloud.moon.fill"),
        (3, false, "cloud.fill"), (45, true, "cloud.fog.fill"), (53, false, "cloud.drizzle.fill"),
        (56, true, "cloud.sleet.fill"), (63, true, "cloud.rain.fill"), (65, true, "cloud.heavyrain.fill"),
        (73, false, "cloud.snow.fill"), (80, true, "cloud.sun.rain.fill"), (81, false, "cloud.moon.rain.fill"),
        (95, true, "cloud.bolt.rain.fill"), (99, false, "cloud.hail.fill"), (42, true, "thermometer.medium"),
    ])
    func symbol(code: Int, isDay: Bool, symbol: String) {
        #expect(WeatherCondition.symbol(code: code, isDay: isDay) == symbol)
    }

    @Test("Description", arguments: [
        (0, "Clear"), (1, "Mostly Clear"), (2, "Partly Cloudy"), (3, "Overcast"), (45, "Fog"),
        (48, "Fog"), (53, "Drizzle"), (63, "Rain"), (65, "Heavy Rain"), (73, "Snow"),
        (81, "Rain Showers"), (95, "Thunderstorm"), (96, "Thunderstorm with Hail"), (4, "Unknown"),
    ])
    func description(code: Int, text: String) {
        #expect(WeatherCondition.description(code: code) == text)
    }

    @Test("Every WMO code Open-Meteo delivers has a text and a weather symbol", arguments: [
        0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
    ])
    func allCodesCovered(code: Int) {
        #expect(WeatherCondition.description(code: code) != "Unknown")
        #expect(WeatherCondition.symbol(code: code, isDay: true) != "thermometer.medium")
        #expect(WeatherCondition.symbol(code: code, isDay: false) != "thermometer.medium")
    }
}

@Suite("Weather: texts")
struct WeatherTextTests {
    @Test("The temperature rounded, without a minus zero", arguments: [
        (12.4, "12°"), (12.5, "13°"), (0.0, "0°"), (-0.4, "0°"), (-2.6, "-3°"),
    ])
    func temperature(value: Double, text: String) {
        #expect(WeatherText.temperature(value) == text)
    }

    @Test("Wind, humidity, range")
    func units() {
        #expect(WeatherText.wind(1.5) == "2 km/h")
        #expect(WeatherText.wind(12.3) == "12 km/h")
        #expect(WeatherText.humidity(85) == "85 %")
        #expect(WeatherText.range(max: 22.4, min: 14.7) == "H:22° L:15°")
    }

    @Test("The chance of rain only from 20 % on", arguments: [
        (Optional(19), String?.none), (Optional(20), Optional("20 %")), (Optional(93), Optional("93 %")), (nil, nil),
    ])
    func precipitation(percent: Int?, text: String?) {
        #expect(WeatherText.precipitation(percent) == text)
    }

    @Test("Times with two digits, the hour row in hours")
    func clock() {
        #expect(WeatherText.clock(zurich(14, 6, 58), calendar: zurichCalendar) == "06:58")
        #expect(WeatherText.stand(zurich(14, 1, 15), calendar: zurichCalendar) == "As of 01:15")
        #expect(WeatherText.hourLabel(zurich(14, 14), isNow: false, calendar: zurichCalendar) == "14:00")
        #expect(WeatherText.hourLabel(zurich(15, 0), isNow: false, calendar: zurichCalendar) == "0:00")
        #expect(WeatherText.hourLabel(zurich(14, 14), isNow: true, calendar: zurichCalendar) == "Now")
    }

    @Test("Weekdays: Today, then two letters")
    func dayLabels() {
        let today = zurich(14, 9) // Montag
        #expect(WeatherText.dayLabel(zurich(14, 0), today: today, calendar: zurichCalendar) == "Today")
        #expect(WeatherText.dayLabel(zurich(15, 0), today: today, calendar: zurichCalendar) == "Di")
        #expect(WeatherText.dayLabel(zurich(20, 0), today: today, calendar: zurichCalendar) == "So")
        #expect(WeatherText.dayLabel(zurich(21, 0), today: today, calendar: zurichCalendar) == "Mo")
    }

    @Test("The date short and long")
    func dates() {
        #expect(WeatherText.shortDate(zurich(15, 0), calendar: zurichCalendar, locale: Locale(identifier: "de_CH")) == "15.9.")
        #expect(WeatherText.shortDate(zurich(15, 0), calendar: zurichCalendar, locale: Locale(identifier: "en_US")) == "9/15")
        #expect(WeatherText.longDate(zurich(14, 9), calendar: zurichCalendar) == "Montag, September 14")
    }
}

@Suite("Weather: the hour row, day/night, days")
struct WeatherReportTests {
    @Test("Now: the current values in the first column, then every 2 hours")
    func stripNow() throws {
        let strip = try report().hourlyStrip(now: zurich(14, 1, 20))
        #expect(strip.map(\.time) == [zurich(14, 1), zurich(14, 3), zurich(14, 5)])
        #expect(strip[0].isNow && !strip[1].isNow)
        #expect(strip[0].temperature == 16.4 && strip[0].code == 61 && !strip[0].isDay)
        #expect(strip[0].precipitationProbability == 45)
        #expect(strip[2].temperature == 15.2 && strip[2].code == 80)
    }

    @Test("Old data: the row moves on with the clock and takes the forecast")
    func stripStale() throws {
        let strip = try report().hourlyStrip(now: zurich(14, 2, 10))
        #expect(strip.map(\.time) == [zurich(14, 2), zurich(14, 4), zurich(14, 6)])
        #expect(strip[0].isNow)
        #expect(strip[0].temperature == 16.8) // Vorhersage 02:00, nicht "aktuell" von 01:00
    }

    @Test("Before the first hour no Now, after the last one nothing")
    func stripEdges() throws {
        let r = try report()
        #expect(r.hourlyStrip(now: zurich(14, 0, 30)).first?.isNow == false)
        #expect(r.hourlyStrip(now: zurich(14, 7, 5)).isEmpty)
        #expect(r.hourlyStrip(now: zurich(14, 1, 20), count: 2, step: 1).map(\.time) == [zurich(14, 1), zurich(14, 2)])
    }

    @Test("Day and night by sunrise and sunset")
    func dayNight() throws {
        let r = try report()
        #expect(r.isDay(at: zurich(14, 7, 30)))
        #expect(!r.isDay(at: zurich(14, 6, 30)))
        #expect(r.isDay(at: zurich(14, 19, 30)))
        #expect(!r.isDay(at: zurich(14, 19, 40)))
        // The day not in the data: roughly 7 to 19 o'clock.
        #expect(r.isDay(at: zurich(25, 12)))
        #expect(!r.isDay(at: zurich(25, 23)))
    }

    @Test("Days from today on, past ones fall away")
    func upcomingDays() throws {
        let r = try report()
        #expect(r.upcomingDays(now: zurich(14, 9)).count == 7)
        let later = r.upcomingDays(now: zurich(15, 10))
        #expect(later.count == 6)
        #expect(later.first?.date == zurich(15, 0))
        #expect(r.today(now: zurich(15, 23, 59))?.maxTemperature == 26.5)
        #expect(r.today(now: zurich(21, 12)) == nil)
    }
}

@Suite("Weather: when to fetch, when to show the age")
struct WeatherRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_789_400_000)

    @Test("Fetch without data or from an age of 15 minutes on")
    func needsFetch() {
        #expect(WeatherRefresh.needsFetch(fetchedAt: nil, now: now))
        #expect(!WeatherRefresh.needsFetch(fetchedAt: now.addingTimeInterval(-600), now: now))
        #expect(WeatherRefresh.needsFetch(fetchedAt: now.addingTimeInterval(-900), now: now))
    }

    @Test("The age only with old data or after an error, never without data")
    func showsStand() {
        #expect(!WeatherRefresh.showsStand(fetchedAt: nil, lastAttemptFailed: true, now: now))
        #expect(!WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-60), lastAttemptFailed: false, now: now))
        #expect(WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-60), lastAttemptFailed: true, now: now))
        #expect(WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-3000), lastAttemptFailed: false, now: now))
    }
}
