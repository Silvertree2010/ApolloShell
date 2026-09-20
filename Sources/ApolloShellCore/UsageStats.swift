import Foundation

/// How often and how recently an app was used ("frecency").
///
/// Every use counts 1 point, and every point loses weight over time: after
/// `halfLife` it is only worth half as much. An app you opened ten times last
/// week therefore stands before one you opened twenty times a month ago.
/// einem Monat zwanzigmal geoeffnet hast.
///
/// Only two values are stored per app, the score and the time. The decay is
/// worked out when reading, so the file does not grow with every use.
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

    /// Book a use: let the weight so far decay up to now, then add a point.
    public mutating func record(_ key: String, at date: Date = Date()) {
        let current = weight(for: key, at: date)
        entries[key] = Entry(score: current + 1, updated: date)
    }

    /// The current weight, 0 for apps that were never used.
    public func weight(for key: String, at date: Date = Date()) -> Double {
        guard let entry = entries[key] else { return 0 }
        let age = max(0, date.timeIntervalSince(entry.updated))
        return entry.score * pow(0.5, age / halfLife)
    }
}
