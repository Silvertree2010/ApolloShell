import Testing
import Foundation
import ApolloShellCore
@testable import ApolloConfig

@Suite("Standarddienste der Filter")
struct DefaultFilterServicesTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        calendar.locale = Locale(identifier: "de_CH")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static let services = DefaultFilterServices(calendar: calendar)

    static func app(_ name: String, bundleID: String, usage: Double? = nil, favoriteIndex: Double? = nil) -> Value {
        var record = Record([
            ("name", .string(name)),
            ("bundle-id", .string(bundleID)),
            ("path", .string("/Applications/\(name).app")),
        ])
        if let usage {
            record["usage"] = .number(usage)
        }
        if let favoriteIndex {
            record["favorite-index"] = .number(favoriteIndex)
        }
        return .record(record)
    }

    static let apps: [Value] = [
        app("Safari", bundleID: "com.apple.Safari", usage: 3),
        app("Firefox", bundleID: "org.mozilla.firefox", usage: 0),
        app("Notes", bundleID: "com.apple.Notes", favoriteIndex: 0),
        app("Affinity", bundleID: "com.seriflabs.affinity", usage: 10),
        app("Calculator", bundleID: "com.apple.calculator", usage: 0.01),
        .string("not an app"),
    ]

    static func names(_ values: [Value]) -> [String] {
        values.compactMap { value in
            guard case .record(let record) = value, case .string(let name)? = record["name"] else { return nil }
            return name
        }
    }

    @Test("app-search ohne Anfrage: Favoriten, dann benutzte nach Gewicht, dann alphabetisch (AppRanker)")
    func appSearchWithoutQuery() {
        #expect(Self.names(Self.services.appSearch(Self.apps, query: "")) == ["Notes", "Affinity", "Safari", "Calculator", "Firefox"])
    }

    @Test("app-search mit Anfrage: Trefferqualität schlägt gedeckelten Nutzungsbonus")
    func appSearchWithQuery() {
        #expect(Self.names(Self.services.appSearch(Self.apps, query: "fi")) == ["Firefox", "Affinity", "Safari"])
        #expect(Self.services.appSearch(Self.apps, query: "zzz").isEmpty)
    }

    @Test("app-search behält doppelte Einträge und gibt die Original-Records zurück")
    func appSearchKeepsRecords() {
        let twice = [Self.apps[0], Self.apps[0]]
        #expect(Self.services.appSearch(twice, query: "") == twice)
    }

    static func day(_ grid: Value, _ row: Int, _ column: Int) -> Record? {
        guard case .list(let weeks) = grid, weeks.indices.contains(row),
              case .list(let days) = weeks[row], days.indices.contains(column),
              case .record(let record) = days[column]
        else { return nil }
        return record
    }

    static func rowCount(_ grid: Value) -> Int {
        guard case .list(let weeks) = grid else { return 0 }
        return weeks.count
    }

    @Test("month-grid: September 2026 mit Montag als erstem Tag, ISO-Wochen, heute markiert")
    func monthGridMonday() throws {
        let grid = Self.services.monthGrid(FilterHarness.now, offset: 0, firstWeekday: "system")
        #expect(Self.rowCount(grid) == 5)
        let first = try #require(Self.day(grid, 0, 0))
        #expect(first["day"] == Value.number(31))
        #expect(first["in-month"] == Value.bool(false))
        #expect(first["weekday"] == Value.number(1))
        #expect(first["week"] == Value.number(36))
        #expect(first.keys == ["day", "in-month", "today", "weekday", "week", "date"])
        let today = try #require(Self.day(grid, 3, 3))
        #expect(today["day"] == Value.number(24))
        #expect(today["today"] == Value.bool(true))
        #expect(today["weekday"] == Value.number(4))
        #expect(today["week"] == Value.number(39))
        let last = try #require(Self.day(grid, 4, 6))
        #expect(last["day"] == Value.number(4))
        #expect(last["in-month"] == Value.bool(false))
        #expect(last["weekday"] == Value.number(7))
        #expect(last["week"] == Value.number(40))
    }

    @Test("month-grid: Sonntag als erster Tag und Versatz um einen Monat")
    func monthGridSundayAndOffset() throws {
        let sunday = Self.services.monthGrid(FilterHarness.now, offset: 0, firstWeekday: "sunday")
        #expect(Self.rowCount(sunday) == 5)
        let first = try #require(Self.day(sunday, 0, 0))
        #expect(first["day"] == Value.number(30))
        #expect(first["weekday"] == Value.number(7))
        let october = Self.services.monthGrid(FilterHarness.now, offset: 1, firstWeekday: "monday")
        #expect(Self.rowCount(october) == 5)
        let start = try #require(Self.day(october, 0, 0))
        #expect(start["day"] == Value.number(28))
        #expect(start["today"] == Value.bool(false))
    }

    @Test("Laufzeit, Adressen, Symbole, Temperatur wie 0.1.4.2")
    func simpleServices() {
        #expect(Self.services.uptimeText(183_600) == UptimeText.format(seconds: 183_600))
        #expect(Self.services.uptimeText(183_600) == "2d 3h")
        #expect(Self.services.uptimeText(1e300) == UptimeText.format(seconds: 1e12))
        #expect(Self.services.normalizedURL("example.com") == "https://example.com")
        #expect(Self.services.normalizedURL("mailto:a@b.ch") == "mailto:a@b.ch")
        #expect(Self.services.normalizedURL("not a url") == nil)
        #expect(Self.services.symbolExists("anything"))
        #expect(Self.services.temperatureText(21.4) == "21°")
        #expect(Self.services.temperatureText(-0.4) == "0°")
        #expect(Self.services.temperatureText(.infinity) == "")
    }

    @Test("Tastenkombinationen: Anzeige und Warnung nach HotKeyAdvice")
    func chords() {
        #expect(Self.services.chordDisplay("alt+space") == "⌥Space")
        #expect(Self.services.chordDisplay("hyper+d") == "⌃⌥⇧⌘D")
        #expect(Self.services.chordDisplay("nonsense") == "nonsense")
        #expect(Self.services.hotkeyWarning("cmd+space") == HotKeyText.warning(.system("Spotlight")))
        #expect(Self.services.hotkeyWarning("alt+u") == HotKeyText.warning(.typesCharacters))
        #expect(Self.services.hotkeyWarning("ctrl+alt+d") == nil)
        #expect(Self.services.hotkeyWarning("nonsense") == nil)
    }
}
