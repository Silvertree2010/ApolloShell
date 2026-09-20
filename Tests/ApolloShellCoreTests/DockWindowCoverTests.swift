import ApolloShellCore
import Testing

@Suite("A covered window on a click on the app that is at the front already")
struct DockWindowCoverTests {
    private static func window(
        _ id: Int, _ owner: DockScreenWindow.Owner, layer: Int = 0,
        _ x: Double, _ y: Double, _ width: Double, _ height: Double
    ) -> DockScreenWindow {
        DockScreenWindow(id: id, owner: owner, layer: layer, x: x, y: y, width: width, height: height)
    }

    @Test("Only one window: nothing covers it")
    func onlyOneWindow() {
        let windows = [Self.window(1, .target, 0, 0, 500, 400)]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Two windows side by side, no overlap: nothing pages")
    func sideBySideNoOverlap() {
        let windows = [
            Self.window(1, .other, 0, 0, 500, 400),
            Self.window(2, .target, 500, 0, 500, 400),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Fully covered: the covered one comes forward")
    func fullyCovered() {
        let windows = [
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("Partly covered, but below the threshold: nothing pages")
    func partiallyCoveredBelowThreshold() {
        // 5 % of the area lies under the other window.
        let windows = [
            Self.window(1, .other, 0, 0, 100, 30),
            Self.window(2, .target, 0, 0, 100, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Partly covered, above the threshold: it counts as covered")
    func partiallyCoveredAboveThreshold() {
        // 20 % of the area lies under the other window.
        let windows = [
            Self.window(1, .other, 0, 0, 100, 120),
            Self.window(2, .target, 0, 0, 100, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("Several covered ones in a row: the frontmost comes first")
    func multipleCoveredInARow() {
        let windows = [
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
            Self.window(3, .target, 300, 300, 200, 200),
        ]
        // Both target windows lie under window 1 - the front target window
        // (2) is nearer the top of the list and comes first.
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("After bringing one forward another one is next")
    func nextClickPicksTheNextOne() {
        // As in the real flow: after raising 2 the list stands anew -
        // 2 is at the front now, 3 still lies under 1.
        let windows = [
            Self.window(2, .target, 100, 100, 200, 200),
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(3, .target, 300, 300, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 3)
    }

    @Test("A foreign window outside level 0 covers nothing (the menu bar, the Dock)")
    func nonZeroLayerDoesNotCover() {
        let windows = [
            Self.window(1, .other, layer: 25, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Our own bar and panels never cover")
    func ownShellNeverCovers() {
        let windows = [
            Self.window(1, .ownShell, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Only a foreign window behind it (which covers nothing, because it is behind the target window)")
    func otherWindowBehindTargetDoesNotCover() {
        let windows = [
            Self.window(2, .target, 0, 0, 200, 200),
            Self.window(1, .other, 0, 0, 800, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }
}
