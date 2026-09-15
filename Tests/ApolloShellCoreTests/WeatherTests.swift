import Foundation
import Testing
@testable import ApolloShellCore

/// Echte Antwort von Open-Meteo fuer einen Testort (abgerufen 14.09.2026,
/// 01:00), gekuerzt: Einheiten weg, nur die ersten 6 Stunden.
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

/// Feste Zone, damit nichts von der Maschine abhaengt.
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

@Suite("Wetter: Open-Meteo lesen")
struct OpenMeteoDecodingTests {
    @Test("Aktuelle Werte aus der echten Antwort")
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

    @Test("Stunden: Ortszeit Mitteleuropa, 01:00 MESZ ist 23:00 UTC am Vortag")
    func hours() throws {
        let r = try report()
        #expect(r.hours.count == 6)
        #expect(r.hours[0].time == zurich(14, 1))
        #expect(r.hours[0].time.timeIntervalSince1970 == 1_789_340_400) // 2026-09-13T23:00Z
        #expect(r.hours[4].code == 80)
        #expect(r.hours[5].precipitationProbability == 43)
    }

    @Test("Tage: Hoechst-/Tiefstwerte, Sonne, Regenwahrscheinlichkeit")
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

    @Test("Luecken (null): Stunde ohne Temperatur faellt weg, fehlende Wahrscheinlichkeit wird nil")
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

    @Test("Ohne Zonennamen: Versatz aus utc_offset_seconds")
    func offsetFallback() throws {
        let json = """
        {"utc_offset_seconds":3600,"current":{"time":"2026-01-10T12:00","temperature_2m":-1.0,"weather_code":71}}
        """
        let r = try OpenMeteo.decode(Data(json.utf8))
        #expect(r.calendar.timeZone.secondsFromGMT() == 3600)
        #expect(r.hours.isEmpty && r.days.isEmpty)
    }

