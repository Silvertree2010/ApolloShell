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
    /// Sichtbare (nicht minimierte) Fenster.
    public let normalWindows: Int
    /// Minimierte Fenster (im Dock abgelegt).
    public let minimizedWindows: Int
    /// ⌘ gedrueckt.
    public let command: Bool
    /// ⌥ gedrueckt.
    public let option: Bool

    public init(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool,
        normalWindows: Int, minimizedWindows: Int, command: Bool, option: Bool
    ) {
        self.running = running
        self.launching = launching
        self.frontmost = frontmost
        self.hidden = hidden
        self.normalWindows = normalWindows
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
    /// Nach vorne (Fenster mit hoch, macOS wechselt dafuer selbst den Space).
    case activate
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
/// kommt sie (mit allen Fenstern) nach vorne; steht sie schon vorne, passiert
/// nichts; sind alle Fenster abgelegt, kommt das zuletzt abgelegte zurueck;
/// hat sie gar keins, oeffnet sie eins ("reopen"). Kein Blaettern durch
/// Fenster mehr beim Klick - das macht weiterhin nur Scrollen
/// (`DockWindowCycle`).
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
        } else if state.frontmost {
            actions.append(contentsOf: frontmostActions(state))
        } else {
            actions.append(.unhide)
            actions.append(contentsOf: activationActions(state))
        }
        if state.option { actions.append(.hidePrevious) }
        return actions
    }

    /// Schon vorne: normalerweise nichts, ausser es gibt gar kein
    /// sichtbares Fenster - dann gilt dieselbe Logik wie beim Aktivieren
    /// (Punkt 4/5), nur ohne erneutes Aktivieren-Kommando noetig.
    private static func frontmostActions(_ state: DockClickState) -> [DockClickAction] {
        guard state.normalWindows == 0 else { return [] }
        if state.minimizedWindows > 0 {
            return [.unminimizeLast, .activate]
        }
        return [.activate, .newWindow]
    }

    /// Nicht vorne: immer aktivieren, dazu je nach Fensterlage abgelegtes
    /// zurueckholen oder ein neues oeffnen.
    private static func activationActions(_ state: DockClickState) -> [DockClickAction] {
        if state.normalWindows > 0 {
            return [.activate]
        }
        if state.minimizedWindows > 0 {
            return [.unminimizeLast, .activate]
        }
        return [.activate, .newWindow]
    }
}
