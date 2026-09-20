import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: providers in settings.json")
struct ShellSettingsProvidersTests {
    @Test("without a section: Open-Meteo and automatic file manager")
    func missing() {
        let settings = ShellSettings.load(from: Data(#"{"bar":{"showClock":false}}"#.utf8))
        #expect(settings.providers == ShellSettings.Providers())
        #expect(settings.providers.weather == .openMeteo && settings.providers.fileManager == nil)
        // The old switch moves into the bar (BarLayout.migrated): without a clock.
        #expect(!settings.bar.layout.contains(.clock))
    }

    @Test("valid, unknown, wrong type, empty", arguments: [
        (#"{"providers":{"weather":"metNorway"}}"#, "metNorway", Optional<String>.none),
        (#"{"providers":{"weather":"wttr","fileManager":"org.yanex.marta"}}"#, "wttr", "org.yanex.marta"),
        (#"{"providers":{"weather":"darksky","fileManager":"com.apple.finder"}}"#, "openMeteo", "com.apple.finder"),
        (#"{"providers":{"weather":3,"fileManager":7}}"#, "openMeteo", nil),
        (#"{"providers":{"fileManager":"   "}}"#, "openMeteo", nil),
        (#"{"providers":{"fileManager":" com.cocoatech.PathFinder "}}"#, "openMeteo", "com.cocoatech.PathFinder"),
        (#"{"providers":{"fileManager":null}}"#, "openMeteo", nil),
        (#"{"providers":"broken"}"#, "openMeteo", nil),
        (#"{"providers":[]}"#, "openMeteo", nil),
    ])
    func decoding(json: String, weather: String, fileManager: String?) {
        let providers = ShellSettings.load(from: Data(json.utf8)).providers
        #expect(providers.weather.rawValue == weather)
        #expect(providers.fileManager == fileManager)
    }

    @Test("a broken section leaves the others intact")
    func isolated() {
        let settings = ShellSettings.load(from: Data(#"{"providers":{"weather":"wttr"},"toasts":{"batteryWarnings":false}}"#.utf8))
        #expect(settings == ShellSettings(toasts: .init(batteryWarnings: false), providers: .init(weather: .wttr)))
    }

    @Test("write and read back", arguments: [
        ("openMeteo", Optional<String>.none), ("metNorway", "com.apple.finder"), ("wttr", "org.yanex.marta"),
    ])
    func roundTrip(weather: String, fileManager: String?) throws {
        let id = try #require(WeatherProviderID(rawValue: weather))
        let settings = ShellSettings(providers: .init(weather: id, fileManager: fileManager))
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
    }

    @Test("the file names the keys, fileManager too when empty", arguments: [
        "\"providers\"", "\"weather\" : \"openMeteo\"", "\"fileManager\" : null",
    ])
    func keysWritten(text: String) {
        #expect(String(decoding: ShellSettings().encoded(), as: UTF8.self).contains(text))
    }
}
