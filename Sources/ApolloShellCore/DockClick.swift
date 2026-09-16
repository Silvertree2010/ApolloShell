import Foundation

/// Beschreibender Zustand einer App im Moment des Klicks - alles, was die
/// Entscheidung braucht, ohne selbst etwas zu tun oder zu lesen.
public struct DockClickState: Equatable, Sendable {
    /// Laeuft ueberhaupt ein Prozess der App.
    public let running: Bool
    /// Gerade erst gestartet, der Prozess ist noch nicht da (Symbol huepft).
    public let launching: Bool
    /// Ist sie die vorderste App.
    public let frontmost: Bool
    /// Ausgeblendet (⌘H).
    public let hidden: Bool
    /// Sichtbare (nicht minimierte) Fenster auf dem Space, der gerade zu
    /// sehen ist.
    public let windowsOnActiveSpace: Int
    /// Sichtbare (nicht minimierte) Fenster auf einem anderen Space.
    public let windowsElsewhere: Int
    /// Minimierte Fenster (im Dock abgelegt) - Space zaehlt hier nicht,
    /// die liegen ohnehin nirgends sichtbar.
    public let minimizedWindows: Int
    /// ⌘ gedrueckt.
    public let command: Bool
    /// ⌥ gedrueckt.
    public let option: Bool

    public init(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool,
        windowsOnActiveSpace: Int, windowsElsewhere: Int, minimizedWindows: Int, command: Bool, option: Bool
    ) {
        self.running = running
        self.launching = launching
        self.frontmost = frontmost
        self.hidden = hidden
        self.windowsOnActiveSpace = windowsOnActiveSpace
        self.windowsElsewhere = windowsElsewhere
        self.minimizedWindows = minimizedWindows
        self.command = command
        self.option = option
    }
}

/// Einzelne Aktion, die ein Klick im Dock der Leiste ausloesen kann. Mehrere
/// zusammen ergeben die Reihenfolge, die `DockClick.actions` liefert.
public enum DockClickAction: Equatable, Sendable {
    /// Nicht da: neu starten.
    case launch
    /// War sie ausgeblendet, wieder einblenden.
    case unhide
    /// Nach vorne. Nur wenn kein Fenster auf dem aktuellen Space liegt -
    /// dann wechselt macOS selbst dorthin, wie bei Apple.
    case activate
    /// Ein Fenster der App liegt schon auf dem aktuellen Space: das nach
    /// vorne holen (aktiviert die App gleich mit) statt auf den Space eines
    /// anderen Fensters zu wechseln.
    case raiseWindowOnActiveSpace
    /// Das zuletzt abgelegte Fenster aus dem Dock zurueckholen.
    case unminimizeLast
    /// Kein Fenster offen: ein neues (wie Apples "reopen").
    case newWindow
    /// ⌥-Klick: die vorher aktive App danach ausblenden.
    case hidePrevious
    /// ⌘-Klick: im Dateimanager zeigen statt zu wechseln.
    case reveal
}

/// Was ein Klick auf ein Symbol im Dock der Leiste tut - wie in Apples Dock:
/// laeuft die App nicht, wird sie gestartet; laeuft sie und steht nicht vorne,
/// kommt sie (mit allen Fenstern) nach vorne; liegt eins ihrer Fenster schon
/// auf dem aktuellen Space, bleibt der Space dabei (kein Sprung zu einem
/// anderen); steht sie schon vorne und hat hier ein Fenster, passiert nichts;
/// sind alle Fenster abgelegt, kommt das zuletzt abgelegte zurueck; hat sie
/// gar keins, oeffnet sie eins ("reopen"). Kein Blaettern durch Fenster mehr
/// beim Klick - das macht weiterhin nur Scrollen (`DockWindowCycle`).
public enum DockClick {
    /// Reine Entscheidung ohne Seiteneffekt: aus dem Zustand eine
    /// Reihenfolge von Aktionen, die die App-Schicht dann ausfuehrt.
    public static func actions(for state: DockClickState) -> [DockClickAction] {
        // ⌘ zeigt nur im Dateimanager, wie bei Apple unabhaengig von allem
        // anderen (auch nicht laufend oder gerade startend).
        if state.command { return [.reveal] }
        // Startet sie gerade: nichts doppeln, der naechste Klick greift, wenn
        // sie da ist.
        if state.launching { return [] }

        var actions: [DockClickAction] = []
        if !state.running {
            actions.append(.launch)
        } else if state.frontmost, state.windowsOnActiveSpace > 0 {
            // Schon vorne und hier ein Fenster: nichts tun (Punkt 3).
        } else {
            actions.append(contentsOf: raiseActions(state))
        }
        if state.option { actions.append(.hidePrevious) }
        return actions
    }

    /// Nicht vorne, oder vorne ohne Fenster auf dem aktuellen Space (etwa
    /// von Hand auf einen anderen Space gewechselt, waehrend sie aktiv
    /// blieb): je nach Fensterlage das hiesige nach vorne, sonst aktivieren
    /// (und macOS wechselt selbst, wenn es nur woanders eins gibt), abgelegtes
    /// zurueckholen oder ein neues oeffnen.
    private static func raiseActions(_ state: DockClickState) -> [DockClickAction] {
        var actions: [DockClickAction] = []
        // War sie ausgeblendet: einblenden. Schon vorne ist sie nie
        // ausgeblendet, das lohnt sich nur im anderen Zweig.
        if !state.frontmost { actions.append(.unhide) }
        if state.windowsOnActiveSpace > 0 {
            actions.append(.raiseWindowOnActiveSpace)
        } else if state.windowsElsewhere > 0 {
            actions.append(.activate)
        } else if state.minimizedWindows > 0 {
            actions.append(.unminimizeLast)
            actions.append(.activate)
        } else {
            actions.append(.activate)
            actions.append(.newWindow)
        }
        return actions
    }
}
