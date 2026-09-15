import Foundation

// Wetter fuer das Dashboard (Caelestia: services/Weather.qml). Daten von
// Open-Meteo (Vorgabe, dieselbe Quelle wie Caelestia) oder einem der anderen
// Anbieter in WeatherProvider.swift - alle ohne Schluessel und Konto.
// Hier nur reine Logik - Abruf und Oberflaeche liegen in der App.

// MARK: - Ort

/// Wofuer das Wetter gilt. Fest statt CoreLocation: Ortung wuerde einen
/// Freigabe-Dialog zeigen. Kein fester Ort mehr - stattdessen selbst
/// angelegte Favoriten (siehe `WeatherFavorites`), gespeichert in weather.json.
public struct WeatherLocation: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - Favoriten

/// Selbst angelegte Orte (Nexus > Dashboard): eine geordnete Liste plus der
/// gewaehlte, gespeichert in weather.json. Frische Installation: leer, kein
/// gewaehlter Ort - erst ein Favorit macht das Wetter abrufbar.
public struct WeatherFavorites: Equatable, Sendable {
    public var locations: [WeatherLocation]
    public var selectedID: WeatherLocation.ID?

    public init(locations: [WeatherLocation] = [], selectedID: WeatherLocation.ID? = nil) {
        self.locations = locations
        self.selectedID = selectedID
    }

    public static let empty = WeatherFavorites()

    public var selected: WeatherLocation? {
        guard let selectedID else { return nil }
        return locations.first { $0.id == selectedID }
    }

    /// Neuer Favorit ans Ende - nicht doppelt, wenn schon einer mit
    /// denselben Koordinaten da ist (dieselbe Ortssuche liefert fuer denselben
    /// Ort immer dieselben Zahlen). Der erste Favorit wird gleich gewaehlt.
    /// `false`, wenn er schon da war - dann bleibt die Liste unveraendert.
    @discardableResult
    public mutating func add(_ location: WeatherLocation) -> Bool {
        guard !locations.contains(where: { $0.sameCoordinates(as: location) }) else { return false }
        locations.append(location)
        if selectedID == nil { selectedID = location.id }
        return true
    }

    /// Entfernt einen Favoriten. War er der gewaehlte, gilt danach keiner
    /// mehr - der Aufrufer (Nexus, Wetter-Reiter) entscheidet, ob und was
    /// von Hand nachgewaehlt wird.
    public mutating func remove(id: WeatherLocation.ID) {
        locations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    /// Wie SwiftUIs `onMove`: `destination` zaehlt in der Liste VOR dem
    /// Verschieben ("vor Zeile n einfuegen"). Eigene Fassung, weil
    /// `move(fromOffsets:toOffset:)` zu SwiftUI gehoert und ApolloShellCore
    /// ohne Oberflaeche bleibt.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { locations.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { locations[$0] }
        let before = valid.filter { $0 < destination }.count
        var rest = locations.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let target = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: target)
        locations = rest
    }

    /// Nur ein vorhandener Favorit laesst sich waehlen.
    public mutating func select(id: WeatherLocation.ID) {
        guard locations.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Inhalt von weather.json. Neues Format: `{"favorites":[...],"selectedID":...}`.
    /// Erkennt zusaetzlich das alte Format eines einzelnen Orts
    /// (`{"name","latitude","longitude"}`) und macht daraus einen Favoriten -
    /// so wird eine vorhandene Datei beim ersten Start zum ersten Favoriten
    /// und zum gewaehlten Ort, ohne dass etwas verloren geht. Fehlt die
    /// Datei, ist sie kaputt oder leer: keine Favoriten.
    public static func load(from data: Data?) -> WeatherFavorites {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else { return .empty }
        if let favoriteFiles = file.favorites {
            let locations = favoriteFiles.compactMap(\.location)
            let selectedID = file.selectedID.flatMap { id in locations.contains { $0.id == id } ? id : nil }
                ?? locations.first?.id
            return WeatherFavorites(locations: locations, selectedID: selectedID)
        }
        // Migration: alte Datei mit genau einem Ort, ohne "favorites".
        guard let latitude = file.latitude, let longitude = file.longitude,
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return .empty }
        let name = file.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let location = WeatherLocation(name: name.isEmpty ? "Standort" : name, latitude: latitude, longitude: longitude)
        return WeatherFavorites(locations: [location], selectedID: location.id)
    }

    /// Zum Schreiben nach weather.json - sortierte Schluessel, eingerueckt:
    /// von Hand lesbar, und gleiche Favoriten ergeben byte-gleiche Dateien.
    public func fileData() -> Data {
        let file = File(
            favorites: locations.map { File.Location(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude) },
            selectedID: selectedID, name: nil, latitude: nil, longitude: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(file)) ?? Data()
    }

    private struct File: Codable {
        struct Location: Codable {
            let id: UUID?
            let name: String?
            let latitude: Double
            let longitude: Double

            /// `nil`, wenn die Koordinaten nicht auf der Erde liegen - so ein
            /// Eintrag faellt beim Lesen weg statt die ganze Datei zu verwerfen.
            var location: WeatherLocation? {
                guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
                let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return WeatherLocation(id: id ?? UUID(), name: trimmed.isEmpty ? "Standort" : trimmed,
                                       latitude: latitude, longitude: longitude)
            }
        }

        let favorites: [Location]?
        let selectedID: WeatherLocation.ID?
        // Nur fuer die Migration von der alten, einzeiligen Datei.
        let name: String?
        let latitude: Double?
        let longitude: Double?
    }
}

