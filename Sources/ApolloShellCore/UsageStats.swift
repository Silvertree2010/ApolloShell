import Foundation

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

    public mutating func record(_ key: String, at date: Date = Date()) {
        let current = weight(for: key, at: date)
        entries[key] = Entry(score: current + 1, updated: date)
    }

    public func weight(for key: String, at date: Date = Date()) -> Double {
        guard let entry = entries[key] else { return 0 }
        let age = max(0, date.timeIntervalSince(entry.updated))
        return entry.score * pow(0.5, age / halfLife)
    }
}

extension UsageStats {
    public init(weights: [String: Double], at date: Date, halfLife: TimeInterval = UsageStats.defaultHalfLife) {
        self.init(halfLife: halfLife)
        entries = weights.mapValues { Entry(score: $0, updated: date) }
    }
}
