import Testing
@testable import ApolloConfig

@Suite("Modul ApolloConfig")
struct ConfigModuleTests {
    @Test("Modul ist gebaut")
    func moduleName() {
        #expect(ConfigModule.name == "ApolloConfig")
    }
}