private extension WeatherLocation {
    /// Gleicher Ort, ohne die Kennung zu vergleichen - fuer die
    /// Duplikatpruefung beim Hinzufuegen.
    func sameCoordinates(as other: WeatherLocation) -> Bool {
        latitude == other.latitude && longitude == other.longitude
    }
}

// MARK: - Bericht

public struct CurrentWeather: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var apparentTemperature: Double?
    public var humidity: Int?
    public var code: Int
    public var windSpeed: Double?
    public var isDay: Bool

    public init(time: Date, temperature: Double, apparentTemperature: Double?, humidity: Int?,
                code: Int, windSpeed: Double?, isDay: Bool) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.code = code
        self.windSpeed = windSpeed
        self.isDay = isDay
    }
}

public struct HourForecast: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var code: Int
    public var precipitationProbability: Int?
    /// Tag oder Nacht, wenn der Anbieter es je Stunde sagt (MET Norway im
    /// Symbolnamen); sonst `nil` und die Sonnenzeiten entscheiden.
    public var isDay: Bool?

    public init(time: Date, temperature: Double, code: Int, precipitationProbability: Int?, isDay: Bool? = nil) {
        self.time = time
        self.temperature = temperature
        self.code = code
        self.precipitationProbability = precipitationProbability
        self.isDay = isDay
    }
}

public struct DayForecast: Equatable, Sendable {
    /// Tagesbeginn in der Zeitzone des Orts.
    public var date: Date
    public var code: Int
    public var maxTemperature: Double
    public var minTemperature: Double
    public var sunrise: Date?
    public var sunset: Date?
    public var precipitationProbability: Int?

    public init(date: Date, code: Int, maxTemperature: Double, minTemperature: Double,
                sunrise: Date?, sunset: Date?, precipitationProbability: Int?) {
        self.date = date
        self.code = code
        self.maxTemperature = maxTemperature
        self.minTemperature = minTemperature
        self.sunrise = sunrise
        self.sunset = sunset
        self.precipitationProbability = precipitationProbability
    }
}

/// Eine Spalte der Stundenleiste.
public struct HourSlot: Equatable, Sendable {
    public var time: Date
    public var temperature: Double
    public var code: Int
    public var isDay: Bool
    public var precipitationProbability: Int?
    /// Die laufende Stunde ("Jetzt").
    public var isNow: Bool
}

public struct WeatherReport: Equatable, Sendable {
    public var current: CurrentWeather
    public var hours: [HourForecast]
    public var days: [DayForecast]
    /// Deutsche Wochentage, Montag zuerst, Zeitzone des Orts: "Heute" und
    /// "14 Uhr" gelten dort, wo das Wetter ist.
    public let calendar: Calendar

