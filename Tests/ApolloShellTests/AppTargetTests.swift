import Testing
@testable import ApolloShell
import ApolloBase

@Suite("App-Target")
struct AppTargetTests {
    @Test("die App meldet die Version aus ApolloBase")
    func banner() {
        #expect(AppBanner.text == "ApolloShell \(ShellVersion.current)")
    }
}
