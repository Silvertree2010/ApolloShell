import Foundation

/// The four actions of the session menu.
///
/// Built like the session menu of Caelestia (modules/session/Content.qml):
/// from top to bottom log out, shut down, then the emblem, then sleep and
/// restart. Caelestia has Hibernate there; that does not exist on the Mac in
/// that form, so sleep.
public enum SessionAction: String, CaseIterable, Sendable {
    case logOut, shutDown, sleep, restart

    /// The order of the buttons from top to bottom.
    public static let menuOrder: [SessionAction] = [.logOut, .shutDown, .sleep, .restart]

    /// The emblem sits before this button index (between shut down and sleep,
    /// where Caelestia shows its image).
    public static let emblemSlot = 2

    /// The id for the symbol swap in the theme (`icons/<id>.png`).
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

    /// For the tooltip and VoiceOver; the buttons themselves carry no label, as
    /// in Caelestia.
    public var title: String {
        switch self {
        case .logOut: String(localized: "Log Out")
        case .shutDown: String(localized: "Shut Down")
        case .sleep: String(localized: "Sleep")
        case .restart: String(localized: "Restart")
        }
    }

    /// The command behind it. No confirmation, as in Caelestia: the menu is the
    /// confirmation itself. Restart, shut down and log out go through System
    /// Events as in the Apple menu: apps with unsaved documents ask by
    /// themselves and can cancel. Needs the automation permission for System
    /// Events; macOS asks for it the first time.
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

/// The keyboard selection in the session menu, ↑↓ move without wrapping.
///
/// Deliberately WITHOUT a preselection, unlike Caelestia (where log out is
/// preselected): a button that stays marked looks like a hover effect that got
/// stuck. The first press on ↓ marks the topmost button, ↑ the bottom one.
/// Enter without a selection does nothing - so an accidental Enter logs nobody
/// out.
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
