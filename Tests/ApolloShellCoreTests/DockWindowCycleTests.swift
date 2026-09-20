import ApolloShellCore
import Testing

@Suite("The next window on a click")
struct DockWindowCycleTests {
    @Test("The app at the front with several windows: the one at the back comes forward")
    func cycles() {
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 3) == 2)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 2) == 1)
    }

    @Test("only one window or the app not at the front: an ordinary click")
    func noCycle() {
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 1) == nil)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: 0) == nil)
        #expect(DockWindowCycle.indexToRaise(isFrontmost: false, visibleWindows: 4) == nil)
    }

    @Test("A full round: every window comes forward once")
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
