import Testing
@testable import ApolloRuntime

@Suite("Modul ApolloRuntime")
struct RuntimeModuleTests {
    @Test("Modul ist gebaut")
    func moduleName() {
        #expect(RuntimeModule.name == "ApolloRuntime")
    }
}
