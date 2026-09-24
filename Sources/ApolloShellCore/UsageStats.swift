import Foundation

/// Wie oft und wie kuerzlich eine App benutzt wurde ("Frecency").
///
/// Jede Nutzung zaehlt 1 Punkt, und jeder Punkt verliert mit der Zeit an
/// Gewicht: nach `halfLife` ist er nur noch halb so viel wert. Eine App, die
/// du letzte Woche zehnmal geoeffnet hast, steht damit vor einer, die du vor
/// einem Monat zwanzigmal geoeffnet hast.
///
/// Pro App werden nur zwei Werte gespeichert, Punktestand und Zeitpunkt.
/// Der Zerfall wird beim Lesen nachgerechnet, die Datei waechst also nicht
/// mit jeder Nutzung.
public struct UsageStats: Codable, Sendable, Equatable {
    public static let defaultHalfLife: TimeInterval = 7 * 24 * 60 * 60

    struct Entry: Codable, Sendable, Equatable {
        var score: Double
        var updated: Date
    }

    private(set) var entries: [String: Entry] = [:]
    public var halfLife: TimeInterval

    public init(halfLife: TimeInterval = UsageStats.defaultHalfLife) {
        self.halfLife = halfLife
    }

    /// Eine Nutzung verbuchen: bisheriges Gewicht bis jetzt abklingen
    /// lassen, dann einen Punkt dazu.
    public mutating func record(_ key: String, at date: Date = Date()) {
        let current = weight(for: key, at: date)
        entries[key] = Entry(score: current + 1, updated: date)
    }

    /// Aktuelles Gewicht, 0 fuer nie benutzte Apps.
    public func weight(for key: String, at date: Date = Date()) -> Double {
        guard let entry = entries[key] else { return 0 }
        let age = max(0, date.timeIntervalSince(entry.updated))
        return entry.score * pow(0.5, age / halfLife)
    }
}
