import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nutzungsstatistik mit Zerfall")
struct UsageStatsTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let week = UsageStats.defaultHalfLife

    @Test("nie benutzt heisst Gewicht 0")
    func unknownIsZero() {
        #expect(UsageStats().weight(for: "com.example.app", at: t0) == 0)
    }

    @Test("jede Nutzung zaehlt einen Punkt")
    func recordAddsOne() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("a", at: t0)
        #expect(stats.weight(for: "a", at: t0) == 2)
    }

    @Test("nach einer Halbwertszeit ist das Gewicht halbiert")
    func decaysByHalf() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        #expect(abs(stats.weight(for: "a", at: t0 + week) - 0.5) < 1e-9)
        #expect(abs(stats.weight(for: "a", at: t0 + 2 * week) - 0.25) < 1e-9)
    }

    @Test("neue Nutzung setzt auf dem abgeklungenen Stand auf")
    func recordOnTopOfDecayed() {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("a", at: t0 + week)
        #expect(abs(stats.weight(for: "a", at: t0 + week) - 1.5) < 1e-9)
    }

    @Test("kuerzlich oft schlaegt frueher sehr oft")
    func recentBeatsOld() {
        var stats = UsageStats()
        for _ in 0..<20 { stats.record("alt", at: t0) }
        for _ in 0..<10 { stats.record("neu", at: t0 + 4 * week) }
        let now = t0 + 4 * week
        #expect(stats.weight(for: "neu", at: now) > stats.weight(for: "alt", at: now))
    }

    @Test("ueberlebt Speichern und Laden als JSON")
    func codableRoundTrip() throws {
        var stats = UsageStats()
        stats.record("a", at: t0)
        stats.record("b", at: t0 + 100)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(UsageStats.self, from: data)
        #expect(decoded == stats)
    }
}
