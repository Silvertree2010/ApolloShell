import ApolloShellCore
import Testing

@Suite("Klick im Dock der Leiste")
struct DockClickTests {
    /// Kurzform, damit die Faelle unten lesbar bleiben.
    private static func state(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool = false,
        normal: Int = 0, minimized: Int = 0, command: Bool = false, option: Bool = false
    ) -> DockClickState {
        DockClickState(
            running: running, launching: launching, frontmost: frontmost, hidden: hidden,
            normalWindows: normal, minimizedWindows: minimized, command: command, option: option
        )
    }

    @Test("Nicht laufend: starten")
    func notRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false))
        #expect(actions == [.launch])
    }

    @Test("Laeuft, nicht vorne, hat ein Fenster: aktivieren (mit Einblenden)")
    func activateExisting() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, normal: 2))
        #expect(actions == [.unhide, .activate])
    }

    @Test("Laeuft, ausgeblendet, nicht vorne: einblenden und aktivieren")
    func unhideAndActivate() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, hidden: true, normal: 1))
        #expect(actions == [.unhide, .activate])
    }

    @Test("Schon vorne mit Fenster: nichts tun")
    func alreadyFrontmostDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, normal: 1))
        #expect(actions.isEmpty)
    }

    @Test("Schon vorne, alle Fenster minimiert: das letzte zurueckholen")
    func frontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, normal: 0, minimized: 3))
        #expect(actions == [.unminimizeLast, .activate])
    }

    @Test("Nicht vorne, alle Fenster minimiert: das letzte zurueckholen")
    func notFrontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, normal: 0, minimized: 2))
        #expect(actions == [.unhide, .unminimizeLast, .activate])
    }

    @Test("Schon vorne, kein Fenster: neues oeffnen (reopen)")
    func frontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, normal: 0, minimized: 0))
        #expect(actions == [.activate, .newWindow])
    }

    @Test("Nicht vorne, kein Fenster: aktivieren und neues oeffnen")
    func notFrontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, normal: 0, minimized: 0))
        #expect(actions == [.unhide, .activate, .newWindow])
    }

    @Test("Startet gerade: nichts tun, kein doppelter Start")
    func launching() {
        let actions = DockClick.actions(for: Self.state(running: false, launching: true, frontmost: false))
        #expect(actions.isEmpty)
    }

    @Test("⌥-Klick: aktivieren und danach die vorherige App ausblenden")
    func optionHidesPrevious() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, normal: 1, option: true))
        #expect(actions == [.unhide, .activate, .hidePrevious])
    }

    @Test("⌥-Klick auf nicht laufende App: starten, danach ausblenden")
    func optionOnNotRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false, option: true))
        #expect(actions == [.launch, .hidePrevious])
    }

    @Test("⌘-Klick: nur im Dateimanager zeigen, unabhaengig vom Zustand")
    func commandAlwaysReveals() {
        #expect(DockClick.actions(for: Self.state(running: true, frontmost: true, normal: 1, command: true)) == [.reveal])
        #expect(DockClick.actions(for: Self.state(running: false, frontmost: false, command: true)) == [.reveal])
        #expect(DockClick.actions(for: Self.state(running: true, frontmost: false, minimized: 1, command: true, option: true)) == [.reveal])
    }
}
