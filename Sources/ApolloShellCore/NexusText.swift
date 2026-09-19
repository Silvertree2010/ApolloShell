import Foundation

/// Texte fuer Nexus (Einstellungsfenster) und die Datumszeile der Leiste.
public enum NexusText {
    /// Laufzeit seit dem Start: "3 T 4 h 12 min", "4 h 5 min", "12 min",
    /// "unter 1 min". Tage nur, wenn es welche gibt; Sekunden nie - die Seite
    /// zeichnet nicht jede Sekunde neu.
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

    /// "Version 0.1 (1)"; ohne Bundle (swift run) ein Gedankenstrich.
    public static func version(short: String?, build: String?) -> String {
        switch (short, build) {
        case let (short?, build?): String(localized: "Version \(short) (\(build))")
        case let (short?, nil): String(localized: "Version \(short)")
        default: String(localized: "Version –")
        }
    }

    /// "1 von 10" fuer die Kopfzeile der angehefteten Apps.
    public static func pinnedCount(_ count: Int, limit: Int = PinnedList.limit) -> String {
        String(localized: "\(count) of \(limit)")
    }
}

extension BarClock {
    /// Wochentag kurz ("Mo"/"Mon", je nach Sprache) - Caelestia zeigt mit
    /// showDate "ddd" ueber dem Tag. `locale`: Standard `.current` - folgt
    /// also der Sprachwahl in Nexus > Allgemein, nicht der Systemregion.
    public static func weekday(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        guard let symbols = formatter.shortStandaloneWeekdaySymbols else { return "" }
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }

    /// Tag des Monats ohne fuehrende Null (Caelestia: "d").
    public static func day(_ date: Date, calendar: Calendar) -> String {
        String(calendar.component(.day, from: date))
    }
}
