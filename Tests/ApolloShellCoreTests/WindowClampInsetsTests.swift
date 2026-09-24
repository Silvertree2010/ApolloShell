import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Nudging windows in front of the menu bar and the sidebar")
struct WindowClampInsetsTests {
    /// The MacBook screen in accessibility coordinates, the menu bar 30 pt.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let bar: CGFloat = 44

    @Test(
        "a bar-flush window shrinks, the opposite edge stays",
        arguments: [
            // (window, insets, expected)
            (
                CGRect(x: 0, y: 30, width: 1512, height: 952),
                ReservedInsets(left: 44),
                CGRect(x: 44, y: 30, width: 1468, height: 952)
            ),
            (
                CGRect(x: 0, y: 30, width: 1512, height: 952),
                ReservedInsets(top: 44),
                CGRect(x: 0, y: 44, width: 1512, height: 938)
            ),
        ] as [(CGRect, ReservedInsets, CGRect)]
    )
    func flushShrinksKeepingOppositeEdge(window: CGRect, insets: ReservedInsets, expected: CGRect) {
        #expect(WindowClamp.clampedFrame(window: window, screen: screen, insets: insets) == expected)
    }

    @Test("top bar: a window filled top to bottom becomes shorter, the bottom edge stays")
    func topBarShrinksFilledWindow() {
        let filled = CGRect(x: 100, y: 0, width: 800, height: 982)
        let expected = CGRect(x: 100, y: 44, width: 800, height: 938)
        #expect(WindowClamp.clampedFrame(window: filled, screen: screen, insets: ReservedInsets(top: bar)) == expected)
    }

    @Test("top bar: a window dragged under it is moved down, the size stays")
    func topBarMovesDraggedWindow() {
        let dragged = CGRect(x: 100, y: -10, width: 600, height: 400)
        let expected = CGRect(x: 100, y: 44, width: 600, height: 400)
        #expect(WindowClamp.clampedFrame(window: dragged, screen: screen, insets: ReservedInsets(top: bar)) == expected)
    }

    @Test("a maximised window with bars top and left ends up exactly in the free rect")
    func topAndLeftBarsFitMaximisedWindow() {
        let maximised = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let expected = CGRect(x: 44, y: 44, width: 1468, height: 938)
        let insets = ReservedInsets(top: bar, left: bar)
        #expect(WindowClamp.clampedFrame(window: maximised, screen: screen, insets: insets) == expected)
    }

    @Test("left bar: a window dragged under it is moved right, the size stays")
    func leftBarMovesDraggedWindow() {
        let dragged = CGRect(x: 10, y: 200, width: 600, height: 400)
        let expected = CGRect(x: 44, y: 200, width: 600, height: 400)
        #expect(WindowClamp.clampedFrame(window: dragged, screen: screen, insets: ReservedInsets(left: bar)) == expected)
    }

    @Test("left bar: while moving, not past the screen on the right")
    func leftBarMoveStopsAtRightEdge() {
        let wide = CGRect(x: -10, y: 30, width: 1500, height: 900)
        let expected = CGRect(x: 44, y: 30, width: 1468, height: 900)
        #expect(WindowClamp.clampedFrame(window: wide, screen: screen, insets: ReservedInsets(left: bar)) == expected)
    }

    @Test("minSize is respected on both axes, then only moved")
    func respectsMinimumSize() {
        let tooSmallToShrink = CGRect(x: 0, y: 0, width: 400, height: 300)
        let insets = ReservedInsets(top: bar, left: bar)
        let minSize = CGSize(width: 380, height: 260)
        let expected = CGRect(x: 44, y: 44, width: 380, height: 260)
        #expect(WindowClamp.clampedFrame(window: tooSmallToShrink, screen: screen, insets: insets, minSize: minSize) == expected)
    }

    @Test("zero insets: nothing to do")
    func zeroInsetsDoNothing() {
        let window = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(WindowClamp.clampedFrame(window: window, screen: screen, insets: .zero) == nil)
        #expect(ReservedInsets.zero.isZero)
    }

    @Test("a window with no overlap with any reserved strip stays as it is")
    func noOverlapIsUntouched() {
        let window = CGRect(x: 200, y: 200, width: 400, height: 300)
        let insets = ReservedInsets(top: bar, left: bar)
        #expect(WindowClamp.clampedFrame(window: window, screen: screen, insets: insets) == nil)
    }

    @Test("without insets or with an empty window do nothing")
    func degenerateInput() {
        #expect(WindowClamp.clampedFrame(
            window: CGRect(x: 0, y: 0, width: 500, height: 500), screen: screen, insets: .zero
        ) == nil)
        #expect(WindowClamp.clampedFrame(
            window: CGRect(x: 0, y: 0, width: 0, height: 500), screen: screen, insets: ReservedInsets(left: bar)
        ) == nil)
    }
}
