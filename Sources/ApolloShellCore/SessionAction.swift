import Foundation

public enum SessionAction: String, CaseIterable, Sendable {
    case logOut, shutDown, sleep, restart

    public static let menuOrder: [SessionAction] = [.logOut, .shutDown, .sleep, .restart]

    public static let emblemSlot = 2

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

    public var title: String {
        switch self {
        case .logOut: String(localized: "Log Out")
        case .shutDown: String(localized: "Shut Down")
        case .sleep: String(localized: "Sleep")
        case .restart: String(localized: "Restart")
        }
    }

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
