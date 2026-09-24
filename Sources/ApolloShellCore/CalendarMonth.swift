import Foundation

public struct CalendarDay: Hashable, Sendable {
    public let date: Date
    public let day: Int
    public let inMonth: Bool
    public let isToday: Bool
}

public enum CalendarMonth {
    public static func weeks(for month: Date, today: Date, calendar: Calendar) -> [[CalendarDay]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let start = interval.start
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let weekCount = (offset + daysInMonth + 6) / 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offset, to: start) else { return [] }

        return (0..<weekCount).map { week in
            (0..<7).compactMap { index in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + index, to: gridStart) else { return nil }
                return CalendarDay(
                    date: date,
                    day: calendar.component(.day, from: date),
                    inMonth: calendar.isDate(date, equalTo: start, toGranularity: .month),
                    isToday: calendar.isDate(date, inSameDayAs: today)
                )
            }
        }
    }

    public static func weekNumbers(_ weeks: [[CalendarDay]], calendar: Calendar) -> [Int] {
        weeks.map { week in week.first.map { calendar.component(.weekOfYear, from: $0.date) } ?? 0 }
    }

    public static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map {
            String($0.replacingOccurrences(of: ".", with: "").prefix(2))
        }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

public enum UptimeText {
    public static func format(seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let days = minutes / (60 * 24)
        let hours = (minutes / 60) % 24
        let mins = minutes % 60
        if days > 0 { return String(localized: "\(days)d \(hours)h") }
        if hours > 0 { return String(localized: "\(hours)h \(mins)m") }
        return String(localized: "\(mins)m")
    }
}
