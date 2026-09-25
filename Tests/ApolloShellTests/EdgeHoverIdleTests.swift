import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Kante im Leerlauf ohne Takt")
struct EdgeHoverIdleTests {
    @Test("Zu: nur der Mausmonitor, kein Timer; offen: Timer; wieder zu: Timer weg")
    func pollsOnlyWhileOpen() {
        let edge = EdgeHoverController()
        var open = false
        var point = CGPoint(x: 500, y: 500)
        var timers = 0
        var monitors = 0
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        edge.targets = {
            [EdgeHoverController.Target(key: "d@A", surfaceID: "d", screenKey: "A", anchor: .top, frame: CGRect(x: 300, y: 500, width: 800, height: 400), screen: screen, margin: 20, gap: 0, isOpen: open)]
        }
        edge.pointer = { point }
        edge.open = { _, _ in open = true }
        edge.close = { _ in open = false }
        edge.makeTimer = { _, _ in timers += 1; return nil }
        edge.makeMonitor = { _ in monitors += 1; return "m" }
        edge.removeMonitor = { _ in }
        edge.refresh()
        #expect(monitors == 1)
        #expect(timers == 0)
        #expect(!edge.polling)
        point = CGPoint(x: 700, y: 900)
        edge.tick()
        #expect(open)
        #expect(edge.polling)
        #expect(timers == 1)
        point = CGPoint(x: 700, y: 100)
        edge.tick()
        #expect(!open)
        #expect(!edge.polling)
    }
}
