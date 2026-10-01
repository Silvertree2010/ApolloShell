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

    @Test("Nach einem sync misst der Host nach dem Layout erneut, auch ohne Meldung des Hosting-Views")
    func remeasuresAfterLayout() throws {
        let fixture = try HostFixture("""
        panel "bar" { text "x" }
        """)
        var pending: [@MainActor () -> Void] = []
        fixture.host.afterLayout = { pending.append($0) }
        let window = try #require(fixture.window("bar"))
        fixture.host.controllers.values.forEach { $0.remeasurePending = false }
        fixture.host.resync()
        fixture.flush()
        #expect(!pending.isEmpty)
        window.fittingSize = CGSize(width: 406, height: 180)
        let scheduled = pending
        pending = []
        scheduled.forEach { $0() }
        fixture.flush()
        #expect(window.frame.size.width >= 406)
    }
}

@MainActor
@Suite("Fenstergrösse ohne Überhang-Rückkopplung")
struct InsetFeedbackTests {
    @Test("Die Messung des Hosting-Views enthält die Überhang-Ränder schon und wächst das Fenster nicht erneut")
    func noGrowth() throws {
        let fixture = try HostFixture("""
        popup "u" anchor="bottom-right" overhang=#true style="border-radius: 25px" { text "x" }
        """)
        let window = try #require(fixture.window("u"))
        for _ in 0..<3 {
            window.fittingSize = CGSize(width: 455, height: 451)
            window.onFittingChange?()
            fixture.flush()
        }
        #expect(window.frame.size == CGSize(width: 455, height: 451))
    }
}

@MainActor
@Suite("Inhalt an der verankerten Kante")
struct AnchorAlignmentTests {
    @Test("Eine links verankerte Oberfläche richtet ihren Inhalt links aus, damit er beim Wachsen für ein Flyout nicht springt")
    func alignment() {
        #expect(WindowHost.alignment(.left) == .leading)
        #expect(WindowHost.alignment(.right) == .trailing)
        #expect(WindowHost.alignment(.bottomRight) == .bottomTrailing)
        #expect(WindowHost.alignment(.center) == .center)
    }
}