    /// `locale`: Standard `.current` - folgt der Sprachwahl in Nexus >
    /// Allgemein (Wochentage, Monatsnamen in "Heute"/Langdatum). Frueher fest
    /// `de_CH`; Woche beginnt trotzdem am Montag (`firstWeekday`), das ist
    /// eine Einstellung, keine Sprachfrage.
    public init(current: CurrentWeather, hours: [HourForecast], days: [DayForecast], timeZone: TimeZone,
                locale: Locale = .current) {
        self.current = current
        self.hours = hours
        self.days = days
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    /// Abstand der Stundenwerte: eine Stunde bei Open-Meteo und MET Norway,
    /// drei bei wttr.in. Der haeufigste Abstand (Median), damit eine einzelne
    /// Luecke ihn nicht verfaelscht; ohne zwei Werte eine Stunde.
    public var hourSpacing: TimeInterval {
        let gaps = zip(hours, hours.dropFirst()).map { $1.time.timeIntervalSince($0.time) }.filter { $0 > 0 }.sorted()
        return gaps.isEmpty ? 3600 : gaps[gaps.count / 2]
    }

    /// Stundenleiste ab dem laufenden Wert, etwa alle `step` Stunden - bei
    /// Werten alle drei Stunden (wttr.in) also jeder Wert.
    ///
    /// Die erste Spalte zeigt die aktuellen Werte, sofern sie aus demselben
    /// Abschnitt stammen - sonst sagte "Jetzt" etwas anderes als die grosse
    /// Zahl daneben. Sind die Daten alt (Abruf fehlgeschlagen), rueckt die
    /// Leiste trotzdem mit der Uhr weiter und nimmt die Vorhersage.
    public func hourlyStrip(now: Date, count: Int = 12, step: Int = 2) -> [HourSlot] {
        let spacing = hourSpacing
        guard let first = hours.firstIndex(where: { $0.time.addingTimeInterval(spacing) > now }) else { return [] }
        let indexStep = max(1, Int((Double(max(step, 1)) * 3600 / spacing).rounded()))
        return stride(from: first, to: hours.count, by: indexStep).prefix(count).map { index in
            let hour = hours[index]
            let isNow = index == first && hour.time <= now
            if isNow, hour.time <= current.time, current.time < hour.time.addingTimeInterval(spacing) {
                return HourSlot(time: hour.time, temperature: current.temperature, code: current.code,
                                isDay: current.isDay, precipitationProbability: hour.precipitationProbability,
                                isNow: true)
            }
            return HourSlot(time: hour.time, temperature: hour.temperature, code: hour.code,
                            isDay: hour.isDay ?? isDay(at: hour.time),
                            precipitationProbability: hour.precipitationProbability, isNow: isNow)
        }
    }

    /// Tag oder Nacht nach Sonnenauf- und -untergang des Tages. Fehlt der Tag
    /// in den Daten, grob 7 bis 19 Uhr.
    public func isDay(at date: Date) -> Bool {
        if let day = days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }),
           let sunrise = day.sunrise, let sunset = day.sunset {
            return sunrise <= date && date < sunset
        }
        return (7..<19).contains(calendar.component(.hour, from: date))
    }

    /// Tage ab heute; vergangene fallen weg, falls die Daten von gestern sind.
    public func upcomingDays(now: Date, count: Int = 7) -> [DayForecast] {
        let today = calendar.startOfDay(for: now)
        return Array(days.filter { $0.date >= today }.prefix(count))
    }

    public func today(now: Date) -> DayForecast? {
        days.first { calendar.isDate($0.date, inSameDayAs: now) }
    }
}

// MARK: - Open-Meteo

public enum OpenMeteo {
    public enum DecodeError: Error, Equatable {
        /// Ohne aktuelle Temperatur und Wetterlage gibt es nichts anzuzeigen.
        case noCurrentWeather
    }

