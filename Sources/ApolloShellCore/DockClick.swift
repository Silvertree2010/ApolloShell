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
    /// Ist sie schon vorne und hat hier ein Fenster: liegt mindestens eins
    /// davon unter einem fremden Fenster (`DockWindowCover`)? Nur dann
    /// blaettert der Klick; mehrere Fenster, die nur nebeneinander offen
    /// sind, bleiben in Ruhe.
    public let hasCoveredWindow: Bool
    /// ⌘ gedrueckt.
    public let command: Bool
    /// ⌥ gedrueckt.
    public let option: Bool

    public init(
        running: Bool, launching: Bool = false, frontmost: Bool, hidden: Bool,
        windowsOnActiveSpace: Int, windowsElsewhere: Int, minimizedWindows: Int, hasCoveredWindow: Bool = false,
        command: Bool, option: Bool
    ) {
        self.running = running
        self.launching = launching
        self.frontmost = frontmost
        self.hidden = hidden
        self.windowsOnActiveSpace = windowsOnActiveSpace
        self.windowsElsewhere = windowsElsewhere
        self.minimizedWindows = minimizedWindows
        self.hasCoveredWindow = hasCoveredWindow
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
    /// Nach vorne. Nur noch, wenn es gar kein Fenster zu heben gibt -
    /// `activate()` holt keines (siehe `raiseWindowElsewhere`).
    case activate
    /// Kein Fenster auf dem aktuellen Space, aber eins auf einem anderen:
    /// genau das nach vorne holen. macOS wechselt dabei auf dessen
    /// Schreibtisch. Gemessen 20.09.: `activate()` macht die App zwar zur
    /// vordersten (Menueleiste wechselt), holt aber kein Fenster und
    /// wechselt keinen Space - auch nicht als
    /// `activate(from:options: .activateAllWindows)`, das `true` liefert und
    /// trotzdem nichts bewegt. Nur der Weg ueber das Fenster wirkt.
    case raiseWindowElsewhere
    /// Ein Fenster der App liegt schon auf dem aktuellen Space: das nach
    /// vorne holen (aktiviert die App gleich mit) statt auf den Space eines
    /// anderen Fensters zu wechseln.
    case raiseWindowOnActiveSpace
    /// Schon vorne, aber eins ihrer Fenster hier liegt unter einem fremden:
    /// das vorderste verdeckte nach vorne (`DockWindowCover` bestimmt,
    /// welches - hier steht nur, dass es dazu kommt).
    case raiseCoveredWindow
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
/// kommt eines ihrer Fenster nach vorne (und mit ihm die App); liegt eins
/// davon schon auf dem aktuellen Space, bleibt der Space dabei (kein Sprung
/// zu einem anderen), sonst wechselt macOS zum Fenster; steht sie schon vorne und hat hier ein Fenster, passiert nichts;
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
            // Schon vorne und hier ein Fenster: normalerweise nichts (Punkt
            // 3) - ausser eins davon ist verdeckt, dann holt der Klick
            // wenigstens das ans Licht statt gar nichts zu tun.
            if state.hasCoveredWindow { actions.append(.raiseCoveredWindow) }
        } else {
            actions.append(contentsOf: raiseActions(state))
        }
        if state.option { actions.append(.hidePrevious) }
        return actions
    }

    /// Nicht vorne, oder vorne ohne Fenster auf dem aktuellen Space (etwa
    /// von Hand auf einen anderen Space gewechselt, waehrend sie aktiv
    /// blieb): je nach Fensterlage das hiesige nach vorne, das auf einem
    /// anderen Schreibtisch nach vorne (samt Space-Wechsel), ein abgelegtes
    /// zurueckholen oder ein neues oeffnen.
    private static func raiseActions(_ state: DockClickState) -> [DockClickAction] {
        var actions: [DockClickAction] = []
        // Nur einblenden, wenn sie wirklich ausgeblendet ist. Gemessen 16.09.:
        // `unhide()` auf eine sichtbare App holt deren zuletzt benutztes
        // Fenster nach vorne - liegt das auf einem anderen Schreibtisch,
        // springt macOS dorthin, obwohl hier eins liegt.
        if state.hidden { actions.append(.unhide) }
        if state.windowsOnActiveSpace > 0 {
            actions.append(.raiseWindowOnActiveSpace)
        } else if state.windowsElsewhere > 0 {
            actions.append(.raiseWindowElsewhere)
        } else if state.minimizedWindows > 0 {
            // Das Zurueckholen hebt das Fenster gleich mit und bringt die App
            // nach vorne - ein zusaetzliches `activate` wuerde nur dieselbe
            // Aufgabe schlechter erledigen (siehe `raiseWindowElsewhere`).
            actions.append(.unminimizeLast)
        } else {
            actions.append(.activate)
            actions.append(.newWindow)
        }
        return actions
    }
}
