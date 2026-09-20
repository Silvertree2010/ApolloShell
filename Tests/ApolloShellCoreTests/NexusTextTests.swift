import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: texts")
struct NexusTextTests {
    @Test("Uptime", arguments: [
        (0.0, "under 1 min"),
        (59.9, "under 1 min"),
        (60.0, "1min"),
        (3_900.0, "1h 5min"),
        (86_430.0, "1d 0h 0min"),
        (274_320.0, "3d 4h 12min"),
        (-5.0, "under 1 min"),
    ])
    func uptime(seconds: Double, expected: String) {
        #expect(NexusText.uptime(seconds) == expected)
    }

    @Test("Version out of the bundle", arguments: [
        ("0.1", "1", "Version 0.1 (1)"),
        ("0.1", nil, "Version 0.1"),
        (nil, "1", "Version –"),
        (nil, nil, "Version –"),
    ] as [(String?, String?, String)])
    func version(short: String?, build: String?, expected: String) {
        #expect(NexusText.version(short: short, build: build) == expected)
    }

    @Test("Counter of the pinned apps", arguments: [(0, "0 of 10"), (10, "10 of 10")])
    func pinnedCount(count: Int, expected: String) {
        #expect(NexusText.pinnedCount(count) == expected)
    }

    @Test("Date of the bar clock: short weekday, day without a leading zero", arguments: [
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
