import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Reload Budget", .serialized)
struct ReloadBudgetTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    static let budget = 80.0
    static let debugFactor: Double = 4
    static var factor: Double { (CPUTime.isDebug ? debugFactor : 1) * CPUTime.machineFactor }
    static let kinds = ["panel", "panel", "popup", "overlay", "popup"]

    struct Synthetic {
        var surfaces: [SurfaceIR] = []
        var vars: [VarDecl] = []
        var nodes = 0
        var expressions = 0
    }

    static func synthetic(shift: Int = 0) -> Synthetic {
        var result = Synthetic()
        for index in 0..<40 {
            result.vars.append(IR.plainVar("v\(index)", .number, .number(Double(index))))
        }
        result.vars.append(IR.plainVar("items", .list, .list([.string("a"), .string("b"), .string("c")])))
        for (surfaceIndex, kind) in kinds.enumerated() {
            var rows: [ChildIR] = []
            var line = surfaceIndex * 1_000 + shift
            for row in 0..<29 {
                var cells: [ChildIR] = []
                for column in 0..<9 {
                    line += 1
                    let key = String(column)
                    if column < 6 {
                        let name = "v\((row * 9 + column) % 40)"
                        let text = column % 3 == 0 ? "{var.\(name) * 2}" : column % 3 == 1 ? "{var.\(name) | round}" : "{self.hover ? var.\(name) : 0}"
                        cells.append(T.text(key, IR.value(text, line: line), properties: ["class": IR.string("cell", line: line)], line: line))
                        result.expressions += 1
                    } else {
                        cells.append(T.text(key, IR.string("static \(column)", line: line), line: line))
                    }
                    result.nodes += 1
                }
                line += 1
                let properties: [String: CompiledValue] = row % 5 == 0 ? ["id": IR.string("row-\(row)", line: line)] : [:]
                rows.append(T.box(row % 5 == 0 ? "row-\(row)" : String(row), properties: properties, children: cells, line: line))
                result.nodes += 1
            }
            line += 1
            rows.append(.each(EachIR(key: "29", variable: "item", list: IR.value("{var.items}", line: line), body: [
                T.text("0", IR.value("{item}", locals: ["item"], line: line + 1), line: line + 1),
            ])))
            result.nodes += 2
            result.expressions += 2
            line += 2
            let properties: [String: CompiledValue] = ["height": IR.value("{var.v1 + 30}", line: line)]
            result.expressions += 1
            result.surfaces.append(T.surface(kind, "s\(surfaceIndex)", properties: properties, children: rows))
            result.nodes += 1
        }
        return result
    }

    func reloadCost(shift: Int, runs: Int) -> (cpu: Double, wall: Double, fixture: ShellFixture) {
        let fixture = ShellFixture()
        let base = Self.synthetic()
        fixture.apply(base.surfaces, vars: base.vars, screens: ["A", "B"])
        fixture.flush()
        var cpu: [Double] = []
        var wall: [Double] = []
        for run in 0..<runs {
            let next = Self.synthetic(shift: run % 2 == 0 ? shift : 0)
            let clock = ContinuousClock()
            let start = clock.now
            cpu.append(CPUTime.measure { fixture.apply(next.surfaces, vars: next.vars, screens: ["A", "B"]) })
            let elapsed = clock.now - start
            wall.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1_000)
            fixture.flush()
        }
        return (CPUTime.median(cpu), CPUTime.median(wall), fixture)
    }

    @Test("Synthetische IR in Grösse der Default-Config: Reload ohne Änderung und mit verschobenen Zeilen im Budget, 0 Auswertungen, 0 gebaut")
    func reloadBudget() {
        let size = Self.synthetic()
        #expect(size.nodes >= 1_450 && size.nodes <= 1_550)
        #expect(size.expressions >= 800)
        let probe = ShellFixture()
        probe.apply(size.surfaces, vars: size.vars, screens: ["A", "B"])
        probe.flush()
        let before = [probe.runtime.stats.bindingsEvaluated, probe.runtime.stats.elementsBuilt, probe.runtime.stats.surfacesBuilt]
        #expect(before[2] == 10)
        let shifted = Self.synthetic(shift: 1)
        probe.host.events.removeAll()
        probe.apply(shifted.surfaces, vars: shifted.vars, screens: ["A", "B"])
        probe.flush()
        #expect([probe.runtime.stats.bindingsEvaluated, probe.runtime.stats.elementsBuilt, probe.runtime.stats.surfacesBuilt] == before)
        #expect(probe.host.events == [])

        let same = reloadCost(shift: 0, runs: 20)
        let moved = reloadCost(shift: 1, runs: 20)
        print("reload-budget nodes=\(size.nodes) expressions=\(size.expressions) same-cpu=\(same.cpu) same-wall=\(same.wall) shifted-cpu=\(moved.cpu) shifted-wall=\(moved.wall) debug=\(CPUTime.isDebug)")
        #expect(same.cpu <= Self.budget * Self.factor)
        #expect(moved.cpu <= Self.budget * Self.factor)
    }
}