    /// Anfrage wie Caelestia (getWeatherUrl), plus Regenwahrscheinlichkeit
    /// pro Tag. `forecast_hours=48` statt der vollen 7 Tage: die Leiste
    /// braucht 24 Stunden ab jetzt, der Rest ist Reserve, falls ein Abruf
    /// fehlschlaegt und die Daten ein paar Stunden alt werden.
    public static func url(for location: WeatherLocation) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "forecast_hours", value: "48"),
        ]
        // Statische Teile, kann nicht scheitern.
        return components.url!
    }

    /// Open-Meteo liefert Ortszeit ohne Zone ("2026-09-14T06:58") und die Zone
    /// separat. Umgerechnet wird mit der benannten Zone, nicht mit
    /// `utc_offset_seconds`: der Versatz gilt nur fuer jetzt, ueber eine
    /// Zeitumstellung in der Wochenvorschau hinweg waere er falsch.
    public static func decode(_ data: Data) throws -> WeatherReport {
        let raw = try JSONDecoder().decode(Raw.self, from: data)

        let zone = raw.timezone.flatMap(TimeZone.init(identifier:))
            ?? raw.utcOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:))
            ?? TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        guard let c = raw.current,
              let time = localDate(c.time, calendar: calendar),
              let temperature = c.temperature2m,
              let code = c.weatherCode
        else { throw DecodeError.noCurrentWeather }
        let current = CurrentWeather(
            time: time,
            temperature: temperature,
            apparentTemperature: c.apparentTemperature,
            humidity: c.relativeHumidity2m.map { Int($0.rounded()) },
            code: code,
            windSpeed: c.windSpeed10m,
            isDay: (c.isDay ?? 1) != 0
        )

        // Einzelne Luecken (null) ueberspringen statt alles zu verwerfen.
        var hours: [HourForecast] = []
        if let h = raw.hourly {
            for (i, text) in h.time.enumerated() {
                guard let time = localDate(text, calendar: calendar),
                      let temperature = element(h.temperature2m, i),
                      let code = element(h.weatherCode, i)
                else { continue }
                hours.append(HourForecast(time: time, temperature: temperature, code: code,
                                          precipitationProbability: element(h.precipitationProbability, i)))
            }
        }

        var days: [DayForecast] = []
        if let d = raw.daily {
            for (i, text) in d.time.enumerated() {
                guard let date = localDate(text, calendar: calendar),
                      let code = element(d.weatherCode, i),
                      let max = element(d.temperature2mMax, i),
                      let min = element(d.temperature2mMin, i)
                else { continue }
                days.append(DayForecast(
                    date: date, code: code, maxTemperature: max, minTemperature: min,
                    sunrise: element(d.sunrise, i).flatMap { localDate($0, calendar: calendar) },
                    sunset: element(d.sunset, i).flatMap { localDate($0, calendar: calendar) },
                    precipitationProbability: element(d.precipitationProbabilityMax, i)
                ))
            }
        }

        return WeatherReport(current: current, hours: hours, days: days, timeZone: zone)
    }

    /// "2026-09-14T06:58" oder "2026-09-14" als Ortszeit. Von Hand statt
    /// DateFormatter: das Format ist fest, und so gibt es keine Abhaengigkeit
    /// von Locale-Einstellungen.
    static func localDate(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).compactMap { Int($0) }
        guard parts.count == 3 || parts.count == 5 else { return nil }
        var components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 0, minute: 0)
        if parts.count == 5 {
            components.hour = parts[3]
            components.minute = parts[4]
        }
        return calendar.date(from: components)
    }

    private static func element<T>(_ array: [T?]?, _ index: Int) -> T? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }

    /// Schluessel von Hand statt `.convertFromSnakeCase`: das macht aus
    /// "temperature_2m" `temperature2M` (gemessen 14.09.), nicht
    /// `temperature2m` - die Felder blieben still leer.
    private struct Raw: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature2m: Double?
            let apparentTemperature: Double?
            let relativeHumidity2m: Double?
            let weatherCode: Int?
            let windSpeed10m: Double?
            let isDay: Int?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case weatherCode = "weather_code"
                case windSpeed10m = "wind_speed_10m"
                case isDay = "is_day"
            }
        }

        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double?]?
            let weatherCode: [Int?]?
            let precipitationProbability: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]?
            let temperature2mMax: [Double?]?
            let temperature2mMin: [Double?]?
            let sunrise: [String?]?
            let sunset: [String?]?
            let precipitationProbabilityMax: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time, sunrise, sunset
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
            }
        }

        let timezone: String?
        let utcOffsetSeconds: Int?
        let current: Current?
        let hourly: Hourly?
        let daily: Daily?

        enum CodingKeys: String, CodingKey {
            case timezone, current, hourly, daily
            case utcOffsetSeconds = "utc_offset_seconds"
        }
    }
}

