import Testing
@testable import ApolloKDL

@Suite("Modul ApolloKDL")
struct KDLModuleTests {
    @Test("Modul ist gebaut")
    func moduleName() {
        #expect(KDLModule.name == "ApolloKDL")
    }
}
