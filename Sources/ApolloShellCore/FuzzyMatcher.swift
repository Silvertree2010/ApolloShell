import Foundation

/// Fuzzy search: the letters of the input must occur in this order in the
/// name, but not necessarily right after each other.
/// "illu" finds "Adobe Illustrator 2026", "ff" finds "Firefox".
///
/// Scoring: hits at the start of the name and at word starts count more,
/// as do consecutive hits. Case and accents don't matter.
public struct FuzzyMatcher: Sendable {
    public init() {}

    /// `nil` if the name doesn't match. Higher is better.
    public func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(Self.normalize(query).filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let normalized = Self.normalize(candidate)
        let c = Array(normalized)

        var score = 0
        var qi = 0
        var previousMatch = -2
        for (ci, ch) in c.enumerated() where qi < q.count {
            guard ch == q[qi] else { continue }
            var points = 1
            if ci == 0 {
                points += 8
            } else if Self.isBoundary(c[ci - 1]) {
                points += 5
            }
            if ci == previousMatch + 1 { points += 3 }
            score += points
            previousMatch = ci
            qi += 1
        }
        guard qi == q.count else { return nil }

        let plainQuery = String(q)
        if normalized.hasPrefix(plainQuery) {
            score += 20
        } else if normalized.contains(plainQuery) {
            score += 10
        }
        return score
    }

    /// Filters and sorts. An empty input leaves the order as-is.
    /// Ties are broken alphabetically by name.
    public func rank<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items
            .compactMap { item in score(query, in: name(item)).map { (item, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return name(lhs.0).localizedStandardCompare(name(rhs.0)) == .orderedAscending
            }
            .map(\.0)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isBoundary(_ ch: Character) -> Bool {
        ch == " " || ch == "-" || ch == "_" || ch == "." || ch == "("
    }
}
