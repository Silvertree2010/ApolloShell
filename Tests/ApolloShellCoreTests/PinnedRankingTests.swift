import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Angeheftete Apps")
struct PinnedRankingTests {
    let ranker = AppRanker()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func app(_ name: String) -> AppEntry {
        AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: "id.\(name)")
    }

    @Test("ohne Suchtext stehen Pins oben, genau in ihrer Reihenfolge")
    func pinnedFirstInGivenOrder() {
        let apps = ["Affinity", "Blender", "Terminal", "Vivaldi", "Zed"].map(app)
        var stats = UsageStats()
        for _ in 0..<50 { stats.record("id.Terminal", at: now) }
        let names = ranker.rank(apps, query: "", usage: stats, pinned: ["id.Zed", "id.Affinity"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Affinity", "Terminal", "Blender", "Vivaldi"])
    }

    @Test("Pins, die es nicht (mehr) gibt, werden uebersprungen")
    func missingPinsAreIgnored() {
        let apps = ["Blender", "Zed"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), pinned: ["id.Gibtsnicht", "id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Blender"])
    }

    @Test("doppelter Pin erscheint nur einmal, an der ersten Stelle")
    func duplicatePinsOnce() {
        let apps = ["Blender", "Zed"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), pinned: ["id.Zed", "id.Blender", "id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Blender"])
    }

    @Test("beim Suchen haben Pins keine Sonderrolle")
    func pinsIgnoredWhileSearching() {
        let apps = ["Firefox", "Zed"].map(app)
        let names = ranker.rank(apps, query: "fire", usage: UsageStats(), pinned: ["id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Firefox"])
    }
}
