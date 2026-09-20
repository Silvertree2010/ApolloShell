import CoreGraphics
import ApolloShellCore
import Testing

@Suite("Kantenfenster per Maus")
struct EdgeHoverTests {
    @Test("Maus-Regel: rein sichtbar, raus weg")
    func hoverRule() {
        let shown = EdgeHoverState.hidden.moved(inArea: true)
        #expect(shown == EdgeHoverState(visible: true, shortcutActive: false))
        #expect(shown.moved(inArea: false) == .hidden)
    }

    @Test("opened by a shortcut: the mouse outside does not close it")
    func shortcutStaysOpen() {
        let opened = EdgeHoverState.openedByShortcut(mouseInArea: false)
        #expect(opened == EdgeHoverState(visible: true, shortcutActive: true))
        #expect(opened.moved(inArea: false) == opened)
    }

    @Test("Shortcut mode: move in once, then the mouse rule holds")
    func shortcutTurnsIntoHover() {
        let entered = EdgeHoverState.openedByShortcut(mouseInArea: false).moved(inArea: true)
        #expect(entered == EdgeHoverState(visible: true, shortcutActive: false))
        #expect(entered.moved(inArea: false) == .hidden)
    }

    @Test("The mouse in the area at the opening already: the mouse rule right away")
    func shortcutWithMouseInside() {
        #expect(EdgeHoverState.openedByShortcut(mouseInArea: true) == EdgeHoverState(visible: true, shortcutActive: false))
    }

    @Test("The area at the top: closed only the edge, open the whole window")
    func topArea() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let closed = EdgeHoverArea.top(screen: screen, width: 871, depth: 516, margin: 25, open: false)
        #expect(closed.contains(CGPoint(x: 864, y: 1117)))
        #expect(closed.contains(CGPoint(x: 864, y: 1115.5)))
        #expect(!closed.contains(CGPoint(x: 864, y: 1110)))
        #expect(closed.contains(CGPoint(x: 405, y: 1117)))
        #expect(!closed.contains(CGPoint(x: 400, y: 1117)))

        let open = EdgeHoverArea.top(screen: screen, width: 871, depth: 516, margin: 25, open: true)
        #expect(open.contains(CGPoint(x: 864, y: 700)))
        #expect(!open.contains(CGPoint(x: 864, y: 500)))
    }

    @Test("The area at the bottom right: the edge yes, the corner free for the quick note")
    func bottomRightArea() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let closed = EdgeHoverArea.bottomRight(screen: screen, width: 430, height: 217, margin: 25, open: false)
        #expect(closed.contains(CGPoint(x: 1500, y: 0)))
        #expect(closed.contains(CGPoint(x: 1274, y: 1)))
        #expect(!closed.contains(CGPoint(x: 1260, y: 0)))
        #expect(!closed.contains(CGPoint(x: 1720, y: 0)))
        #expect(!closed.contains(CGPoint(x: 1500, y: 10)))

        let open = EdgeHoverArea.bottomRight(screen: screen, width: 430, height: 217, margin: 25, open: true)
        #expect(open.contains(CGPoint(x: 1500, y: 150)))
        #expect(open.contains(CGPoint(x: 1727, y: 100)))
        #expect(!open.contains(CGPoint(x: 1500, y: 230)))
    }

    /// The panel stays clickable while it fades out. A double click on the
    /// screenshot or the lock therefore ran once right away (with the glass
    /// still visible) and once after the fade-out.
    @Test("Closing with an action: never before the fade-out, never twice", arguments: [
        (true, false, false, DrawerCloseStep.closeThenRun),
        (true, true, false, DrawerCloseStep.closeThenRun),
        (false, true, false, DrawerCloseStep.runAfterFade),
        (false, true, true, DrawerCloseStep.drop),
        (false, false, false, DrawerCloseStep.runNow),
    ])
    func closeStep(isOpen: Bool, isVisible: Bool, hasPendingAction: Bool, expected: DrawerCloseStep) {
        #expect(DrawerCloseStep(isOpen: isOpen, isVisible: isVisible, hasPendingAction: hasPendingAction) == expected)
    }
}
