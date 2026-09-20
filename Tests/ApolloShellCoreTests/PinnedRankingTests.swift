import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Pinned apps")
struct PinnedRankingTests {
    let ranker = AppRanker()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func app(_ name: String) -> AppEntry {
        AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: "id.\(name)")
    }

    @Test("without search text, pins are on top, in exactly their order")
    func pinnedFirstInGivenOrder() {
        let apps = ["Affinity", "Blender", "Terminal", "Vivaldi", "Zed"].map(app)
        var stats = UsageStats()
        for _ in 0..<50 { stats.record("id.Terminal", at: now) }
        let names = ranker.rank(apps, query: "", usage: stats, pinned: ["id.Zed", "id.Affinity"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Affinity", "Terminal", "Blender", "Vivaldi"])
    }

    @Test("Pins that no longer exist are skipped")
    func missingPinsAreIgnored() {
        let apps = ["Blender", "Zed"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), pinned: ["id.DoesNotExist", "id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Blender"])
    }

    @Test("a duplicate pin appears only once, in the first position")
    func duplicatePinsOnce() {
        let apps = ["Blender", "Zed"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), pinned: ["id.Zed", "id.Blender", "id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Zed", "Blender"])
    }

    @Test("pins have no special role while searching")
    func pinsIgnoredWhileSearching() {
        let apps = ["Firefox", "Zed"].map(app)
        let names = ranker.rank(apps, query: "fire", usage: UsageStats(), pinned: ["id.Zed"], now: now)
            .map(\.name)
        #expect(names == ["Firefox"])
    }
}
