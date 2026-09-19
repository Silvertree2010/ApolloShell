import Foundation

/// Die vier Aktionen des Sitzungsmenues.
///
/// Aufbau wie im Sitzungsmenue von Caelestia (modules/session/Content.qml):
/// von oben nach unten Abmelden, Ausschalten, dann das Emblem, dann
/// Ruhezustand und Neustart. Caelestia hat dort Hibernate; das gibt es auf
/// dem Mac so nicht, deshalb Ruhezustand.
public enum SessionAction: String, CaseIterable, Sendable {
    case logOut, shutDown, sleep, restart

    /// Reihenfolge der Knoepfe von oben nach unten.
    public static let menuOrder: [SessionAction] = [.logOut, .shutDown, .sleep, .restart]

    /// Vor diesem Knopf-Index sitzt das Emblem (zwischen Ausschalten und
    /// Ruhezustand, wo Caelestia sein Bild zeigt).
    public static let emblemSlot = 2

    /// Kennung fuer den Symbol-Austausch im Theme (`icons/<kennung>.png`).
    public var iconID: String {
        switch self {
        case .logOut: "session-logout"
        case .shutDown: "session-shutdown"
        case .sleep: "session-sleep"
        case .restart: "session-restart"
        }
    }

    public var symbolName: String {
        switch self {
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .shutDown: "power"
        case .sleep: "moon.zzz"
        case .restart: "arrow.clockwise"
        }
    }

    /// Fuer Tooltip und VoiceOver; die Knoepfe selbst sind wie bei Caelestia
    /// ohne Beschriftung.
    public var title: String {
        switch self {
        case .logOut: String(localized: "Log Out")
        case .shutDown: String(localized: "Shut Down")
        case .sleep: String(localized: "Sleep")
        case .restart: String(localized: "Restart")
        }
    }

    /// Der Befehl dahinter. Keine Rueckfrage, wie bei Caelestia: das Menue
    /// ist selbst die Bestaetigung. Neustart, Ausschalten und Abmelden gehen
    /// ueber System Events wie im Apple-Menue: Apps mit ungesicherten
    /// Dokumenten fragen selbst nach und koennen abbrechen. Braucht die
    /// Automation-Freigabe fuer System Events; macOS fragt beim ersten
    /// Mal danach.
    public var command: (executable: String, arguments: [String]) {
        switch self {
        case .sleep:
            ("/usr/bin/pmset", ["sleepnow"])
        case .restart:
            ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
        case .shutDown:
            ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
        case .logOut:
            ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to log out"])
        }
    }
}

/// Tastatur-Auswahl im Sitzungsmenue, ↑↓ bewegen ohne Umlauf.
///
/// Bewusst OHNE Vorauswahl, anders als Caelestia (dort ist Abmelden
/// vorausgewaehlt): ein dauerhaft markierter Knopf wirkt wie ein
/// haengender Hover-Effekt. Der erste Druck auf ↓ markiert den obersten, ↑ den
/// untersten Knopf. Enter ohne Auswahl tut nichts - ein versehentliches Enter
/// meldet also niemanden ab.
public struct SessionSelection: Equatable, Sendable {
    public private(set) var index: Int?

    public init() {}

    public var action: SessionAction? { index.map { SessionAction.menuOrder[$0] } }

    public mutating func move(by delta: Int) {
        let last = SessionAction.menuOrder.count - 1
        guard let current = index else {
            index = delta > 0 ? 0 : last
            return
        }
        index = min(max(current + delta, 0), last)
    }

    public mutating func select(_ action: SessionAction) {
        if let i = SessionAction.menuOrder.firstIndex(of: action) { index = i }
    }
}
