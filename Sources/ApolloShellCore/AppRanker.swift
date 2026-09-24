import Foundation

public struct AppRanker: Sendable {
    static let usedThreshold = 0.05
    static let maxUsageBonus = 15.0

    private let matcher = FuzzyMatcher()

    public init() {}

    public func rank(
        _ apps: [AppEntry],
        query: String,
        usage: UsageStats,
        pinned: [String] = [],
        now: Date = Date()
    ) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
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

    static func usageBonus(_ weight: Double) -> Double {
        min(log2(1 + weight) * 6, maxUsageBonus)
    }

    private static func alphabetical(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
