import Testing
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime
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
        #expect(Self.keys(weather["today"]) == Self.keys(WeatherReportProvider.today(day, report: report)))
        #expect(Self.keys(weather["days"]) == Self.keys(WeatherReportProvider.day(day, report: report, now: now)))
        let slot = try #require(report.hourlyStrip(now: now).first)
        #expect(Self.keys(weather["hourly-strip"]) == Self.keys(WeatherReportProvider.slot(slot, report: report)))
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

    @Test("Default-Config und launcher-only lesen keinen Schlüssel, den die Provider nicht liefern")
    func defaultConfigsReadOnlyExistingFields() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        for id in ["apolloshell-default", "launcher-only"] {
            let result = Self.builtin(id)
            let ir = try #require(result.ir, "\(result.diagnostics.map(\.message))")
            let findings = FixtureFieldCheck.run(ir, fixture: fixture)
            let lines = findings.map { "\($0.span.map { "\($0.file.split(separator: "/").suffix(2).joined(separator: "/")):\($0.start.line)" } ?? "") \($0.message)" }
            #expect(lines == [], "\(id)")
        }
    }


    static func texts(_ roots: [ElementInstance]) -> [String] {
        var out: [String] = []
        var stack = Array(roots.reversed())
        while let element = stack.popLast() {
            if element.kind == "text", let first = element.arguments.first {
                switch first.value {
                case .string(let text): out.append(text)
                case .number(let number): out.append(number == number.rounded() ? String(Int(number)) : String(number))
                default: out.append("\(first.value)")
                }
            }
            for slot in element.slotChildren.values.reversed() { stack.append(contentsOf: slot.reversed()) }
            stack.append(contentsOf: element.children.reversed())
        }
        return out
    }

    @Test("Wetter, Kalender und Bluetooth zeigen die Fixture-Werte")
    func surfacesShowFixtureValues() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        session.runtime.open("dash", screenKey: nil)
        session.flush()
        let overview = Self.texts(try #require(session.runtime.surface("dash", screenKey: "main")).root)
        #expect(overview.contains("Partly Cloudy") && overview.contains("14°"))
        let calendar = try #require(overview.firstIndex(of: "September 2026"))
        #expect(overview[calendar...].contains("30"))
        #expect(session.vars.set("dt", .string("wx")))
        session.flush()
        let weather = Self.texts(try #require(session.runtime.surface("dash", screenKey: "main")).root)
        for text in ["Feels like", "12°", "62%", "07:18 – 19:16", "11 km/h", "Now", "Today", "Fr", "15°", "6°"] {
            #expect(weather.contains(text), "\(text) \(weather)")
        }
        #expect(session.vars.set("pv", .string("bt")))
        #expect(session.vars.set("po", .bool(true)))
        session.flush()
        let bar = Self.texts(try #require(session.runtime.surface("bar", screenKey: "main")).root)
        let airpods = try #require(bar.firstIndex(of: "AirPods Pro"))
        #expect(Array(bar[airpods...].prefix(4)) == ["AirPods Pro", "L 80% · R 15%", "Magic Keyboard", "64%"], "\(bar)")
        #expect(session.diagnostics.map(\.message) == [])
    }

    @Test("Zwei gleichnamige Bluetooth-Geräte geben keine Warnung über doppelte Schlüssel")
    func sidebarBluetoothDuplicateNamesNoWarning() throws {
        let text = try String(contentsOf: Self.fixtureURL, encoding: .utf8)
            .replacingOccurrences(of: "Magic Keyboard", with: "AirPods Pro")
        let fixture = ProviderFixture.parse(text, file: "apolloshell-default.kdl")
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        #expect(session.vars.set("pv", .string("bt")))
        session.flush()
        let bar = Self.texts(try #require(session.runtime.surface("bar", screenKey: "main")).root)
        #expect(bar.filter { $0 == "AirPods Pro" }.count == 2)
        #expect(!session.diagnostics.map(\.message).contains { $0.contains("duplicate keys") })
    }

    static func all(_ roots: [ElementInstance]) -> [ElementInstance] {
        var out: [ElementInstance] = []
        var stack = Array(roots.reversed())
        while let element = stack.popLast() {
            out.append(element)
            for slot in element.slotChildren.values.reversed() { stack.append(contentsOf: slot.reversed()) }
            stack.append(contentsOf: element.children.reversed())
        }
        return out
    }

    @Test("Ein Suchtreffer in den Wetter-Einstellungen wird der Ort des Dashboards")
    func searchResultBecomesPlace() async throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        #expect(session.vars.set("pg", .string("wx")))
        session.runtime.open("prefs", screenKey: nil)
        session.flush()
        let buttons = Self.all(try #require(session.runtime.surface("prefs", screenKey: "main")).root)
            .filter { $0.kind == "button" && Self.texts([$0]).contains("Zürich") }
        let zurich = try #require(buttons.first)
        await session.runtime.trigger("on-click", on: zurich.identity, event: Record())?.value
        session.flush()
        guard case .record(let place) = session.vars.value("wp") else {
            Issue.record("no place")
            return
        }
        #expect(place["name"] == .string("Zürich"))
        #expect(session.diagnostics.map(\.message) == [])
    }

    static func classes(_ element: ElementInstance) -> [String] {
        guard case .string(let value) = element.property("class") else { return [] }
        return value.split(separator: " ").map(String.init)
    }

    @Test("Media-Karte und Media-Seite zeigen Titel, Album, Künstler und Quelle")
    func mediaCardVariants() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        session.runtime.open("dash", screenKey: nil)
        session.flush()
        let elements = Self.all(try #require(session.runtime.surface("dash", screenKey: "main")).root)
        let card = try #require(elements.first { Self.classes($0).contains("cmed") })
        #expect(Self.texts([card]) == ["Starboy", "Starboy", "The Weeknd"])
        #expect(Self.all([card]).contains { $0.kind == "ring" })
        #expect(session.vars.set("dt", .string("media")))
        session.flush()
        let shown = Self.all(try #require(session.runtime.surface("dash", screenKey: "main")).root)
        let pane = try #require(shown.first { Self.classes($0).contains("pmed") })
        let texts = Self.texts([pane])
        #expect(texts.prefix(3) == ["Starboy", "The Weeknd", "Starboy"], "\(texts)")
        #expect(texts.contains("Playing in Spotify"))
        #expect(session.diagnostics.map(\.message) == [])
    }
}
