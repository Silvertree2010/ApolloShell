import Foundation

/// Sorts the app list.
///
/// Without a search text: used apps by their usage weight first, the rest
/// alphabetically behind them.
///
/// With a search text: the hit quality of the fuzzy search decides, and the
/// usage only gives a capped bonus. With hits of similar quality the app that
/// is used often moves up, but it does not beat a clearly better hit: "fi"
/// finds Firefox first, even when Affinity is used far more often.
/// viel oefter benutzt wird.
public struct AppRanker: Sendable {
    /// From this weight on an app counts as used. A single use falls below it
    /// after a good four half-lives (about a month).
    static let usedThreshold = 0.05
    /// The highest bonus for usage in the search. A hit at the start of the
    /// name brings 20 extra points, and the bonus deliberately stays below that.
    static let maxUsageBonus = 15.0

    private let matcher = FuzzyMatcher()

    public init() {}

    /// - Parameter pinned: the usage keys (bundle IDs) in a fixed order.
    ///   Without a search text these apps always stand at the very top, in
    ///   exactly this order. While searching they have no special role.
    public func rank(
        _ apps: [AppEntry],
        query: String,
        usage: UsageStats,
        pinned: [String] = [],
        now: Date = Date()
    ) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            // The first position wins when a key stands in there twice.
            var pinPosition: [String: Int] = [:]
            for (index, key) in pinned.enumerated() where pinPosition[key] == nil {
                pinPosition[key] = index
            }
            let top = apps
                .compactMap { app in pinPosition[app.usageKey].map { (app, $0) } }
                .sorted { $0.1 < $1.1 }
                .map(\.0)
            let rest = apps.filter { pinPosition[$0.usageKey] == nil }
            return top + rankByUsage(rest, usage: usage, now: now)
        }

        return apps
            .compactMap { app -> (AppEntry, Double)? in
                guard let fuzzy = matcher.score(trimmed, in: app.name) else { return nil }
                let bonus = Self.usageBonus(usage.weight(for: app.usageKey, at: now))
                return (app, Double(fuzzy) + bonus)
            }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : Self.alphabetical(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    /// Used apps by weight, the rest alphabetically.
    private func rankByUsage(_ apps: [AppEntry], usage: UsageStats, now: Date) -> [AppEntry] {
        apps
            .map { ($0, usage.weight(for: $0.usageKey, at: now)) }
            .sorted { lhs, rhs in
                let lhsUsed = lhs.1 >= Self.usedThreshold
                let rhsUsed = rhs.1 >= Self.usedThreshold
                if lhsUsed != rhsUsed { return lhsUsed }
                if lhsUsed && lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return Self.alphabetical(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    /// Grows logarithmically: the first uses count a lot, the hundredth hardly
    /// at all.
    static func usageBonus(_ weight: Double) -> Double {
        min(log2(1 + weight) * 6, maxUsageBonus)
    }

    private static func alphabetical(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
