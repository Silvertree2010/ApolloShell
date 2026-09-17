import Foundation

/// Das Tastenkuerzel eines Menuepunkts, so wie die Bedienungshilfen es
/// melden: ein Zeichen und eine Bitmaske fuer die Zusatztasten.
///
/// Die Maske ist die von `kAXMenuItemCmdModifiers`: Bit 0 Umschalt, Bit 1
/// Wahl, Bit 2 Steuerung - und Bit 3 heisst, dass **keine** Befehlstaste
/// dazugehoert. 0 ist also das blosse ⌘.
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

    /// Dasselbe Zeichen, Gross- und Kleinschreibung egal.
    public func matches(_ character: String) -> Bool {
        self.character.lowercased() == character.lowercased()
    }
}

/// Welche Art Befehl ein Menuepunkt ist, wenn er ins Dock-Menue gehoert.
public enum DockCommandKind: Equatable, Sendable {
    /// "Neues Fenster", "Neues privates Fenster", "Neuer Tab" …
    case newItem
    /// "Einstellungen …"
    case settings
}

/// Welche Menuepunkte einer App ins Dock-Menue der Leiste kommen.
///
/// Apples Dock zeigt dort, was die App selbst anbietet (bei Vivaldi "Neues
/// Fenster", "Neues privates Fenster", "Einstellungen"). Dieses Dock-Menue
/// der App liegt nur Apples Dock offen. Dieselben Befehle stehen aber in
/// ihrer Menueleiste, im App-Menue und im ersten Menue danach (File/Ablage,
/// bei kitty "Shell") - gemessen 14.09. bei Vivaldi, kitty, ForkLift.
///
/// Erkannt wird zuerst am Tastenkuerzel und erst dann am Text: ⌘N ist in
/// jeder Sprache ein neues Fenster, ⌘, sind die Einstellungen. Der Text
/// bleibt der zweite Weg, fuer Eintraege ohne Kuerzel ("Neues privates
/// Fenster" hat bei manchen Apps keins).
public enum DockCommandFilter {
    public static func isNewCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("New ") || trimmed.hasPrefix("Neu")
    }

    /// Woerter fuer die Einstellungen in den Sprachen, die die Shell selbst
    /// spricht. Alles andere findet das Kuerzel ⌘,.
    public static func isSettingsCommand(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("einstellungen") || trimmed.hasPrefix("settings")
            || trimmed.hasPrefix("preferences")
    }

    /// Gehoert dieser Menuepunkt ins Dock-Menue, und als was?
    ///
    /// `shortcut` ist das Kuerzel des Punktes, `nil` wenn er keines hat.
    public static func kind(title: String, shortcut: MenuShortcut?) -> DockCommandKind? {
        if let shortcut, shortcut.hasCommand, !shortcut.hasControl, !shortcut.hasOption {
            // ⌘, sind ueberall die Einstellungen, ⌘N und ⇧⌘N ein neues
            // Fenster - unabhaengig davon, wie der Eintrag heisst.
            if shortcut.matches(",") { return .settings }
            if shortcut.matches("n") { return .newItem }
        }
        if isSettingsCommand(title) { return .settings }
        if isNewCommand(title) { return .newItem }
        return nil
    }
}
