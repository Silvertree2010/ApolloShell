import Foundation

/// Texts and cadence of the clock in the bar (Caelestia: bar/components/Clock.qml,
/// hour and minute stacked, without seconds).
public enum BarClock {
    /// Always 24 hours, two digits - regardless of the region, otherwise
    /// an English setting would show "2" instead of "14" in the bar.
    public static func hour(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.hour, from: date))
    }

    public static func minute(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.minute, from: date))
    }

    /// Start of the next minute. Right on a minute boundary that is the one
    /// after it - so a timer that fires exactly on time doesn't plan the same
    /// minute again.
    public static func nextMinute(after date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
