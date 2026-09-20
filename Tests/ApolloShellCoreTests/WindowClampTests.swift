import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Nudging windows in front of the left bar")
struct WindowClampTests {
    /// The MacBook screen in accessibility coordinates, the menu bar 30 pt.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let bar: CGFloat = 44

    func clamp(_ window: CGRect, minWidth: CGFloat = 0) -> CGRect? {
        WindowClamp.clampedFrame(window: window, screen: screen, reservedWidth: bar, minWidth: minWidth)
    }

    @Test("a window to the right of the bar stays as it is")
    func outsideIsUntouched() {
        #expect(clamp(CGRect(x: 200, y: 100, width: 800, height: 600)) == nil)
    }

    @Test("lying exactly against the bar there is nothing to do")
    func touchingIsUntouched() {
        #expect(clamp(CGRect(x: 44, y: 30, width: 1468, height: 952)) == nil)
    }

    @Test("rounding remainders below half a point are ignored")
    func toleranceIgnored() {
        #expect(clamp(CGRect(x: 43.6, y: 30, width: 500, height: 400)) == nil)
        #expect(clamp(CGRect(x: 43.4, y: 30, width: 500, height: 400)) != nil)
    }

    @Test("a filled window becomes narrower, the right edge stays")
    func filledWindowShrinks() {
        let filled = CGRect(x: 0, y: 30, width: 1512, height: 952)
        #expect(clamp(filled) == CGRect(x: 44, y: 30, width: 1468, height: 952))
    }

    @Test("a left tile does not grow into the right one")
    func leftTileKeepsRightEdge() {
        let leftHalf = CGRect(x: 0, y: 30, width: 756, height: 952)
        #expect(clamp(leftHalf) == CGRect(x: 44, y: 30, width: 712, height: 952))
    }

    @Test("a window dragged halfway under it is moved, the size stays")
    func draggedWindowMoves() {
        let dragged = CGRect(x: 10, y: 200, width: 600, height: 400)
        #expect(clamp(dragged) == CGRect(x: 44, y: 200, width: 600, height: 400))
    }

    @Test("a window hanging over the left edge comes fully into view")
    func hangingWindowMoves() {
        let hanging = CGRect(x: -200, y: 200, width: 600, height: 400)
        #expect(clamp(hanging) == CGRect(x: 44, y: 200, width: 600, height: 400))
    }

    @Test("while moving, not past the screen on the right")
    func moveStopsAtRightEdge() {
        let wide = CGRect(x: -20, y: 30, width: 1520, height: 900)
        #expect(clamp(wide) == CGRect(x: 44, y: 30, width: 1468, height: 900))
    }

    @Test("if it reached past on the right already, it may stay there")
    func alreadyBeyondRightEdgeKeepsIt() {
        let beyond = CGRect(x: -10, y: 30, width: 1622, height: 900) // bis 1612
        #expect(clamp(beyond) == CGRect(x: 44, y: 30, width: 1568, height: 900))
    }

    @Test("never narrower than the app allows, then only move it")
    func respectsMinimumWidth() {
        let filled = CGRect(x: 0, y: 30, width: 400, height: 500)
        #expect(clamp(filled, minWidth: 380) == CGRect(x: 44, y: 30, width: 380, height: 500))
        let dragged = CGRect(x: -200, y: 30, width: 1600, height: 500)
        #expect(clamp(dragged, minWidth: 1550) == CGRect(x: 44, y: 30, width: 1550, height: 500))
    }

    @Test("a tiny window fully inside the strip is only moved")
    func tinyWindowInsideStrip() {
        let tiny = CGRect(x: 0, y: 300, width: 30, height: 30)
        #expect(clamp(tiny) == CGRect(x: 44, y: 300, width: 30, height: 30))
    }

    @Test("a screen not at x = 0: the bar counts from its left edge")
    func offsetScreen() {
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let window = CGRect(x: 1512, y: 25, width: 1920, height: 1055)
        let result = WindowClamp.clampedFrame(window: window, screen: other, reservedWidth: bar)
        #expect(result == CGRect(x: 1556, y: 25, width: 1876, height: 1055))
    }