// MARK: - Wetterlage

/// WMO-Wettercode (Open-Meteo `weather_code`) als SF Symbol und deutscher
/// Text. Gruppen wie Caelestia (Icons.weatherIcons, getWeatherCondition),
/// Texte feiner abgestuft, weil "Regen" und "Starker Regen" etwas anderes
/// bedeuten, wenn man rausgeht.
public enum WeatherCondition {
    /// Fuer Codes anderer Anbieter, die keine Entsprechung haben: "Unbekannt"
    /// mit Thermometer. Negativ, damit er nie ein echter WMO-Code ist.
    public static let unknownCode = -1

    /// Gefuellte Varianten: nur die haben Mehrfarben-Ebenen (Sonne gelb,
    /// Regen blau). Tag/Nacht nur, wo es ein Mond-Gegenstueck gibt.
    ///
    /// 68/69 (Schneeregen), 79 (Eiskoerner) und 83/84 (Schneeregenschauer)
    /// liefert Open-Meteo nie, MET Norway und wttr.in aber schon - echte
    /// WMO-Codes statt "gefrierender Regen", der etwas anderes ist.
    public static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67, 68, 69, 79, 83, 84: "cloud.sleet.fill"
        case 61, 63: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95: "cloud.bolt.rain.fill"
        case 96, 99: "cloud.hail.fill"
        default: "thermometer.medium"
        }
    }

    public static func description(code: Int) -> String {
        switch code {
        case 0: String(localized: "Klar")
        case 1: String(localized: "Überwiegend klar")
        case 2: String(localized: "Leicht bewölkt")
        case 3: String(localized: "Bedeckt")
        case 45, 48: String(localized: "Nebel")
        case 51: String(localized: "Leichter Nieselregen")
        case 53: String(localized: "Nieselregen")
        case 55: String(localized: "Starker Nieselregen")
        case 56, 57: String(localized: "Gefrierender Nieselregen")
        case 61: String(localized: "Leichter Regen")
        case 63: String(localized: "Regen")
        case 65: String(localized: "Starker Regen")
        case 66, 67: String(localized: "Gefrierender Regen")
        case 68: String(localized: "Leichter Schneeregen")
        case 69: String(localized: "Schneeregen")
        case 71: String(localized: "Leichter Schneefall")
        case 73: String(localized: "Schnee")
        case 75: String(localized: "Starker Schneefall")
        case 77: String(localized: "Schneegriesel")
        case 79: String(localized: "Eiskörner")
        case 80: String(localized: "Leichte Regenschauer")
        case 81: String(localized: "Regenschauer")
        case 82: String(localized: "Heftige Regenschauer")
        case 83: String(localized: "Leichte Schneeregenschauer")
        case 84: String(localized: "Schneeregenschauer")
        case 85: String(localized: "Leichte Schneeschauer")
        case 86: String(localized: "Starke Schneeschauer")
        case 95: String(localized: "Gewitter")
        case 96, 99: String(localized: "Gewitter mit Hagel")
        default: String(localized: "Unbekannt")
        }
    }
}

// MARK: - Texte

