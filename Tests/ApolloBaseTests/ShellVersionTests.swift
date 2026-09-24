import Testing
@testable import ApolloBase

@Suite("Version der Shell")
struct ShellVersionTests {
    @Test("0.2.0 ist die Version dieses Branches")
    func currentVersion() {
        #expect(ShellVersion.current == "0.2.0")
    }
}
