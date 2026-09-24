import Testing
import Foundation

@MainActor
@Suite("Test-Hilfen treiben die Runloop auch ohne Quellen")
struct RunLoopPumpTests {
    @Test("RunLoopPump wartet die volle Zeit, eine leere Runloop allein kehrt sofort zurück")
    func waits() {
        let start = Date()
        RunLoopPump.run(0.03)
        #expect(Date().timeIntervalSince(start) >= 0.025)
    }
}
