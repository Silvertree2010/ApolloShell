import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("each Budget (Review Focus 4)", .serialized)
struct EachBudgetTests {
    typealias F = EachFixture

    static let debugFactor: Double = 4
    static var factor: Double { CPUTime.isDebug ? debugFactor : 1 }
    static let firstBuildBudget = 50.0
    static let changeBudget = 5.0
    static let hostile = 50_000

    static func hostileItems(prefix: String = "") -> [Value] {
        (0..<hostile).map { F.item("\(prefix)e\($0)") }
    }

    func firstBuild() -> (EachFixture, Double) {
        let fixture = F(items: [])
        let items = Self.hostileItems()
        fixture.shell.store.set(DependencyPath("data", ["items"]), .list(items))
        let cost = CPUTime.measure { fixture.shell.flush() }
        return (fixture, cost)
    }

    func changeCost(_ fixture: EachFixture, runs: Int, _ change: (Int, [Value]) -> [Value]) -> Double {
        var items = Self.hostileItems()
        var samples: [Double] = []
        for run in 0..<runs {
            items = change(run, items)
            fixture.shell.store.set(DependencyPath("data", ["items"]), .list(items))
            samples.append(CPUTime.measure { fixture.shell.flush() })
        }
        return CPUTime.median(samples)
    }

    @Test("50 000 Einträge: genau 5 000 gebaut, eine Warnung, erster Aufbau im Budget")
    func hostileFirstBuild() {
        var costs: [Double] = []
        for _ in 0..<3 {
            let (fixture, cost) = firstBuild()
            costs.append(cost)
            #expect(fixture.shell.runtime.stats.elementsBuilt == RuntimeLimits.eachEntries)
            #expect(fixture.entries.count == RuntimeLimits.eachEntries)
            #expect(fixture.shell.warnings.filter { $0.message.contains("at most") }.count == 1)
        }
        let best = costs.min()!
        print("each-budget first-build ms=\(best) debug=\(CPUTime.isDebug)")
        #expect(best <= Self.firstBuildBudget * Self.factor)
    }

    @Test("50 000 Einträge: Einfügen vorn, Verschieben, Entfernen im Budget (Median aus 20)")
    func hostileChanges() {
        let (insertFixture, _) = firstBuild()
        let insert = changeCost(insertFixture, runs: 20) { run, items in [F.item("new\(run)")] + items }
        let (moveFixture, _) = firstBuild()
        let move = changeCost(moveFixture, runs: 20) { _, items in
            var moved = items
            moved.insert(moved.remove(at: 4_000), at: 0)
            return moved
        }
        let (removeFixture, _) = firstBuild()
        let remove = changeCost(removeFixture, runs: 20) { _, items in Array(items.dropFirst()) }
        print("each-budget insert ms=\(insert) move ms=\(move) remove ms=\(remove) debug=\(CPUTime.isDebug)")
        #expect(insert <= Self.changeBudget * Self.factor)
        #expect(move <= Self.changeBudget * Self.factor)
        #expect(remove <= Self.changeBudget * Self.factor)
        #expect(insertFixture.entries.count == RuntimeLimits.eachEntries)
        #expect(insertFixture.shell.runtime.stats.elementsBuilt == RuntimeLimits.eachEntries + 20)
    }

    @Test("Selbstbeweis: lineare Suche statt Dictionary reisst das Budget beim Einfügen vorn")
    func linearLookupBreaksBudget() {
        let (fixture, _) = firstBuild()
        fixture.shell.runtime.eachKeyLookup = .linear
        let insert = changeCost(fixture, runs: 3) { run, items in [F.item("new\(run)")] + items }
        print("each-budget linear insert ms=\(insert) debug=\(CPUTime.isDebug)")
        #expect(insert > Self.changeBudget * Self.factor)
        #expect(fixture.entries.count == RuntimeLimits.eachEntries)
    }
}
