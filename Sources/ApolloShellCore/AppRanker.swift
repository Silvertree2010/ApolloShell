import Foundation

/// Sortiert die App-Liste.
///
/// Ohne Suchtext: benutzte Apps nach Nutzungsgewicht zuerst, der Rest
/// alphabetisch dahinter.
///
/// Mit Suchtext: die Trefferqualitaet der unscharfen Suche entscheidet, die
/// Nutzung gibt nur einen gedeckelten Bonus. Bei aehnlich guten Treffern
/// rutscht die oft benutzte App nach oben, einen klar besseren Treffer
/// schlaegt sie aber nicht: "fi" findet zuerst Firefox, auch wenn Affinity
/// viel oefter benutzt wird.
public struct AppRanker: Sendable {
    /// Ab diesem Gewicht gilt eine App als benutzt. Eine einzelne Nutzung
    /// faellt nach gut vier Halbwertszeiten (rund einem Monat) darunter.
    static let usedThreshold = 0.05
    /// Hoechstbonus fuer Nutzung bei der Suche. Ein Treffer am Namensanfang
    /// bringt 20 Extrapunkte, der Bonus bleibt bewusst darunter.
    static let maxUsageBonus = 15.0

    private let matcher = FuzzyMatcher()

    public init() {}

    /// - Parameter pinned: Nutzungsschluessel (Bundle-IDs) in fester
    ///   Reihenfolge. Ohne Suchtext stehen diese Apps immer ganz oben, genau
    ///   in dieser Reihenfolge. Beim Suchen haben sie keine Sonderrolle.
    public func rank(
        _ apps: [AppEntry],
        query: String,
        usage: UsageStats,
        pinned: [String] = [],
        now: Date = Date()
    ) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            // Erste Position gewinnt, falls ein Schluessel doppelt drinsteht.
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

    /// Benutzte Apps nach Gewicht, der Rest alphabetisch.
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

    /// Waechst logarithmisch: die ersten Nutzungen zaehlen viel, die
    /// hundertste kaum noch.
    static func usageBonus(_ weight: Double) -> Double {
        min(log2(1 + weight) * 6, maxUsageBonus)
    }

    private static func alphabetical(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