    @Test("without a bar or with an empty window do nothing")
    func degenerateInput() {
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 0, y: 0, width: 500, height: 500),
                                         screen: screen, reservedWidth: 0) == nil)
        #expect(clamp(CGRect(x: 0, y: 0, width: 0, height: 500)) == nil)
    }

    @Test("the screen with the largest share wins")
    func dominantScreen() {
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let screens = [screen, right]
        #expect(WindowClamp.dominantScreen(for: CGRect(x: 100, y: 100, width: 500, height: 500), among: screens) == 0)
        #expect(WindowClamp.dominantScreen(for: CGRect(x: 1400, y: 100, width: 500, height: 500), among: screens) == 1)
        #expect(WindowClamp.dominantScreen(for: CGRect(x: 1300, y: 100, width: 400, height: 500), among: screens) == 0)
        #expect(WindowClamp.dominantScreen(for: CGRect(x: -900, y: 100, width: 500, height: 500), among: screens) == nil)
    }

    @Test("a corner from a neighbouring screen on the left belongs to the neighbour")
    func leftNeighbourOwnsWindow() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let window = CGRect(x: -800, y: 100, width: 830, height: 500) // 30 pt auf dem Hauptbildschirm
        #expect(WindowClamp.dominantScreen(for: window, among: [screen, left]) == 1)
    }

    @Test("AppKit and accessibility: y mirrored, there and back identical")
    func flip() {
        let menuBarStrip = CGRect(x: 0, y: 952, width: 1512, height: 30) // AppKit, oben
        let ax = WindowClamp.flipped(menuBarStrip, primaryHeight: 982)
        #expect(ax == CGRect(x: 0, y: 0, width: 1512, height: 30))
        #expect(WindowClamp.flipped(ax, primaryHeight: 982) == menuBarStrip)
        // A screen below the main screen: a negative y in AppKit.
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(WindowClamp.flipped(below, primaryHeight: 982) == CGRect(x: 0, y: 982, width: 1920, height: 1080))
    }
}

@Suite("No loops while nudging")
struct ClampLedgerTests {
    let frame = CGRect(x: 44, y: 30, width: 800, height: 600)

    // #expect may call nothing that mutates, hence a constant first.

    @Test("an unknown window may be touched")
    func freshWindow() {
        var ledger = ClampLedger<Int>()
        let allowed = ledger.shouldClamp(1, current: frame, now: 0)
        #expect(allowed)
    }

    @Test("our own echo: when it still stands where it stood after the intervention, do nothing")
    func ignoresOwnEcho() {
        var ledger = ClampLedger<Int>()
        ledger.record(1, result: frame, now: 0)
        let same = ledger.shouldClamp(1, current: frame, now: 0.2)
        let rounded = ledger.shouldClamp(1, current: frame.offsetBy(dx: 0.3, dy: 0), now: 0.2)
        let movedAgain = ledger.shouldClamp(1, current: frame.offsetBy(dx: -30, dy: 0), now: 0.2)
        #expect(!same)
        #expect(!rounded)
        #expect(movedAgain)
    }

    @Test("when the app resists, quiet after three attempts until the deadline is up")
    func givesUpOnFightingApp() {
        var ledger = ClampLedger<Int>(maxAttempts: 3, period: 5)
        let snappedBack = CGRect(x: 0, y: 30, width: 800, height: 600)
        for t in 0..<3 {
            let allowed = ledger.shouldClamp(1, current: snappedBack, now: Double(t))
            #expect(allowed)
            ledger.record(1, result: frame, now: Double(t))
        }
        let fourth = ledger.shouldClamp(1, current: snappedBack, now: 3)
        let afterPeriod = ledger.shouldClamp(1, current: snappedBack, now: 7.5)
        #expect(!fourth)
        #expect(afterPeriod)
    }

    @Test("windows are independent of each other, and forgetting clears up")
    func perWindowAndForget() {
        var ledger = ClampLedger<Int>(maxAttempts: 1, period: 5)
        ledger.record(1, result: frame, now: 0)
        let other = ledger.shouldClamp(2, current: frame, now: 0)
        #expect(other)
        #expect(ledger.count == 1)
        ledger.forget(1)
        #expect(ledger.count == 0)
        let forgotten = ledger.shouldClamp(1, current: frame, now: 0)
        #expect(forgotten)
        ledger.record(10, result: frame, now: 0)
        ledger.record(11, result: frame, now: 0)
        ledger.forget(where: { $0 >= 10 })
        #expect(ledger.count == 0)
    }
}
