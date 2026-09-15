import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: Anbieter in settings.json")
struct ShellSettingsProvidersTests {
    @Test("ohne Abschnitt: Open-Meteo und automatischer Dateimanager")
    func missing() {
        let settings = ShellSettings.load(from: Data(#"{"bar":{"showClock":false}}"#.utf8))
        #expect(settings.providers == ShellSettings.Providers())
        #expect(settings.providers.weather == .openMeteo && settings.providers.fileManager == nil)
        // Der alte Schalter wandert in die Leiste (BarLayout.migrated): ohne Uhr.
        #expect(!settings.bar.layout.contains(.clock))
    }

    @Test("gueltig, unbekannt, falscher Typ, leer", arguments: [
        (#"{"providers":{"weather":"metNorway"}}"#, "metNorway", Optional<String>.none),
        (#"{"providers":{"weather":"wttr","fileManager":"org.yanex.marta"}}"#, "wttr", "org.yanex.marta"),
        (#"{"providers":{"weather":"darksky","fileManager":"com.apple.finder"}}"#, "openMeteo", "com.apple.finder"),
        (#"{"providers":{"weather":3,"fileManager":7}}"#, "openMeteo", nil),
        (#"{"providers":{"fileManager":"   "}}"#, "openMeteo", nil),
        (#"{"providers":{"fileManager":" com.cocoatech.PathFinder "}}"#, "openMeteo", "com.cocoatech.PathFinder"),
        (#"{"providers":{"fileManager":null}}"#, "openMeteo", nil),
        (#"{"providers":"kaputt"}"#, "openMeteo", nil),
        (#"{"providers":[]}"#, "openMeteo", nil),
    ])
    func decoding(json: String, weather: String, fileManager: String?) {
        let providers = ShellSettings.load(from: Data(json.utf8)).providers
        #expect(providers.weather.rawValue == weather)
        #expect(providers.fileManager == fileManager)
    }

    @Test("kaputter Abschnitt laesst die anderen stehen")
    func isolated() {
        let settings = ShellSettings.load(from: Data(#"{"providers":{"weather":"wttr"},"toasts":{"batteryWarnings":false}}"#.utf8))
        #expect(settings == ShellSettings(toasts: .init(batteryWarnings: false), providers: .init(weather: .wttr)))
    }

    @Test("schreiben und wieder lesen", arguments: [
        ("openMeteo", Optional<String>.none), ("metNorway", "com.apple.finder"), ("wttr", "org.yanex.marta"),
    ])
    func roundTrip(weather: String, fileManager: String?) throws {
        let id = try #require(WeatherProviderID(rawValue: weather))
        let settings = ShellSettings(providers: .init(weather: id, fileManager: fileManager))
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
    }

    @Test("die Datei nennt die Schluessel, fileManager auch leer", arguments: [
        "\"providers\"", "\"weather\" : \"openMeteo\"", "\"fileManager\" : null",
    ])
    func keysWritten(text: String) {
        #expect(String(decoding: ShellSettings().encoded(), as: UTF8.self).contains(text))
    }
}
