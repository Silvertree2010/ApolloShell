import Testing
import Foundation
import CoreGraphics
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
@Suite("Feldprüfung mit Fixture")
struct FixtureFieldCheckTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/apolloshell-default.kdl")

    static func load(_ files: [String: String]) -> ConfigLoadResult {
        let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/builtin"), userConfig: URL(fileURLWithPath: "/config"), applicationSupport: URL(fileURLWithPath: "/support"))
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(files), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        return loader.load(ConfigLocation(id: "mine", root: URL(fileURLWithPath: "/config"), isBuiltin: false))
    }

    static func builtin(_ id: String) -> ConfigLoadResult {
        let configs = root.appendingPathComponent("Resources/configs")
        let paths = ConfigPaths(builtinConfigs: configs, userConfig: URL(fileURLWithPath: "/nonexistent/config"), applicationSupport: URL(fileURLWithPath: "/nonexistent/support"))
        let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        return loader.load(ConfigLocation(id: id, root: configs.appendingPathComponent(id), isBuiltin: true))
    }

    static func keys(_ value: Value?) -> Set<String> {
        switch value {
        case .record(let record)?: Set(record.keys)
        case .list(let items)?: keys(items.first)
        default: []
        }
    }

    @Test("meldet fehlende Schlüssel in Provider-Records und each-Einträgen, nicht bei ?? und Vergleich mit null")
    func reportsMissingKeys() throws {
        let result = Self.load(["/config/shell.kdl": """
        var page "a"
        window "w" {
            text "{weather.current.condition}"
            text "{weather.current.description}"
            text "{weather.current.feels-like ?? ''}"
            text "{weather.current.wind != null}"
            each device in="{bluetooth.devices}" key="{device.name}" {
                text "{device.id}"
                text "{device.battery.left}"
            }
            switch "{var.page}" {
                case "a" { text "a" }
                case "b" { text "{weather.today.high}" }
            }
        }
        """])
        let ir = try #require(result.ir, "\(result.diagnostics.map(\.message))")
        let fixture = ProviderFixture.parse("""
        fixture {
            weather status="ready" {
                current temperature=14 description="Sunny" wind=3
                today min=4 max=12
            }
            bluetooth {
                devices {
                    - name="AirPods" kind="headphones" symbol="airpods" {
                        battery main=#null left=0.5 right=0.5 case=#null
                    }
                }
            }
        }
        """, file: "f.kdl")
        let messages = FixtureFieldCheck.run(ir, fixture: fixture).map(\.message)
        #expect(Set(messages) == [
            "'weather.current.condition' does not exist in the fixture record",
            "'device.id' does not exist in the fixture record",
            "'weather.today.high' does not exist in the fixture record",
        ])
    }

    @Test("Fixture der Default-Config hat die Record-Formen der Provider")
    func fixtureMatchesProviders() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        #expect(fixture.diagnostics.isEmpty, "\(fixture.diagnostics.map(\.message))")
        let now = Date(timeIntervalSince1970: 1_790_236_800)
        let report = FakeWeatherSource.report(at: now)
        let weather = fixture.values["weather"] ?? Record()
        #expect(Self.keys(weather["current"]) == Self.keys(WeatherReportProvider.current(report.current)))
        let day = try #require(report.upcomingDays(now: now).first)
        #expect(Self.keys(weather["today"]) == Self.keys(WeatherReportProvider.today(day)))
        #expect(Self.keys(weather["days"]) == Self.keys(WeatherReportProvider.day(day, report: report, now: now)))
        let slot = try #require(report.hourlyStrip(now: now).first)
        #expect(Self.keys(weather["hourly-strip"]) == Self.keys(WeatherReportProvider.slot(slot)))
        #expect(Self.keys(weather["search-results"]) == Self.keys(WeatherReportProvider.result(GeocodingPlace(id: 1, name: "Chur", latitude: 46.85, longitude: 9.53, admin1: nil, country: nil))))
        #expect(Self.keys(weather["attribution"]) == ["text", "url"])
        let device = BluetoothProvider.device(FakeBluetoothSource.airpods)
        #expect(Self.keys(fixture.values["bluetooth"]?["devices"]) == Self.keys(device))
        guard case .list(let devices)? = fixture.values["bluetooth"]?["devices"], case .record(let first)? = devices.first, case .record(let real) = device else {
            Issue.record("no bluetooth device")
            return
        }
        #expect(Self.keys(first["battery"]) == Self.keys(real["battery"]))
        #expect(Self.keys(fixture.values["screens"]?["list"]) == Self.keys(ScreensProvider.record(FakeScreensSource.builtin, index: 0)))
    }
}
