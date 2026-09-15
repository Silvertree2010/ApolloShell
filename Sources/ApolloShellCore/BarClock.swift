import Foundation

/// Texte und Takt der Uhr in der Leiste (Caelestia: bar/components/Clock.qml,
/// Stunde und Minute untereinander, ohne Sekunden).
public enum BarClock {
    /// Immer 24 Stunden, zweistellig - unabhaengig von der Region, sonst
    /// stuende bei englischer Einstellung "2" statt "14" in der Leiste.
    public static func hour(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.hour, from: date))
    }

    public static func minute(_ date: Date, calendar: Calendar) -> String {
        twoDigits(calendar.component(.minute, from: date))
    }

    /// Beginn der naechsten Minute. Genau auf einer Minutengrenze ist das die
    /// danach - so plant ein Timer, der puenktlich feuert, nicht dieselbe
    /// Minute noch einmal.
    public static func nextMinute(after date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.end ?? date.addingTimeInterval(60)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
