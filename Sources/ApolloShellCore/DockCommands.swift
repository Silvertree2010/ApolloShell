import Foundation

public struct MenuShortcut: Equatable, Hashable, Sendable {
    public let character: String
    public let modifiers: Int

    public init(character: String, modifiers: Int) {
        self.character = character
        self.modifiers = modifiers
    }

    public var hasCommand: Bool { modifiers & 8 == 0 }
    public var hasShift: Bool { modifiers & 1 != 0 }
    public var hasOption: Bool { modifiers & 2 != 0 }
    public var hasControl: Bool { modifiers & 4 != 0 }

    public func matches(_ character: String) -> Bool {
        self.character.lowercased() == character.lowercased()
    }
}

public enum DockCommandKind: Equatable, Sendable {
    case newItem
    case settings
}

public enum DockCommandFilter {
    public static func isNewCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("New ") || trimmed.hasPrefix("Neu")
    }

    public static func isSettingsCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("einstellungen") || trimmed.hasPrefix("settings")
            || trimmed.hasPrefix("preferences")
    }

    public static func kind(title: String, shortcut: MenuShortcut?) -> DockCommandKind? {
        if let shortcut, shortcut.hasCommand, !shortcut.hasControl, !shortcut.hasOption {
            if shortcut.matches(",") { return .settings }
            if shortcut.matches("n") { return .newItem }
        }
        if isSettingsCommand(title) { return .settings }
        if isNewCommand(title) { return .newItem }
        return nil
    }
}
