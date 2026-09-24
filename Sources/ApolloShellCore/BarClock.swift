import Foundation

public enum BarClock {
    public static func hour(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.hour, from: date))
    }

    public static func minute(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.minute, from: date))
    }

    public static func nextMinute(after date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
