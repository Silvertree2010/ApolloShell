import Testing
@testable import ApolloShellCore

@Suite("Sitzungsmenue")
struct SessionActionTests {
    @Test("Reihenfolge wie Caelestia, Emblem zwischen Ausschalten und Ruhezustand")
    func orderMatchesCaelestia() {
        #expect(SessionAction.menuOrder == [.logOut, .shutDown, .sleep, .restart])
        #expect(SessionAction.menuOrder[SessionAction.emblemSlot] == .sleep)
    }

    @Test("keine Vorauswahl beim Oeffnen")
    func noSelectionInitially() {
        #expect(SessionSelection().action == nil)
    }

    @Test("erster Pfeil: runter markiert den obersten, hoch den untersten Knopf")
    func firstArrowStartsAtAnEnd() {
        var down = SessionSelection()
        down.move(by: 1)
        #expect(down.action == .logOut)
        var up = SessionSelection()
        up.move(by: -1)
        #expect(up.action == .restart)
    }

    @Test("Pfeile bewegen die Auswahl ohne Umlauf")
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

    @Test("Direkte Auswahl per Maus")
    func selectByAction() {
        var selection = SessionSelection()
        selection.select(.sleep)
        #expect(selection.action == .sleep)
    }

    @Test("Befehle hinter den Knoepfen", arguments: [
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
