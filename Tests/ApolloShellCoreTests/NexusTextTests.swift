import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: Texte")
struct NexusTextTests {
    @Test("Laufzeit", arguments: [
        (0.0, "unter 1 min"),
        (59.9, "unter 1 min"),
        (60.0, "1 min"),
        (3_900.0, "1 h 5 min"),
        (86_430.0, "1 T 0 h 0 min"),
        (274_320.0, "3 T 4 h 12 min"),
        (-5.0, "unter 1 min"),
    ])
    func uptime(seconds: Double, expected: String) {
        #expect(NexusText.uptime(seconds) == expected)
    }

    @Test("Version aus dem Bundle", arguments: [
        ("0.1", "1", "Version 0.1 (1)"),
        ("0.1", nil, "Version 0.1"),
        (nil, "1", "Version –"),
        (nil, nil, "Version –"),
    ] as [(String?, String?, String)])
    func version(short: String?, build: String?, expected: String) {
        #expect(NexusText.version(short: short, build: build) == expected)
    }

    @Test("Zaehler der angehefteten Apps", arguments: [(0, "0 von 10"), (10, "10 von 10")])
    func pinnedCount(count: Int, expected: String) {
        #expect(NexusText.pinnedCount(count) == expected)
    }

    @Test("Datum der Leistenuhr: Wochentag kurz, Tag ohne Null", arguments: [
        (13, "So", "13"), (14, "Mo", "14"), (17, "Do", "17"), (19, "Sa", "19"), (1, "Di", "1"),
    ])
    func barDate(day: Int, weekday: String, dayText: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Zurich"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12)))
        #expect(BarClock.weekday(date, calendar: calendar, locale: Locale(identifier: "de_CH")) == weekday)
        #expect(BarClock.day(date, calendar: calendar) == dayText)
    }
}
