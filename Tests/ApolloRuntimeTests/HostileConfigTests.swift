import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Feindliche Config aus echter KDL (Review Focus 4)", .serialized)
struct HostileConfigTests {
    static let applyBudget = 50.0
    static let setBudget = 16.7
    static var factor: Double { EachBudgetTests.factor }

    static func source() -> String {
        var text = "var n 0\nvar rec-name \"rec\"\nvar big {\n"
        for index in 0..<50_000 {
            text += "    - \(index)\n"
        }
        text += "}\nvar outer {\n"
        for index in 0..<300 {
            text += "    - \(index)\n"
        }
        text += "}\nvar inner {\n"
        for index in 0..<300 {
            text += "    - \(index)\n"
        }
        text += "}\n"
        text += "define \"rec\" {\n    param \"level\" default=0\n    column {\n        text \"{level}\"\n        use \"{var.rec-name}\" level=\"{level + 1}\"\n    }\n}\n"
        text += "panel \"deep\" {\n" + String(repeating: "column {\n", count: 62) + "text \"deep\"\n" + String(repeating: "}\n", count: 62) + "}\n"
        text += "panel \"rec\" {\n    use \"{var.rec-name}\"\n}\n"
        text += "panel \"hostile\" {\n    text \"n {var.n}\"\n"
        text += "    column {\n        each item in=\"{var.big}\" { text \"{item}\" }\n    }\n"
        text += "    each a in=\"{var.outer}\" {\n        each b in=\"{var.inner}\" { text \"{a}-{b}\" }\n    }\n}\n"
        return text
    }

    @Test("Laden, Aufbau und erster Flush im Budget, Warnungen statt Absturz, danach set im nächsten Flush ≤ 16,7 ms")
    func hostileConfig() async throws {
        let source = Self.source()
        let started = Date()
        let result = await KDLLoad.load(source)
        let loadMilliseconds = Date().timeIntervalSince(started) * 1000
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(result.diagnostics.map(\.message))")
        let ir = try #require(result.ir)
        var applyCosts: [Double] = []
        var setCosts: [Double] = []
        var last: KDLShell?
        for _ in 0..<3 {
            let shell = KDLShell()
            var applyPart = 0.0
            var flushPart = 0.0
            applyCosts.append(CPUTime.measure {
                applyPart = CPUTime.measure { shell.runtime.applyLoaded(ConfigLoadResult(ir: ir, diagnostics: result.diagnostics, files: result.files), persisted: [:], screens: ["A"], shell: Record()) }
                flushPart = CPUTime.measure { shell.fixture.flush() }
            })
            print("hostile-config split apply ms=\(applyPart) flush ms=\(flushPart)")
            for value in 1...5 {
                #expect(shell.vars.set("n", .number(Double(value)), for: nil))
                setCosts.append(CPUTime.measure { shell.fixture.flush() })
            }
            last = shell
        }
        let shell = try #require(last)
        let applyCost = applyCosts.min()!
        let setCost = CPUTime.median(setCosts)
        print("hostile-config load ms=\(loadMilliseconds) apply+flush ms=\(applyCost) set ms=\(setCost) elements=\(shell.runtime.stats.elementsBuilt) debug=\(CPUTime.isDebug)")
        let root = shell.fixture.surface("hostile").root
        #expect(root.first?.arguments.first?.value == .string("n 5"))
        #expect(shell.runtime.stats.elementsBuilt <= RuntimeLimits.elementsPerSurface + 62 + 2 * (ConfigLimits.useDepth + 1))
        let messages = shell.fixture.warnings.map(\.message)
        #expect(messages.contains { $0.contains("at most") })
        #expect(messages.contains { $0.contains("runtime use nested deeper than \(ConfigLimits.useDepth)") })
        #expect(messages.contains { $0.contains("reached \(RuntimeLimits.elementsPerSurface) elements") })
        var depth = 0
        var cursor = shell.fixture.surface("deep").root.first
        while let element = cursor, element.kind == "column" {
            depth += 1
            cursor = element.children.first
        }
        #expect(depth == 62)
        #expect(cursor?.arguments.first?.value == .string("deep"))
        #expect(applyCost <= Self.applyBudget * Self.factor)
        #expect(setCost <= Self.setBudget * Self.factor)
    }
}
