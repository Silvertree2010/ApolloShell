import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Sortierung der App-Liste")
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

    @Test("ohne Suchtext: benutzte Apps nach Gewicht zuerst, Rest alphabetisch")
    func emptyQueryUsageThenAlphabet() {
        let apps = ["Blender", "Discord", "Firefox", "Zed", "Affinity"].map(app)
        let stats = usage(["Zed": 5, "Discord": 2])
        let names = ranker.rank(apps, query: "", usage: stats, now: now).map(\.name)
        #expect(names == ["Zed", "Discord", "Affinity", "Blender", "Firefox"])
    }

    @Test("ohne Nutzung bleibt es rein alphabetisch")
    func emptyQueryNoUsageIsAlphabetical() {
        let apps = ["Zed", "Blender", "Affinity"].map(app)
        let names = ranker.rank(apps, query: "", usage: UsageStats(), now: now).map(\.name)
        #expect(names == ["Affinity", "Blender", "Zed"])
    }

    @Test("lange nicht benutzt zaehlt nicht mehr als benutzt")
    func oldUsageFallsBackToAlphabet() {
        let apps = ["Zed", "Affinity"].map(app)
        var stats = UsageStats()
        stats.record("id.Zed", at: now - 60 * 24 * 60 * 60) // vor 60 Tagen
        let names = ranker.rank(apps, query: "", usage: stats, now: now).map(\.name)
        #expect(names == ["Affinity", "Zed"])
    }

    @Test("bei gleich guten Treffern gewinnt die benutzte App")
    func usageBreaksTies() {
        let apps = ["Alpha Tool", "Beta Tool"].map(app)
        let stats = usage(["Beta Tool": 3])
        let names = ranker.rank(apps, query: "tool", usage: stats, now: now).map(\.name)
        #expect(names.first == "Beta Tool")
    }

    @Test("Nutzung schlaegt keinen klar besseren Treffer")
    func usageDoesNotOverrideClearlyBetterMatch() {
        let apps = ["Affinity Designer", "Firefox"].map(app)
        let stats = usage(["Affinity Designer": 200])
        let names = ranker.rank(apps, query: "fi", usage: stats, now: now).map(\.name)
        #expect(names == ["Firefox", "Affinity Designer"])
    }

    @Test("Nutzungsbonus ist gedeckelt und steigt mit der Nutzung")
    func usageBonusCappedAndMonotonic() {
        #expect(AppRanker.usageBonus(0) == 0)
        #expect(AppRanker.usageBonus(1) < AppRanker.usageBonus(5))
        #expect(AppRanker.usageBonus(10_000) == AppRanker.maxUsageBonus)
    }

    @Test("nicht passende Apps fallen auch mit viel Nutzung raus")
    func nonMatchesStayOut() {
        let apps = ["Blender", "Firefox"].map(app)
        let stats = usage(["Blender": 50])
        let names = ranker.rank(apps, query: "fire", usage: stats, now: now).map(\.name)
        #expect(names == ["Firefox"])
    }
}
