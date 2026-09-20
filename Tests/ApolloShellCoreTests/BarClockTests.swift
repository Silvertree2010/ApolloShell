import Foundation
import Testing
@testable import ApolloShellCore

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

/// 14.09.2026 in UTC, to the second (with a fraction).
private func utc(_ hour: Int, _ minute: Int, _ second: Double = 0) -> Date {
    let base = calendar("UTC").date(from: DateComponents(year: 2026, month: 9, day: 14, hour: hour, minute: minute))!
    return base.addingTimeInterval(second)
}

@Suite("The clock in the bar")
struct BarClockTests {
    @Test("24 hours, two digits", arguments: [
        (14, 5, "14", "05"), (0, 0, "00", "00"), (9, 59, "09", "59"), (23, 7, "23", "07"),
    ])
    func twoDigits(hour: Int, minute: Int, hourText: String, minuteText: String) {
        let date = utc(hour, minute)
        #expect(BarClock.hour(date, calendar: calendar("UTC")) == hourText)
        #expect(BarClock.minute(date, calendar: calendar("UTC")) == minuteText)
    }

    @Test("Local time out of the calendar: 12:05 UTC is 14:05 in Central Europe (summer time)")
    func timeZone() {
        let date = utc(12, 5)
        #expect(BarClock.hour(date, calendar: calendar("Europe/Zurich")) == "14")
        #expect(BarClock.minute(date, calendar: calendar("Europe/Zurich")) == "05")
    }

    @Test("the next full minute, with a fraction of a second too")
    func nextMinuteMidway() {
        #expect(BarClock.nextMinute(after: utc(14, 5, 30.5), calendar: calendar("UTC")) == utc(14, 6))
        #expect(BarClock.nextMinute(after: utc(14, 5, 59.99), calendar: calendar("UTC")) == utc(14, 6))
    }

    @Test("exactly on the boundary: the minute after it, not the same one")
    func nextMinuteOnBoundary() {
        #expect(BarClock.nextMinute(after: utc(14, 6), calendar: calendar("UTC")) == utc(14, 7))
        #expect(BarClock.nextMinute(after: utc(23, 59, 59), calendar: calendar("UTC")) == utc(0, 0).addingTimeInterval(86_400))
    }
}
