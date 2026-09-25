import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Fenster folgt der Inhaltsgrösse")
struct ContentFitTests {
    @Test("Wächst der Inhalt eines toast, wächst das Fenster mit")
    func toastGrowsWithContent() throws {
        let fixture = try HostFixture("""
        toast "default" { text "x" }
        """)
        let window = try #require(fixture.window("default"))
        window.fittingSize = CGSize(width: 16, height: 16)
        window.onFittingChange?()
        fixture.flush()
        let small = window.frame.size
        window.fittingSize = CGSize(width: 406, height: 180)
        window.onFittingChange?()
        fixture.flush()
        #expect(window.frame.size.height > small.height)
        #expect(window.frame.size.width >= 406)
    }
}
