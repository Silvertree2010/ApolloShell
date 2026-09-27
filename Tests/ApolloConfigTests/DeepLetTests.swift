import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Tief verschachtelte let-Werte")
struct DeepLetTests {
    final class Box: @unchecked Sendable {
        var result: ConfigLoadResult?
    }

    static func nestedLets(_ count: Int) -> String {
        var lines = ["let v0=1"]
        for index in 1..<count {
            lines.append("let v\(index)=\"{[v\(index - 1)]}\"")
        }
        return lines.joined(separator: "\n")
    }

    @Test("20 000 let, die jeweils das vorige einpacken, laden auf kleinem Stapel ohne Stapelüberlauf")
    func twentyThousandNestedLets() {
        let source = Self.nestedLets(20_000) + "\npanel \"p\" anchor=\"left\" {\n  text \"{v19999}\"\n}"
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.result = LoaderHarness.load(["/config/shell.kdl": source])
            box.result = nil
            semaphore.signal()
        }
        thread.stackSize = 512 << 10
        thread.start()
        semaphore.wait()
        #expect(box.result == nil)
    }

    @Test("Ein let tiefer als 64 Ebenen ist ein Fehler, 64 Ebenen bleiben erlaubt")
    func depthLimit() {
        let allowed = LetStageTests.run(Self.nestedLets(65))
        #expect(allowed.diagnostics.isEmpty)
        #expect(allowed.values["v64"] != nil)
        let refused = LetStageTests.run(Self.nestedLets(66))
        #expect(refused.diagnostics.map(\.message) == ["'let' 'v65' is nested deeper than 64 levels"])
        #expect(refused.values["v65"] == nil)
    }
}
