import Testing
import ApolloConfig
@testable import ApolloRuntime

@Suite("LocalScope")
struct LocalScopeTests {
    @Test("adding überdeckt ältere Namen, ohne den Ausgangs-Scope zu ändern", arguments: [1, 7, 8, 9, 20])
    func shadowing(layers: Int) {
        let base = LocalScope(["a": .number(0), "b": .string("b")])
        var scope = base
        for index in 1...layers {
            scope = scope.adding("a", .number(Double(index)))
            scope = scope.adding("n\(index % 3)", .number(Double(index)))
        }
        #expect(scope["a"] == .number(Double(layers)))
        #expect(scope["b"] == .string("b"))
        #expect(scope["n\(layers % 3)"] == .number(Double(layers)))
        #expect(scope["missing"] == nil)
        #expect(base["a"] == .number(0))
        #expect(base["n1"] == nil)
    }

    @Test("gleicher Inhalt ist gleich und hasht gleich, egal wie er entstanden ist", arguments: [2, 12])
    func equality(layers: Int) {
        var built = LocalScope(["x": .number(1)])
        var expected: [String: Value] = ["x": .number(1)]
        for index in 0..<layers {
            built = built.adding("k\(index % 4)", .number(Double(index)))
            expected["k\(index % 4)"] = .number(Double(index))
        }
        let direct = LocalScope(expected)
        #expect(built == direct)
        #expect(built.hashValue == direct.hashValue)
        #expect(Set([built, direct]).count == 1)
        #expect(built != direct.adding("k0", .string("other")))
        #expect(built.adding("x", .number(2)) != direct)
    }
}
