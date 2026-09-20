import Foundation
import Testing
@testable import ApolloShellCore

/// Antwort der Ortssuche fuer "Springfield" (Feld-Struktur wie Open-Meteo,
/// eigene Testdaten): gleichnamige Orte in verschiedenen Bundesstaaten, wie
/// bei Buchs AG/SG in der echten Schnittstelle.
private let springfield = """
{"results":[{"id":4926166,"name":"Springfield","latitude":39.78421,"longitude":-89.64371,"elevation":180.0,"feature_code":"PPLA2","country_code":"US","admin1_id":4896861,"admin2_id":4250384,"timezone":"America/Chicago","population":114230,"postcodes":["62701"],"country_id":6252001,"country":"Vereinigte Staaten","admin1":"Illinois","admin2":"Sangamon County"},{"id":4409896,"name":"Springfield","latitude":37.21533,"longitude":-93.29824,"elevation":409.0,"feature_code":"PPLA2","country_code":"US","admin1_id":4398678,"admin2_id":4404128,"timezone":"America/Chicago","population":159498,"postcodes":["65801"],"country_id":6252001,"country":"Vereinigte Staaten","admin1":"Missouri","admin2":"Greene County"},{"id":4951788,"name":"Springfield","latitude":42.10148,"longitude":-72.58981,"elevation":21.0,"feature_code":"PPLA2","country_code":"US","admin1_id":6254926,"admin2_id":4936544,"timezone":"America/New_York","postcodes":["01101"],"country_id":6252001,"country":"Vereinigte Staaten","admin1":"Massachusetts","admin2":"Hampden County"}],"generationtime_ms":0.8020401}
"""

@Suite("Nexus: Ortssuche von Open-Meteo")
struct GeocodingTests {
    @Test("drei Treffer aus der Antwort, in ihrer Reihenfolge", arguments: [
        (0, 4926166, "Springfield", "Illinois, Vereinigte Staaten", 39.78421, -89.64371),
        (1, 4409896, "Springfield", "Missouri, Vereinigte Staaten", 37.21533, -93.29824),
        (2, 4951788, "Springfield", "Massachusetts, Vereinigte Staaten", 42.10148, -72.58981),
    ])
    func places(index: Int, id: Int, name: String, detail: String, latitude: Double, longitude: Double) throws {
        let places = try OpenMeteoGeocoding.decode(Data(springfield.utf8))
        #expect(places.count == 3)
        let place = places[index]
        #expect(place.id == id)
        #expect(place.name == name)
        #expect(place.detail == detail)
        #expect(place.location.name == name)
        #expect(place.location.latitude == latitude)
        #expect(place.location.longitude == longitude)
    }

    @Test("nichts gefunden: Antwort ohne results ist eine leere Liste", arguments: [
        #"{"generationtime_ms":0.119805336}"#, #"{"results":[]}"#,
    ])
    func noResults(json: String) throws {
        #expect(try OpenMeteoGeocoding.decode(Data(json.utf8)).isEmpty)
    }

    @Test("Treffer ohne Namen oder mit Koordinaten neben der Erde fallen weg", arguments: [
        #"{"results":[{"id":1,"latitude":47,"longitude":9},{"id":2,"name":"Oslo","latitude":59.91,"longitude":10.75}]}"#,
        #"{"results":[{"id":1,"name":"X","latitude":123,"longitude":9},{"id":2,"name":"Oslo","latitude":59.91,"longitude":10.75}]}"#,
        #"{"results":[{"id":1,"name":"  ","latitude":1,"longitude":1},{"id":2,"name":"Oslo","latitude":59.91,"longitude":10.75,"admin1":""}]}"#,
    ])
    func skipsBroken(json: String) throws {
        let places = try OpenMeteoGeocoding.decode(Data(json.utf8))
        #expect(places.map(\.name) == ["Oslo"])
        #expect(places.first?.detail.isEmpty == true)
    }

    @Test("kein JSON: Fehler statt leerer Liste", arguments: ["kaputt", ""])
    func brokenThrows(json: String) {
        #expect(throws: (any Error).self) { try OpenMeteoGeocoding.decode(Data(json.utf8)) }
    }

    @Test("Adresse: Suchtext gekuerzt und kodiert, 5 Treffer, deutsch", arguments: [
        ("Bern", "name=Bern"),
        ("  Oslo \n", "name=Oslo&"),
        ("Lissabon", "name=Lissabon"),
    ])
    func url(query: String, expectedName: String) throws {
        let url = try #require(OpenMeteoGeocoding.url(for: query))
        #expect(url.host() == "geocoding-api.open-meteo.com")
        #expect(url.path() == "/v1/search")
        let text = url.absoluteString
        #expect(text.contains(expectedName))
        #expect(text.contains("count=\(OpenMeteoGeocoding.count)"))
        #expect(text.contains("language=\(OpenMeteoGeocoding.language)"))
    }

    @Test("zu kurzer Suchtext: gar keine Anfrage", arguments: ["", " ", "C", " C \n"])
    func tooShort(query: String) {
        #expect(OpenMeteoGeocoding.url(for: query) == nil)
    }

    @Test("Favoriten schreiben und wieder lesen", arguments: [
        WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405),
        WeatherLocation(name: "Wien", latitude: 48.2082, longitude: 16.3738),
        WeatherLocation(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
    ])
    func fileRoundTrip(location: WeatherLocation) {
        var favorites = WeatherFavorites.empty
        favorites.add(location)
        let loaded = WeatherFavorites.load(from: favorites.fileData())
        #expect(loaded.locations == [location])
        #expect(loaded.selected == location)
    }

    @Test("Coordinates in a German locale keep the decimal comma", arguments: [
        (47.00601, 9.50266, "47,01° N, 9,50° E"),
        (-33.8688, 151.2093, "33,87° S, 151,21° E"),
        (40.7128, -74.006, "40,71° N, 74,01° W"),
    ])
    func coordinates(latitude: Double, longitude: Double, expected: String) {
        let location = WeatherLocation(name: "", latitude: latitude, longitude: longitude)
    @Test("Coordinates in English with a decimal point")
    }

    @Test("Koordinaten englisch mit Dezimalpunkt")
    func coordinatesEnglish() {
        let text = WeatherLocation(name: "", latitude: 47.00601, longitude: 9.50266)
            .coordinateText(locale: Locale(identifier: "en_US"))
        // Die Himmelsrichtung uebersetzt erst die App (en.lproj), die Tests
        // laufen ohne Uebersetzung.
        #expect(text.hasPrefix("47.01° N, 9.50° "))
    }
}
