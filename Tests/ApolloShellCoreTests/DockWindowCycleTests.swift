import ApolloShellCore
import Testing

@Suite("Naechstes Fenster per Klick")
struct DockWindowCycleTests {
    @Test("App vorne mit mehreren Fenstern: das hinterste kommt nach vorne")
    func cycles() {
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 3) == 2)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 2) == 1)
    }

    @Test("nur ein Fenster oder App nicht vorne: normaler Klick")
    func noCycle() {
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 1) == nil)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 0) == nil)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: false, visibleWindows: 4) == nil)
    }

    @Test("Durchlauf: jedes Fenster kommt einmal nach vorne")
    func fullRound() {
        var order = ["A", "B", "C"]
        var seenFront: [String] = []
        for _ in 0..<3 {
            let index = DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: order.count)!
            order.insert(order.remove(at: index), at: 0)
            seenFront.append(order[0])
        }
        #expect(Set(seenFront) == ["A", "B", "C"])
    }
}
