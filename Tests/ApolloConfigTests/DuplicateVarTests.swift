import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Doppelte var")
struct DuplicateVarTests {
    @Test("zweites var gleichen Namens ist ein Fehler, das erste gilt")
    func duplicate() {
        let result = VarStageTests.run("var hello \"a\"\nvar hello 1")
        #expect(result.declarations.count == 1)
        #expect(result.declarations.first?.type == .string)
        #expect(result.diagnostics.map(\.code) == [.duplicateDefinition])
        #expect(result.diagnostics.first?.notes.count == 1)
    }
}
