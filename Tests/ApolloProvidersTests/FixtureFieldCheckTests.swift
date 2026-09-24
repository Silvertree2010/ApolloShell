import Testing
import Foundation
import CoreGraphics
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
        session.runtime.open("dashboard", screenKey: nil)
        session.flush()
        let overview = Self.texts(try #require(session.runtime.surface("dashboard", screenKey: "main")).root)
        #expect(session.vars.set("dashboard-tab", .string("weather")))
        session.flush()
        let weather = Self.texts(try #require(session.runtime.surface("dashboard", screenKey: "main")).root)
        #expect(session.vars.set("status-popout", .string("bluetooth")))
        session.flush()
        let sidebar = Self.texts(try #require(session.runtime.surface("sidebar", screenKey: "main")).root)
        #expect(overview.contains("Partly Cloudy") && overview.contains("H:17° L:8°"))
        let calendar = try #require(overview.firstIndex(of: "September 2026"))
        #expect(Array(overview[calendar...].prefix(9)) == ["September 2026", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su", "31"])
        #expect(overview[calendar...].filter { $0 == "30" }.count == 1)
        for text in ["Feels like 12° · H:17° L:8°", "Weather data by Open-Meteo.com", "62%", "07:18", "11 km/h", "19:16", "Now", "Thu", "15°", "6°"] {
            #expect(weather.contains(text), "\(text)")
        }
        let airpods = try #require(sidebar.firstIndex(of: "AirPods Pro"))
        #expect(Array(sidebar[airpods...].prefix(9)) == ["AirPods Pro", "L", "80%", "R", "15%", "Case", "55%", "Magic Keyboard", "64%"])
        #expect(session.diagnostics.map(\.message) == [])
    }

    @Test("Zwei gleichnamige Bluetooth-Geräte geben keine Warnung über doppelte Schlüssel")
    func sidebarBluetoothDuplicateNamesNoWarning() throws {
        let text = try String(contentsOf: Self.fixtureURL, encoding: .utf8)
            .replacingOccurrences(of: "Magic Keyboard", with: "AirPods Pro")
        let fixture = ProviderFixture.parse(text, file: "apolloshell-default.kdl")
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        #expect(session.vars.set("status-popout", .string("bluetooth")))
        session.runtime.open("sidebar", screenKey: nil)
        session.flush()
        let sidebar = Self.texts(try #require(session.runtime.surface("sidebar", screenKey: "main")).root)
        #expect(sidebar.filter { $0 == "AirPods Pro" }.count == 2)
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

    @Test("Wetter-Favorit mit UUID aus 0.1.4.2 gilt beim Hinzufügen als vorhanden (Koordinaten)")
    func importedFavoriteMatchesByCoordinates() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        let place = Record([("id", .string("5C0F6A2E-1D7B-4C1B-9F59-2E1B7A0C9D11")), ("name", .string("Chur")), ("region", .null), ("country", .null), ("latitude", .number(46.85)), ("longitude", .number(9.53))])
        #expect(session.vars.set("weather-places", .list([.record(place)])))
        #expect(session.vars.set("settings-page", .string("dashboard")))
        session.runtime.open("settings", screenKey: nil)
        session.flush()
        let buttons = Self.all(try #require(session.runtime.surface("settings", screenKey: "main")).root)
            .filter { $0.kind == "button" && $0.property("tooltip") == .string("Add to Favorites") }
        #expect(buttons.count == 2)
        #expect(buttons.map { $0.property("disabled") } == [.bool(true), .bool(false)])
        let icons = buttons.map { Self.all([$0]).first { $0.kind == "icon" }?.arguments.first?.value }
        #expect(icons == [.string("checkmark.circle.fill"), .string("plus.circle.fill")])
        #expect(session.diagnostics.map(\.message) == [])
    }

    static func classes(_ element: ElementInstance) -> [String] {
        guard case .string(let value) = element.property("class") else { return [] }
        return value.split(separator: " ").map(String.init)
    }

    @Test("Media-Karte: Dash rechts, Streifen oben mit Balken, Compact unten ohne Album und Quelle")
    func mediaCardVariants() throws {
        let fixture = ProviderFixture.load(Self.fixtureURL)
        let ir = try #require(Self.builtin("apolloshell-default").ir)
        let session = FixtureFieldCheck.session(ir, fixture: fixture)
        let card = Value.record(Record([("id", .string("media")), ("kind", .string("media")), ("show-album", .bool(true)), ("show-source", .bool(true))]))
        #expect(session.vars.set("dashboard-cards-top", .list([card])))
        #expect(session.vars.set("dashboard-cards-bottom", .list([card])))
        #expect(session.vars.set("dashboard-cards-side", .list([card])))
        session.runtime.open("dashboard", screenKey: nil)
        session.flush()
        let elements = Self.all(try #require(session.runtime.surface("dashboard", screenKey: "main")).root)
        func variant(_ name: String) throws -> ElementInstance {
            try #require(elements.first { Self.classes($0).contains(name) }, "\(name)")
        }
        let tall = try variant("card-media-tall")
        #expect(Self.texts([tall]) == ["Starboy", "Starboy", "The Weeknd", "Spotify"])
        #expect(Self.all([tall]).contains { $0.kind == "ring" })
        let strip = try variant("card-media-strip")
        #expect(Self.texts([strip]) == ["Starboy", "The Weeknd · Starboy"])
        #expect(Self.all([strip]).contains { $0.kind == "progress" })
        let compact = try variant("card-media-compact")
        #expect(Self.texts([compact]) == ["Starboy", "The Weeknd"])
        #expect(Self.all([compact]).contains { $0.kind == "ring" })
        #expect(session.diagnostics.map(\.message) == [])
    }
}
