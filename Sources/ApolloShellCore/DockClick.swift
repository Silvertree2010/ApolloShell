import Foundation

public struct DockClickState: Equatable, Sendable {
    public let running: Bool
    public let launching: Bool
    public let frontmost: Bool
    public let hidden: Bool
    public let windowsOnActiveSpace: Int
    public let windowsElsewhere: Int
    public let minimizedWindows: Int
    public let hasCoveredWindow: Bool
    public let command: Bool
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

public enum DockClickAction: Equatable, Sendable {
    case launch
    case unhide
    case activate
    case raiseWindowElsewhere
    case raiseWindowOnActiveSpace
    case raiseCoveredWindow
    case unminimizeLast
    case newWindow
    case hidePrevious
    case reveal
}

public enum DockClick {
    public static func actions(for state: DockClickState) -> [DockClickAction] {
        if state.command { return [.reveal] }
        if state.launching { return [] }

        var actions: [DockClickAction] = []
        if !state.running {
            actions.append(.launch)
        } else if state.frontmost, state.windowsOnActiveSpace > 0 {
            if state.hasCoveredWindow { actions.append(.raiseCoveredWindow) }
        } else {
            actions.append(contentsOf: raiseActions(state))
        }
        if state.option { actions.append(.hidePrevious) }
        return actions
    }

    private static func raiseActions(_ state: DockClickState) -> [DockClickAction] {
        var actions: [DockClickAction] = []
        if state.hidden { actions.append(.unhide) }
        if state.windowsOnActiveSpace > 0 {
            actions.append(.raiseWindowOnActiveSpace)
        } else if state.windowsElsewhere > 0 {
            actions.append(.raiseWindowElsewhere)
        } else if state.minimizedWindows > 0 {
            actions.append(.unminimizeLast)
        } else {
            actions.append(.activate)
            actions.append(.newWindow)
        }
        return actions
    }
}
