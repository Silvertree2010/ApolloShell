import Testing
@testable import ApolloShellCore

@Suite("Session menu")
struct SessionActionTests {
    @Test("Order like Caelestia, emblem between shut down and sleep")
    func orderMatchesCaelestia() {
        #expect(SessionAction.menuOrder == [.logOut, .shutDown, .sleep, .restart])
        #expect(SessionAction.menuOrder[SessionAction.emblemSlot] == .sleep)
    }

    @Test("no preselection on open")
    func noSelectionInitially() {
        #expect(SessionSelection().action == nil)
    }

    @Test("first arrow: down highlights the top button, up the bottom one")
    func firstArrowStartsAtAnEnd() {
        var down = SessionSelection()
        down.move(by: 1)
        #expect(down.action == .logOut)
        var up = SessionSelection()
        up.move(by: -1)
        #expect(up.action == .restart)
    }

    @Test("Arrows move the selection without wraparound")
    func moveClampsWithoutWrap() {
        var selection = SessionSelection()
        selection.move(by: 1)
        selection.move(by: -1)
        #expect(selection.action == .logOut)
        selection.move(by: 1)
        #expect(selection.action == .shutDown)
        selection.move(by: 10)
        #expect(selection.action == .restart)
        selection.move(by: 1)
        #expect(selection.action == .restart)
    }

    @Test("Direct selection by mouse")
    func selectByAction() {
        var selection = SessionSelection()
        selection.select(.sleep)
        #expect(selection.action == .sleep)
    }

    @Test("Commands behind the buttons", arguments: [
        (SessionAction.sleep, "/usr/bin/pmset", ["sleepnow"]),
        (SessionAction.restart, "/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"]),
        (SessionAction.shutDown, "/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"]),
        (SessionAction.logOut, "/usr/bin/osascript", ["-e", "tell application \"System Events\" to log out"]),
    ])
    func commands(action: SessionAction, executable: String, arguments: [String]) {
        #expect(action.command.executable == executable)
        #expect(action.command.arguments == arguments)
    }
}
