import Foundation

/// Texts for Nexus (settings window) and the bar's date row.
public enum NexusText {
    /// Runtime since launch: "3d 4h 12min", "4h 5min", "12min",
    /// "under 1 min". Days only if there are any; seconds never - the page
    /// doesn't redraw every second.
    public static func uptime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds)) / 60
        let days = total / (24 * 60)
        let hours = total / 60 % 24
        let minutes = total % 60
        if days == 0, hours == 0, minutes == 0 { return String(localized: "under 1 min") }
        var parts: [String] = []
        if days > 0 { parts.append(String(localized: "\(days)d")) }
        if days > 0 || hours > 0 { parts.append(String(localized: "\(hours)h")) }
        parts.append(String(localized: "\(minutes)min"))
        return parts.joined(separator: " ")
    }

    /// "Version 0.1 (1)"; without a bundle (swift run) an em dash.
    public static func version(short: String?, build: String?) -> String {
        switch (short, build) {
        case let (short?, build?): String(localized: "Version \(short) (\(build))")
        case let (short?, nil): String(localized: "Version \(short)")
        default: String(localized: "Version –")
        }
    }

    /// "1 of 10" for the header of pinned apps.
    public static func pinnedCount(_ count: Int, limit: Int = PinnedList.limit) -> String {
        String(localized: "\(count) of \(limit)")
    }
}

extension BarClock {
    /// Short weekday ("Mo"/"Mon", depending on language) - Caelestia shows
    /// "ddd" above the day with showDate. `locale`: default `.current` - so it
    /// follows the language choice in Nexus > General, not the system region.
    public static func weekday(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        guard let symbols = formatter.shortStandaloneWeekdaySymbols else { return "" }
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// Day of the month without a leading zero (Caelestia: "d").
    public static func day(_ date: Date, calendar: Calendar) -> String {
        String(calendar.component(.day, from: date))
    }
}
