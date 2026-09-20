import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Dashboard-Logik")
struct DashboardLogicTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_CH")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("September 2026: faengt am Montag 31. August an, 5 Wochen")
    func september2026Grid() {
        let weeks = CalendarMonth.weeks(for: date(2026, 9, 14), today: date(2026, 9, 14), calendar: calendar)
        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks[0][0].day == 31 && !weeks[0][0].inMonth)
        #expect(weeks[0][1].day == 1 && weeks[0][1].inMonth)
        #expect(weeks[4][6].day == 4 && !weeks[4][6].inMonth)
    }

    @Test("Heute ist genau ein Tag markiert, am richtigen Platz")
    func todayMarkedOnce() {
        let weeks = CalendarMonth.weeks(for: date(2026, 9, 14), today: date(2026, 9, 14), calendar: calendar)
        let today = weeks.flatMap { $0 }.filter(\.isToday)
        #expect(today.count == 1)
        #expect(weeks[2][0].isToday) // Montag der dritten Zeile
    }

    @Test("Monat mit 6 Wochen (Maerz 2026 beginnt am Sonntag)")
    func sixWeekMonth() {
        let weeks = CalendarMonth.weeks(for: date(2026, 3, 10), today: date(2026, 9, 14), calendar: calendar)
        #expect(weeks.count == 6)
        #expect(weeks.flatMap { $0 }.filter(\.isToday).isEmpty)
    }

    @Test("Wochentage ab Montag, zweibuchstabig")
    func weekdaySymbols() {
        #expect(CalendarMonth.weekdaySymbols(calendar: calendar) == ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
    }

    @Test("CPU-Auslastung aus der Tick-Differenz")
    func cpuUsage() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let new = CPUTicks(user: 130, system: 60, idle: 860, nice: 0)
        // busy 40, idle 60 -> 40 %
        #expect(ResourceMath.cpuUsage(from: old, to: new) == 0.4)
    }

    @Test("CPU ohne Veraenderung oder mit zuruecklaufenden Zaehlern: nil")
    func cpuUsageDegenerate() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 0)
        #expect(ResourceMath.cpuUsage(from: ticks, to: ticks) == nil)
        #expect(ResourceMath.cpuUsage(from: ticks, to: CPUTicks(user: 0, system: 1, idle: 1, nice: 0)) == nil)
    }

    @Test("Anteile werden begrenzt")
    func fractionClamped() {
        #expect(ResourceMath.fraction(used: 50, total: 200) == 0.25)
        #expect(ResourceMath.fraction(used: 300, total: 200) == 1)
        #expect(ResourceMath.fraction(used: 1, total: 0) == 0)
    }

    // Ausgerechnete Werte: mit `3.0 * 3600 + 12 * 60` im Array gibt der
    // Values worked out by hand: with `3.0 * 3600 + 12 * 60` in the array the
    // type checker gives up ("unable to type-check in reasonable time").
    @Test("Uptime text", arguments: [
        (TimeInterval(2_700), "45m"),      // 45 minutes
        (TimeInterval(11_520), "3h 12m"),  // 3 h 12 min
        (TimeInterval(183_600), "2d 3h"),  // 2 days 3 h
    func uptime(seconds: TimeInterval, text: String) {
        #expect(UptimeText.format(seconds: seconds) == text)
    }
}
