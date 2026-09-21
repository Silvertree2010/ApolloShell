import ApolloShellCore
import Testing

@Suite("Klick im Dock der Leiste")
struct DockClickTests {
    /// Kurzform, damit die Faelle unten lesbar bleiben.
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

    @Test("Nicht laufend: starten")
    func notRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false))
        #expect(actions == [.launch])
    }

    @Test("Laeuft, nicht vorne, Fenster hier und woanders: das hiesige nach vorne, kein Space-Wechsel")
    func hereAndElsewhereRaisesHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, elsewhere: 2))
        #expect(actions == [.raiseWindowOnActiveSpace])
    }

    @Test("Laeuft, nicht vorne, Fenster nur hier: das hiesige nach vorne")
    func onlyHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, elsewhere: 0))
        #expect(actions == [.raiseWindowOnActiveSpace])
    }

    /// `activate()` allein reicht nicht: gemessen 20.09. wird die App damit
    /// zwar zur vordersten, das Fenster bleibt aber auf seinem Schreibtisch.
    @Test("Laeuft, nicht vorne, Fenster nur woanders: das dortige Fenster nach vorne")
    func onlyElsewhere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 0, elsewhere: 2))
        #expect(actions == [.raiseWindowElsewhere])
    }

    @Test("Laeuft, ausgeblendet, Fenster hier: einblenden und das hiesige nach vorne")
    func hiddenWithWindowHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, hidden: true, here: 1))
        #expect(actions == [.unhide, .raiseWindowOnActiveSpace])
    }

    @Test("Schon vorne mit Fenster hier: nichts tun")
    func alreadyFrontmostDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1))
        #expect(actions.isEmpty)
    }

    @Test("Schon vorne, Fenster hier und woanders: trotzdem nichts tun (hier reicht)")
    func frontmostHereAndElsewhereDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1, elsewhere: 3))
        #expect(actions.isEmpty)
    }

    @Test("Schon vorne, ein Fenster hier ist verdeckt: das vorderste verdeckte nach vorne")
    func frontmostCoveredWindowRaises() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 2, covered: true))
        #expect(actions == [.raiseCoveredWindow])
    }

    @Test("Schon vorne, Fenster hier every frei sichtbar (nebeneinander): nichts tun, kein Blaettern")
    func frontmostSideBySideDoesNothing() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 2, covered: false))
        #expect(actions.isEmpty)
    }

    @Test("Vorne, aber kein Fenster hier, nur woanders: dorthin (Rand: aktiv auf falschem Space gelandet)")
    func frontmostOnlyElsewhere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 0, elsewhere: 1))
        #expect(actions == [.raiseWindowElsewhere])
    }

    @Test("Schon vorne, every Fenster minimiert: das letzte zurueckholen")
    func frontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true, here: 0, elsewhere: 0, minimized: 3))
        #expect(actions == [.unminimizeLast])
    }

    @Test("Nicht vorne, every Fenster minimiert: das letzte zurueckholen")
    func notFrontmostAllMinimized() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 0, elsewhere: 0, minimized: 2))
        #expect(actions == [.unminimizeLast])
    }

    @Test("Schon vorne, kein Fenster: neues oeffnen (reopen)")
    func frontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: true))
        #expect(actions == [.activate, .newWindow])
    }

    @Test("Nicht vorne, kein Fenster: aktivieren und neues oeffnen")
    func notFrontmostNoWindow() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false))
        #expect(actions == [.activate, .newWindow])
    }

    @Test("Startet gerade: nichts tun, kein doppelter Start")
    func launching() {
        let actions = DockClick.actions(for: Self.state(running: false, launching: true, frontmost: false))
        #expect(actions.isEmpty)
    }

    @Test("⌥-Klick: hinueberwechseln und danach die vorherige App ausblenden")
    func optionHidesPrevious() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, elsewhere: 1, option: true))
        #expect(actions == [.raiseWindowElsewhere, .hidePrevious])
    }

    @Test("⌥-Klick mit Fenster hier: hiesiges Fenster nach vorne, danach die vorherige App ausblenden")
    func optionHidesPreviousWithWindowHere() {
        let actions = DockClick.actions(for: Self.state(running: true, frontmost: false, here: 1, option: true))
        #expect(actions == [.raiseWindowOnActiveSpace, .hidePrevious])
    }

    @Test("⌥-Klick auf nicht laufende App: starten, danach ausblenden")
    func optionOnNotRunning() {
        let actions = DockClick.actions(for: Self.state(running: false, frontmost: false, option: true))
        #expect(actions == [.launch, .hidePrevious])
    }

    @Test("⌘-Klick: nur im Dateimanager zeigen, unabhaengig vom Zustand")
    func commandAlwaysReveals() {
        #expect(DockClick.actions(for: Self.state(running: true, frontmost: true, here: 1, command: true)) == [.reveal])
        #expect(DockClick.actions(for: Self.state(running: false, frontmost: false, command: true)) == [.reveal])
        #expect(
            DockClick.actions(for: Self.state(running: true, frontmost: false, minimized: 1, command: true, option: true))
                == [.reveal]
        )
    }
}
