import Testing
@testable import ApolloStyle

@Suite("Modul ApolloStyle")
struct StyleModuleTests {
    @Test("Modul ist gebaut")
    func moduleName() {
        #expect(StyleModule.name == "ApolloStyle")
    }
}