/// Alle Zahlen und Zeiten als Text, fest in deutscher Schreibweise statt
/// ueber Formatter mit Systemsprache: so ist das Ergebnis testbar gleich.
public enum WeatherText {
    /// "12°", "-3°". Gerundet wie Apple Wetter; -0.4 wird "0°", nicht "-0°".
    public static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    /// "H: 22° T: 14°" wie Apple Wetter auf Deutsch ("H:22° L:14°" auf
    /// Englisch - Apple nennt den Tiefstwert dort "Low", nicht "Tief").
    public static func range(max: Double, min: Double) -> String {
        String(localized: "H: \(temperature(max)) T: \(temperature(min))")
    }

    public static func wind(_ kmh: Double) -> String {
        "\(Int(kmh.rounded())) km/h"
    }

    public static func humidity(_ percent: Int) -> String {
        "\(percent) %"
    }

    /// Regenwahrscheinlichkeit erst ab 20 %: darunter ist es Rauschen, und
    /// eine Leiste voller "3 %" liest sich wie Regenwetter.
    public static func precipitation(_ percent: Int?) -> String? {
        guard let percent, percent >= 20 else { return nil }
        return "\(percent) %"
    }

    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Zeigt an, von wann die angezeigten Daten sind, wenn sie nicht frisch sind.
    public static func stand(_ date: Date, calendar: Calendar) -> String {
        String(localized: "Stand \(clock(date, calendar: calendar))")
    }

    /// "Jetzt" oder "14 Uhr".
    public static func hourLabel(_ date: Date, isNow: Bool, calendar: Calendar) -> String {
        isNow ? String(localized: "Jetzt") : String(localized: "\(calendar.component(.hour, from: date)) Uhr")
    }

    /// "Heute", sonst zwei Buchstaben wie im Kalender ("Mo", "Di").
    public static func dayLabel(_ date: Date, today: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: today) { return String(localized: "Heute") }
        let symbol = calendar.shortStandaloneWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return String(symbol.replacingOccurrences(of: ".", with: "").prefix(2))
    }

    /// Tag und Monat kurz, im Format der Sprache: "15.9." (de), "9/15" (en).
    public static func shortDate(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.defaultDigits)
        )
    }

    /// "Montag, 14. September".
    public static func longDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekday = calendar.standaloneWeekdaySymbols[(c.weekday ?? 1) - 1]
        let month = calendar.monthSymbols[(c.month ?? 1) - 1]
        return "\(weekday), \(c.day ?? 0). \(month)"
    }
}

// MARK: - Abrufregeln

public enum WeatherRefresh {
    /// Beim Oeffnen nur abrufen, wenn die Daten aelter sind: wer das Dashboard
    /// mehrmals pro Minute oeffnet, soll nicht jedes Mal den Anbieter fragen.
    /// Passt auch zu MET Norway (hoechstens alle 10 Minuten, gemessen 14.09.:
    /// ihre Antwort gilt laut Expires gut 10 Minuten).
    public static let maxAge: TimeInterval = 15 * 60
    /// Takt, solange das Dashboard offen bleibt.
    public static let interval: TimeInterval = 30 * 60
    /// Ab hier gilt der Stand als alt, auch ohne gemeldeten Fehler (z. B.
    /// lange zu gewesen, neuer Abruf laeuft noch).
    public static let staleAfter: TimeInterval = 45 * 60

    /// Nach einem Fehlschlag, solange das Dashboard offen ist: bald nochmal
    /// statt erst nach 30 Minuten. Gemessen 14.09.: direkt nach dem Aufwachen
    /// lief der Abruf in die Zeitueberschreitung (Netz/VPN noch nicht bereit),
    /// wenige Minuten spaeter klappte derselbe Abruf.
    public static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ...1: 10
        case 2: 30
        case 3: 60
        default: 300
        }
    }

    public static func needsFetch(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= maxAge
    }

    /// "Stand HH:MM" zeigen? Nur wenn es alte Daten gibt, die nicht frisch
    /// sind - ohne Daten gibt es keinen Stand, und frische brauchen keinen.
    public static func showsStand(fetchedAt: Date?, lastAttemptFailed: Bool, now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return lastAttemptFailed || now.timeIntervalSince(fetchedAt) > staleAfter
    }
}
