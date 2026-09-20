import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Usage statistics with decay")
struct UsageStatsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let week = UsageStats.defaultHalfLife

    @Test("never used means weight 0")
    func unknownIsZero() {
        #expect(UsageStats().weight(for: "com.example.app", at: t0) == 0)
    }

    @Test("every use counts one point")
    func recordAddsOne() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("a", at: t0)
        #expect(stats.weight(for: "a", at: t0) == 2)
    }

    @Test("after one half-life the weight is halved")
    func decaysByHalf() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        #expect(abs(stats.weight(for: "a", at: t0 + week) - 0.5) < 1e-9)
        #expect(abs(stats.weight(for: "a", at: t0 + 2 * week) - 0.25) < 1e-9)
    }

    @Test("a new use builds on top of the decayed value")
    func recordOnTopOfDecayed() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("a", at: t0 + week)
        #expect(abs(stats.weight(for: "a", at: t0 + week) - 1.5) < 1e-9)
    }

    @Test("recently often beats long-ago very often")
    func recentBeatsOld() {
        var stats = UsageStats()
        for _ in 0..<20 { stats.record("old", at: t0) }
        for _ in 0..<10 { stats.record("new", at: t0 + 4 * week) }
        let now = t0 + 4 * week
        #expect(stats.weight(for: "new", at: now) > stats.weight(for: "old", at: now))
    }

    @Test("survives saving and loading as JSON")
    func codableRoundTrip() throws {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("b", at: t0 + 100)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(UsageStats.self, from: data)
        #expect(decoded == stats)
    }
}
