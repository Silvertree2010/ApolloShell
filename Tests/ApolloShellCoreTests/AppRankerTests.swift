import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The order of the app list")
struct AppRankerTests {
    let ranker = AppRanker()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func app(_ name: String) -> AppEntry {
        AppEntry(name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: "id.\(name)")
    }

    private func usage(_ counts: [String: Int]) -> UsageStats {
        var stats = UsageStats()
        for (name, count) in counts {
            for _ in 0..<count { stats.record("id.\(name)", at: now) }
        }
        return stats
    }

    @Test("without a search text: used apps by weight first, the rest alphabetically")
    func emptyQueryUsageThenAlphabet() {
        let apps = ["Blender", "Discord", "Firefox", "Zed", "Affinity"].map(app)
        let stats = usage(["Zed": 5, "Discord": 2])
        let names = ranker.rank(apps, query: "", usage: stats, now: now).map(\.name)
        #expect(names == ["Zed", "Discord", "Affinity", "Blender", "Firefox"])
    }

    @Test("without usage it stays purely alphabetical")
    func emptyQueryNoUsageIsAlphabetical() {
        let apps = ["Zed", "Blender", "Affinity"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), now: now).map(\.name)
        #expect(names == ["Affinity", "Blender", "Zed"])
    }

    @Test("not used for a long time no longer counts as used")
    func oldUsageFallsBackToAlphabet() {
        let apps = ["Zed", "Affinity"].map(app)
        var stats = UsageStats()
        stats.record("id.Zed", at: now - 60 * 24 * 60 * 60) // 60 days ago
        let names = ranker.rank(apps, query: "", usage: stats, now: now).map(\.name)
        #expect(names == ["Affinity", "Zed"])
    }

    @Test("with hits of equal quality the used app wins")
    func usageBreaksTies() {
        let apps = ["Alpha Tool", "Beta Tool"].map(app)
        let stats = usage(["Beta Tool": 3])
        let names = ranker.rank(apps, query: "tool", usage: stats, now: now).map(\.name)
        #expect(names.first == "Beta Tool")
    }

    @Test("usage does not beat a clearly better hit")
    func usageDoesNotOverrideClearlyBetterMatch() {
        let apps = ["Affinity Designer", "Firefox"].map(app)
        let stats = usage(["Affinity Designer": 200])
        let names = ranker.rank(apps, query: "fi", usage: stats, now: now).map(\.name)
        #expect(names == ["Firefox", "Affinity Designer"])
    }

    @Test("the usage bonus is capped and grows with the usage")
    func usageBonusCappedAndMonotonic() {
        #expect(AppRanker.usageBonus(0) == 0)
        #expect(AppRanker.usageBonus(1) < AppRanker.usageBonus(5))
        #expect(AppRanker.usageBonus(10_000) == AppRanker.maxUsageBonus)
    }

    @Test("apps that do not match fall out even with a lot of usage")
    func nonMatchesStayOut() {
        let apps = ["Blender", "Firefox"].map(app)
        let stats = usage(["Blender": 50])
        let names = ranker.rank(apps, query: "fire", usage: stats, now: now).map(\.name)
        #expect(names == ["Firefox"])
    }
}
