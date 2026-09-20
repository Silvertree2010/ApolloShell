import Foundation

/// The keyboard shortcut of a menu item the way the accessibility API reports
/// it: a character and a bit mask for the modifier keys.
///
/// The mask is the one of `kAXMenuItemCmdModifiers`: bit 0 shift, bit 1
/// option, bit 2 control - and bit 3 means that **no** command key belongs to
/// it. So 0 is the plain ⌘.
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

    /// The same character, upper and lower case do not matter.
    public func matches(_ character: String) -> Bool {
        self.character.lowercased() == character.lowercased()
    }
}

/// Which kind of command a menu item is when it belongs in the Dock menu.
public enum DockCommandKind: Equatable, Sendable {
    /// "New Window", "New Private Window", "New Tab" …
    case newItem
    /// "Settings …"
    case settings
}

/// Which menu items of an app come into the Dock menu of the bar.
///
/// Apple's Dock shows what the app offers itself there (with Vivaldi “New
/// Window”, “New Private Window”, “Settings”). That Dock menu of the app is
/// open to Apple's Dock alone. The same commands stand in its menu bar though,
/// in the app menu and in the first menu after it (File, with kitty “Shell”) -
/// measured 14.09. with Vivaldi, kitty, ForkLift.
///
/// They are recognised by the shortcut first and only then by the text: ⌘N is
/// a new window in every language, ⌘, is the settings. The text stays the
/// second way, for entries without a shortcut (“New Private Window” has none
/// in some apps).
public enum DockCommandFilter {
    public static func isNewCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("New ") || trimmed.hasPrefix("Neu")
    }

    /// The words for the settings in the languages the shell speaks itself.
    /// Everything else is found by the shortcut ⌘,.
    public static func isSettingsCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("einstellungen") || trimmed.hasPrefix("settings")
            || trimmed.hasPrefix("preferences")
    }

    /// Does this menu item belong in the Dock menu, and as what?
    ///
    /// `shortcut` is the shortcut of the item, `nil` when it has none.
    public static func kind(title: String, shortcut: MenuShortcut?) -> DockCommandKind? {
        if let shortcut, shortcut.hasCommand, !shortcut.hasControl, !shortcut.hasOption {
            // ⌘, is the settings everywhere, ⌘N and ⇧⌘N a new window -
            // no matter what the entry is called.
            if shortcut.matches(",") { return .settings }
            if shortcut.matches("n") { return .newItem }
        }
        if isSettingsCommand(title) { return .settings }
        if isNewCommand(title) { return .newItem }
        return nil
    }
}
