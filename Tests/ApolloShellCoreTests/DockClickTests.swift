import ApolloShellCore
import Testing

@Suite("A click in the Dock of the bar")
struct DockClickTests {
    /// A short form, so that the cases below stay readable.
    private static func state(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool = false,
        here: Int = 0, elsewhere: Int = 0, minimized: Int = 0, covered: Bool = false,
        command: Bool = false, option: Bool = false
    ) -> DockClickState {
        DockClickState(
            running: running, launching: launching, frontmost: frontmost, hidden: hidden,
            windowsOnActiveSpace: here, windowsElsewhere: elsewhere, minimizedWindows: minimized,
            hasCoveredWindow: covered, command: command, option: option
        )
    }

    @Test("Not running: start it")
    func notRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false))
        #expect(actions == [.launch])
    }

    @Test("Running, not at the front, windows here and elsewhere: the one here forward, no space change")
    func hereAndElsewhereRaisesHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, elsewhere: 2))
        #expect(actions == [.raiseWindowOnActiveSpace])
    }

    @Test("Running, not at the front, windows only here: the one here forward")
    func onlyHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, elsewhere: 0))
        #expect(actions == [.raiseWindowOnActiveSpace])
    }

    @Test("Running, not at the front, windows only elsewhere: activate, macOS switches by itself")
    func onlyElsewhere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 0, elsewhere: 2))
        #expect(actions == [.activate])
    }

    @Test("Running, hidden, windows here: unhide and bring the one here forward")
    func hiddenWithWindowHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, hidden: true, here: 1))
        #expect(actions == [.unhide, .raiseWindowOnActiveSpace])
    }

    @Test("At the front already with a window here: do nothing")
    func alreadyFrontmostDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1))
        #expect(actions.isEmpty)
    }

    @Test("At the front already, windows here and elsewhere: still do nothing (here is enough)")
    func frontmostHereAndElsewhereDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1, elsewhere: 3))
        #expect(actions.isEmpty)
    }

    @Test("At the front already, a window here is covered: the frontmost covered one forward")
    func frontmostCoveredWindowRaises() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 2, covered: true))
        #expect(actions == [.raiseCoveredWindow])
    }

    @Test("At the front already, the windows here all freely visible (side by side): do nothing, no paging")
    func frontmostSideBySideDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 2, covered: false))
        #expect(actions.isEmpty)
    }

    @Test("At the front, but no window here, only elsewhere: activate (edge case: active but landed on the wrong space)")
    func frontmostOnlyElsewhere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 0, elsewhere: 1))
        #expect(actions == [.activate])
    }

    @Test("At the front already, all windows minimised: fetch the last one back")
    func frontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 0, elsewhere: 0, minimized: 3))
        #expect(actions == [.unminimizeLast, .activate])
    }

    @Test("Not at the front, all windows minimised: fetch the last one back")
    func notFrontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 0, elsewhere: 0, minimized: 2))
        #expect(actions == [.unminimizeLast, .activate])
    }

    @Test("At the front already, no window: open a new one (reopen)")
    func frontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true))
        #expect(actions == [.activate, .newWindow])
    }

    @Test("Not at the front, no window: activate and open a new one")
    func notFrontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false))
        #expect(actions == [.activate, .newWindow])
    }

    @Test("Starting right now: do nothing, no double start")
    func launching() {
        let actions = DockClick.actions(for: Self.state(running: false, launching: true, frontmost: false))
        #expect(actions.isEmpty)
    }

    @Test("⌥ click: activate and hide the previous app afterwards")
    func optionHidesPrevious() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, elsewhere: 1, option: true))
        #expect(actions == [.activate, .hidePrevious])
    }

    @Test("⌥ click with a window here: the window here forward, then hide the previous app")
    func optionHidesPreviousWithWindowHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, option: true))
        #expect(actions == [.raiseWindowOnActiveSpace, .hidePrevious])
    }

    @Test("⌥ click on an app that is not running: start it, then hide")
    func optionOnNotRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false, option: true))
        #expect(actions == [.launch, .hidePrevious])
    }

    @Test("⌘ click: only show it in the file manager, whatever the state")
    func commandAlwaysReveals() {
        #expect(DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1, command: true)) == [.reveal])
        #expect(DockClick.actions(for: Self.state(running: false, frontmost: false, command: true)) == [.reveal])
        #expect(
            DockClick.actions(for: Self.state(running: true, frontmost: false, minimized: 1, command: true, option: true))
                == [.reveal]
        )
    }
}