    @Test("Ohne aktuelle Werte oder kaputt: Fehler statt leerer Bericht")
    func failures() {
        #expect(throws: OpenMeteo.DecodeError.noCurrentWeather) {
            try OpenMeteo.decode(Data(#"{"timezone":"Europe/Zurich"}"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try OpenMeteo.decode(Data("<html>502</html>".utf8))
        }
    }

    @Test("Anfrage: Koordinaten, alle Felder, Ortszeit")
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

@Suite("Wetter: Ort aus weather.json (Migration von einem einzelnen Ort)")
struct WeatherLocationTests {
    @Test("Ohne Datei: keine Favoriten")
    func missing() {
        #expect(WeatherFavorites.load(from: nil) == .empty)
    }

    @Test("Gueltige alte Datei wird zum ersten, gewaehlten Favoriten")
    func valid() {
        let data = Data(#"{"name":"Oslo","latitude":59.9139,"longitude":10.7522}"#.utf8)
        let favorites = WeatherFavorites.load(from: data)
        #expect(favorites.locations.map(\.name) == ["Oslo"])
        #expect(favorites.selected?.name == "Oslo")
    }

    @Test("Kaputt oder ausserhalb der Erde: keine Favoriten")
    func invalid() {
        #expect(WeatherFavorites.load(from: Data("{".utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":95,"longitude":9}"#.utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":"47"}"#.utf8)) == .empty)
    }

    @Test("Ohne Namen: Koordinaten gelten, Name 'Standort'")
    func unnamed() {
        let data = Data(#"{"latitude":48.2082,"longitude":16.3738}"#.utf8)
        #expect(WeatherFavorites.load(from: data).selected?.name == "Standort")
    }
}

@Suite("Wetter: Code zu Symbol und Text")
struct WeatherConditionTests {
    @Test("Symbole mit Tag/Nacht", arguments: [
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

    @Test("Deutsche Beschreibung", arguments: [
        (0, "Klar"), (1, "Überwiegend klar"), (2, "Leicht bewölkt"), (3, "Bedeckt"), (45, "Nebel"),
        (48, "Nebel"), (53, "Nieselregen"), (63, "Regen"), (65, "Starker Regen"), (73, "Schnee"),
        (81, "Regenschauer"), (95, "Gewitter"), (96, "Gewitter mit Hagel"), (4, "Unbekannt"),
    ])
    func description(code: Int, text: String) {
        #expect(WeatherCondition.description(code: code) == text)
    }

    @Test("Jeder WMO-Code, den Open-Meteo liefert, hat Text und Wettersymbol", arguments: [
        0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
    ])
    func allCodesCovered(code: Int) {
        #expect(WeatherCondition.description(code: code) != "Unbekannt")
        #expect(WeatherCondition.symbol(code: code, isDay: true) != "thermometer.medium")
        #expect(WeatherCondition.symbol(code: code, isDay: false) != "thermometer.medium")
    }
}

@Suite("Wetter: Texte")
struct WeatherTextTests {
    @Test("Temperatur gerundet, ohne minus null", arguments: [
        (12.4, "12°"), (12.5, "13°"), (0.0, "0°"), (-0.4, "0°"), (-2.6, "-3°"),
    ])
    func temperature(value: Double, text: String) {
        #expect(WeatherText.temperature(value) == text)
    }

    @Test("Wind, Feuchte, Spanne")
    func units() {
        #expect(WeatherText.wind(1.5) == "2 km/h")
        #expect(WeatherText.wind(12.3) == "12 km/h")
        #expect(WeatherText.humidity(85) == "85 %")
        #expect(WeatherText.range(max: 22.4, min: 14.7) == "H: 22° T: 15°")
    }

    @Test("Regenwahrscheinlichkeit erst ab 20 %", arguments: [
        (Optional(19), String?.none), (Optional(20), Optional("20 %")), (Optional(93), Optional("93 %")), (nil, nil),
    ])
    func precipitation(percent: Int?, text: String?) {
        #expect(WeatherText.precipitation(percent) == text)
    }

    @Test("Uhrzeiten zweistellig, Stundenleiste in Uhr")
    func clock() {
        #expect(WeatherText.clock(zurich(14, 6, 58), calendar: zurichCalendar) == "06:58")
        #expect(WeatherText.stand(zurich(14, 1, 15), calendar: zurichCalendar) == "Stand 01:15")
        #expect(WeatherText.hourLabel(zurich(14, 14), isNow: false, calendar: zurichCalendar) == "14 Uhr")
        #expect(WeatherText.hourLabel(zurich(15, 0), isNow: false, calendar: zurichCalendar) == "0 Uhr")
        #expect(WeatherText.hourLabel(zurich(14, 14), isNow: true, calendar: zurichCalendar) == "Jetzt")
    }

    @Test("Wochentage: Heute, dann zwei Buchstaben")
    func dayLabels() {
        let today = zurich(14, 9) // Montag
        #expect(WeatherText.dayLabel(zurich(14, 0), today: today, calendar: zurichCalendar) == "Heute")
        #expect(WeatherText.dayLabel(zurich(15, 0), today: today, calendar: zurichCalendar) == "Di")
        #expect(WeatherText.dayLabel(zurich(20, 0), today: today, calendar: zurichCalendar) == "So")
        #expect(WeatherText.dayLabel(zurich(21, 0), today: today, calendar: zurichCalendar) == "Mo")
    }

    @Test("Datum kurz und lang")
    func dates() {
        #expect(WeatherText.shortDate(zurich(15, 0), calendar: zurichCalendar, locale: Locale(identifier: "de_CH")) == "15.9.")
        #expect(WeatherText.shortDate(zurich(15, 0), calendar: zurichCalendar, locale: Locale(identifier: "en_US")) == "9/15")
        #expect(WeatherText.longDate(zurich(14, 9), calendar: zurichCalendar) == "Montag, 14. September")
    }
}

@Suite("Wetter: Stundenleiste, Tag/Nacht, Tage")
struct WeatherReportTests {
    @Test("Jetzt: aktuelle Werte in der ersten Spalte, dann alle 2 Stunden")
    func stripNow() throws {
        let strip = try report().hourlyStrip(now: zurich(14, 1, 20))
        #expect(strip.map(\.time) == [zurich(14, 1), zurich(14, 3), zurich(14, 5)])
        #expect(strip[0].isNow && !strip[1].isNow)
        #expect(strip[0].temperature == 16.4 && strip[0].code == 61 && !strip[0].isDay)
        #expect(strip[0].precipitationProbability == 45)
        #expect(strip[2].temperature == 15.2 && strip[2].code == 80)
    }

    @Test("Alte Daten: Leiste rueckt mit der Uhr weiter und nimmt die Vorhersage")
    func stripStale() throws {
        let strip = try report().hourlyStrip(now: zurich(14, 2, 10))
        #expect(strip.map(\.time) == [zurich(14, 2), zurich(14, 4), zurich(14, 6)])
        #expect(strip[0].isNow)
        #expect(strip[0].temperature == 16.8) // Vorhersage 02:00, nicht "aktuell" von 01:00
    }

    @Test("Vor der ersten Stunde kein Jetzt, nach der letzten nichts")
    func stripEdges() throws {
        let r = try report()
        #expect(r.hourlyStrip(now: zurich(14, 0, 30)).first?.isNow == false)
        #expect(r.hourlyStrip(now: zurich(14, 7, 5)).isEmpty)
        #expect(r.hourlyStrip(now: zurich(14, 1, 20), count: 2, step: 1).map(\.time) == [zurich(14, 1), zurich(14, 2)])
    }

    @Test("Tag und Nacht nach Sonnenauf- und -untergang")
    func dayNight() throws {
        let r = try report()
        #expect(r.isDay(at: zurich(14, 7, 30)))
        #expect(!r.isDay(at: zurich(14, 6, 30)))
        #expect(r.isDay(at: zurich(14, 19, 30)))
        #expect(!r.isDay(at: zurich(14, 19, 40)))
        // Tag nicht in den Daten: grob 7 bis 19 Uhr.
        #expect(r.isDay(at: zurich(25, 12)))
        #expect(!r.isDay(at: zurich(25, 23)))
    }

    @Test("Tage ab heute, vergangene fallen weg")
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

@Suite("Wetter: wann abrufen, wann Stand zeigen")
struct WeatherRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_789_400_000)

    @Test("Abrufen ohne Daten oder ab 15 Minuten Alter")
    func needsFetch() {
        #expect(WeatherRefresh.needsFetch(fetchedAt: nil, now: now))
        #expect(!WeatherRefresh.needsFetch(fetchedAt: now.addingTimeInterval(-600), now: now))
        #expect(WeatherRefresh.needsFetch(fetchedAt: now.addingTimeInterval(-900), now: now))
    }

    @Test("Stand nur bei alten Daten oder nach Fehler, nie ohne Daten")
    func showsStand() {
        #expect(!WeatherRefresh.showsStand(fetchedAt: nil, lastAttemptFailed: true, now: now))
        #expect(!WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-60), lastAttemptFailed: false, now: now))
        #expect(WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-60), lastAttemptFailed: true, now: now))
        #expect(WeatherRefresh.showsStand(fetchedAt: now.addingTimeInterval(-3000), lastAttemptFailed: false, now: now))
    }
}
