import CoreGraphics
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Leiste rechts und Fensterwache aus")
struct BarSideTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func clamp(_ window: CGRect, minWidth: CGFloat = 0) -> CGRect? {
        WindowClamp.clampedFrame(window: window, screen: screen, reservedWidth: 44, side: .right, minWidth: minWidth)
    }

    @Test("Fenster links der rechten Leiste bleibt")
    func outsideIsUntouched() {
        #expect(clamp(CGRect(x: 200, y: 100, width: 800, height: 600)) == nil)
        #expect(clamp(CGRect(x: 0, y: 30, width: 1468, height: 952)) == nil)
    }

    @Test("gefuelltes Fenster wird schmaler, linke Kante bleibt")
    func filledWindowShrinks() {
        #expect(clamp(CGRect(x: 0, y: 30, width: 1512, height: 952)) == CGRect(x: 0, y: 30, width: 1468, height: 952))
    }

    @Test("rechte Kachel waechst nicht in die linke hinein")
    func rightTileKeepsLeftEdge() {
        #expect(clamp(CGRect(x: 756, y: 30, width: 756, height: 952)) == CGRect(x: 756, y: 30, width: 712, height: 952))
    }

    @Test("halb daruntergezogen: verschoben, Groesse bleibt")
    func draggedUnderIsMoved() {
        #expect(clamp(CGRect(x: 1000, y: 100, width: 500, height: 400)) == CGRect(x: 968, y: 100, width: 500, height: 400))
    }

    @Test("Bildschirm nicht bei x = 0")
    func offsetScreen() {
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let result = WindowClamp.clampedFrame(window: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                                              screen: other, reservedWidth: 44, side: .right)
        #expect(result == CGRect(x: 1512, y: 0, width: 1876, height: 1080))
    }

    @Test("Glas rechts ueber den Rand, ausser ein Nachbar steht dort")
    func bleed() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(SidebarBleed.edges(screen: main, others: [main], side: .right).left == SidebarBleed.depth)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        #expect(SidebarBleed.edges(screen: main, others: [main, right], side: .right).left == 0)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(SidebarBleed.edges(screen: main, others: [main, left], side: .right).left == SidebarBleed.depth)
    }

    @Test("alte Datei: links, Fensterwache an; neue Werte bleiben erhalten")
    func settingsRoundTrip() throws {
        let old = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{"screens":{"mode":"all"}}"#.utf8))
        #expect(old.side == .left)
        #expect(old.keepWindowsClear)
        var bar = ShellSettings.Bar()
        bar.side = .right
        bar.keepWindowsClear = false
        let back = try JSONDecoder().decode(ShellSettings.Bar.self, from: JSONEncoder().encode(bar))
        #expect(back == bar)
    }

    @Test("unbekannte Seite faellt auf links zurueck")
    func unknownSide() throws {
        let bar = try JSONDecoder().decode(ShellSettings.Bar.self, from: Data(#"{"side":"top"}"#.utf8))
        #expect(bar.side == .left)
    }
}
