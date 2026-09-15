import Foundation

/// Was ein Klick auf ein Symbol im Dock der Leiste tut - wie in Apples Dock,
/// damit die gewohnten Klicks mit Modifiern gleich wirken.
public enum DockClickAction: Equatable, Sendable {
    /// Laeuft sie, nach vorne (ohne Fenster macht sie eins auf), sonst starten.
    case open
    /// ⌥-Klick: wechseln und die App davor ausblenden.
    case openHidingPrevious
    /// ⌘⌥-Klick: wechseln und alle anderen ausblenden.
    case openHidingOthers
    /// ⌘-Klick: im Dateimanager zeigen.
    case reveal

    public static func action(command: Bool, option: Bool) -> DockClickAction {
        switch (command, option) {
        case (true, true): .openHidingOthers
        case (true, false): .reveal
        case (false, true): .openHidingPrevious
        case (false, false): .open
        }
    }
}
