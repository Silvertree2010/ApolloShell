import Foundation

// The menus of other apps, drawn by the shell (spec topbar.md, "Etappe 5"):
// the frontmost app's menu bar and the menus of other apps' status items.
// The app layer reads the raw entries through accessibility (`AXMenuEntry`);
// what becomes of them - separators, ticks, shortcuts, alternates - is
// decided here, so it can be checked without an app to ask.

// MARK: - Raw entries

/// One menu entry the way accessibility reports it - raw, without
/// interpretation. The attribute names are Apple's (`AXMenuItemCmdChar` and
/// friends), measured 23.09. on Finder and TextEdit in the VM.
public struct AXMenuEntry: Equatable, Sendable {
    public var title: String
    public var enabled: Bool
    /// `AXMenuItemCmdChar`: "N", "\u{8}" for delete; empty without a shortcut.
    public var commandCharacter: String
    /// `AXMenuItemCmdModifiers`: shift 1, option 2, control 4, "no command" 8
    /// (Carbon's kMenu*Modifier). 0 means command alone.
    public var commandModifiers: Int
    /// `AXMenuItemCmdGlyph`: Carbon's glyph number for keys without a
    /// printable character (23 = delete left); 0 without one.
    public var commandGlyph: Int
    /// `AXMenuItemMarkChar`: "✓" for a tick, "-" for mixed; empty without.
    public var mark: String
    /// It has a submenu (an AXMenu child); `children` are its entries.
    public var hasSubmenu: Bool
    public var children: [AXMenuEntry]

    public init(title: String, enabled: Bool = true, commandCharacter: String = "", commandModifiers: Int = 0,
                commandGlyph: Int = 0, mark: String = "", hasSubmenu: Bool = false, children: [AXMenuEntry] = []) {
        self.title = title
        self.enabled = enabled
        self.commandCharacter = commandCharacter
        self.commandModifiers = commandModifiers
        self.commandGlyph = commandGlyph
        self.mark = mark
        self.hasSubmenu = hasSubmenu || !children.isEmpty
        self.children = children
    }
}

/// One step on the way to an entry: its title and its place in its menu, as
/// in `DockMenuStep` - titles repeat (two recent files of the same name), so
/// the place counts first and the title only confirms it.
public struct AXMenuStep: Equatable, Sendable {
    public let title: String
    public let index: Int

    public init(title: String, index: Int) {
        self.title = title
        self.index = index
    }

    /// Where this step is now among `titles`: at its old place while the
    /// title there still fits, otherwise the first entry of that title (the
    /// menu changed since it was read), `nil` when it is gone.
    public func resolve(in titles: [String]) -> Int? {
        if titles.indices.contains(index), titles[index] == title { return index }
        return titles.firstIndex(of: title)
    }
}

// MARK: - Shortcuts

/// The modifier keys of a shortcut, in the order menus show them.
public struct MenuModifiers: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = MenuModifiers(rawValue: 1 << 0)
    public static let option = MenuModifiers(rawValue: 1 << 1)
    public static let shift = MenuModifiers(rawValue: 1 << 2)
    public static let command = MenuModifiers(rawValue: 1 << 3)

    /// From `AXMenuItemCmdModifiers`: command is there unless bit 8 says
    /// "no command".
    public init(accessibility raw: Int) {
        var set: MenuModifiers = raw & 8 == 0 ? .command : []
        if raw & 1 != 0 { set.insert(.shift) }
        if raw & 2 != 0 { set.insert(.option) }
        if raw & 4 != 0 { set.insert(.control) }
        self = set
    }

    /// "⌃⌥⇧⌘", the order of Apple's menus.
    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "")
            + (contains(.command) ? "⌘" : "")
    }
}

/// A keyboard shortcut of a menu entry.
public struct AppMenuShortcut: Equatable, Sendable {
    public var modifiers: MenuModifiers
    /// What stands after the modifier symbols: "N", "⌫", "F5", "Space".
    public var key: String
    /// For `NSMenuItem.keyEquivalent`: a lower-case character or AppKit's
    /// function key character, so the menu draws the shortcut itself.
    public var keyEquivalent: String

    public init(modifiers: MenuModifiers, key: String, keyEquivalent: String) {
        self.modifiers = modifiers
        self.key = key
        self.keyEquivalent = keyEquivalent
    }

    /// "⇧⌘N".
    public var display: String { modifiers.symbols + key }

    /// From the three attributes; `nil` when the entry has no key (the
    /// modifiers alone make no shortcut).
    public static func from(character: String, modifiers: Int, glyph: Int) -> AppMenuShortcut? {
        let set = MenuModifiers(accessibility: modifiers)
        if glyph != 0, let special = glyphs[glyph] {
            return AppMenuShortcut(modifiers: set, key: special.key, keyEquivalent: special.equivalent)
        }
        guard let scalar = character.unicodeScalars.first else { return nil }
        if let special = characters[scalar.value] {
            return AppMenuShortcut(modifiers: set, key: special.key, keyEquivalent: special.equivalent)
        }
        // F1 to F35 (AppKit's NSF1FunctionKey onwards).
        if (0xF704...0xF726).contains(scalar.value) {
            return AppMenuShortcut(modifiers: set, key: "F\(scalar.value - 0xF704 + 1)", keyEquivalent: character)
        }
        // A control character nobody names: better no shortcut than a box.
        guard scalar.value >= 0x20 else { return nil }
        return AppMenuShortcut(modifiers: set, key: character.uppercased(), keyEquivalent: character.lowercased())
    }

    private typealias Special = (key: String, equivalent: String)

    /// Carbon's menu glyphs (Menus.h, kMenu*Glyph) for keys without a
    /// printable character, with AppKit's character for the same key.
    private static let glyphs: [Int: Special] = {
        var table: [Int: Special] = [
            0x02: ("⇥", "\t"), 0x03: ("⇤", "\u{19}"), 0x04: ("⌤", "\u{3}"), 0x09: ("Space", " "),
            0x0A: ("⌦", "\u{F728}"), 0x0B: ("↩", "\r"), 0x0D: ("↩", "\r"), 0x17: ("⌫", "\u{8}"),
            0x1B: ("⎋", "\u{1B}"), 0x1C: ("⌧", "\u{F739}"), 0x62: ("⇞", "\u{F72C}"), 0x64: ("←", "\u{F702}"),
            0x65: ("→", "\u{F703}"), 0x66: ("↖", "\u{F729}"), 0x68: ("↑", "\u{F700}"), 0x69: ("↘", "\u{F72B}"),
            0x6A: ("↓", "\u{F701}"), 0x6B: ("⇟", "\u{F72D}"),
        ]
        // F1-F12 lie at 0x6F-0x7A, F13-F15 at 0x87-0x89, F16-F19 at 0x8F-0x92.
        let fKeys = Array(0x6F...0x7A) + Array(0x87...0x89) + Array(0x8F...0x92)
        for (offset, glyph) in fKeys.enumerated() {
            table[glyph] = ("F\(offset + 1)", String(UnicodeScalar(0xF704 + offset)!))
        }
        return table
    }()

    /// Characters AppKit uses for keys that have no letter.
    private static let characters: [UInt32: Special] = [
        0x03: ("⌤", "\u{3}"), 0x08: ("⌫", "\u{8}"), 0x09: ("⇥", "\t"), 0x0D: ("↩", "\r"), 0x1B: ("⎋", "\u{1B}"),
        0x20: ("Space", " "), 0x7F: ("⌫", "\u{8}"), 0xF700: ("↑", "\u{F700}"), 0xF701: ("↓", "\u{F701}"),
        0xF702: ("←", "\u{F702}"), 0xF703: ("→", "\u{F703}"), 0xF728: ("⌦", "\u{F728}"), 0xF729: ("↖", "\u{F729}"),
        0xF72B: ("↘", "\u{F72B}"), 0xF72C: ("⇞", "\u{F72C}"), 0xF72D: ("⇟", "\u{F72D}"),
    ]
}

// MARK: - Finished entries

/// An entry of our menu, ready for an NSMenuItem.
public struct AppMenuNode: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case none, check, mixed }

    public let title: String
    public let enabled: Bool
    public let mark: Mark
    public let shortcut: AppMenuShortcut?
    /// The entry's modifiers even without a key: an alternate without a
    /// shortcut ("Always Open With") differs from its primary only by them.
    public let modifiers: MenuModifiers
    public let isSeparator: Bool
    /// Shows in place of the entry before it while Option is held (see
    /// `AppMenuTree.alternates`).
    public let isAlternate: Bool
    /// The way to this entry in the other app's menu, to press it there.
    public let path: [AXMenuStep]
    public let children: [AppMenuNode]
    public let hasSubmenu: Bool

    public init(title: String, enabled: Bool = true, mark: Mark = .none, shortcut: AppMenuShortcut? = nil,
                modifiers: MenuModifiers = .command, isSeparator: Bool = false, isAlternate: Bool = false,
                path: [AXMenuStep] = [], children: [AppMenuNode] = [], hasSubmenu: Bool = false) {
        self.title = title
        self.enabled = enabled
        self.mark = mark
        self.shortcut = shortcut
        self.modifiers = modifiers
        self.isSeparator = isSeparator
        self.isAlternate = isAlternate
        self.path = path
        self.children = children
        self.hasSubmenu = hasSubmenu || !children.isEmpty
    }
}

/// Makes our menu out of what accessibility reports.
public enum AppMenuTree {
    /// Deeper than this nobody nests menus; a guard against a cycle.
    public static let maximumDepth = 8

    /// - Parameter path: the steps up to the menu these entries stand in;
    ///   every node's own path is that plus its place here.
    public static func nodes(from entries: [AXMenuEntry], path: [AXMenuStep] = [], depth: Int = 0) -> [AppMenuNode] {
        guard depth < maximumDepth else { return [] }
        let alternate = alternates(entries)
        var result: [AppMenuNode] = []
        for (index, entry) in entries.enumerated() {
            let own = path + [AXMenuStep(title: entry.title, index: index)]
            if isSeparator(entry) {
                // No separator at the top, none twice in a row.
                if let last = result.last, !last.isSeparator { result.append(AppMenuNode(title: "", isSeparator: true, path: own)) }
                continue
            }
            result.append(AppMenuNode(
                title: entry.title, enabled: entry.enabled, mark: mark(entry.mark),
                shortcut: AppMenuShortcut.from(character: entry.commandCharacter, modifiers: entry.commandModifiers,
                                            glyph: entry.commandGlyph),
                modifiers: MenuModifiers(accessibility: entry.commandModifiers),
                isAlternate: alternate[index], path: own,
                children: entry.hasSubmenu ? nodes(from: entry.children, path: own, depth: depth + 1) : [],
                hasSubmenu: entry.hasSubmenu
            ))
        }
        // None at the bottom either.
        while result.last?.isSeparator == true { result.removeLast() }
        return result
    }

    /// Apple reports a separator as an entry without a title and without a
    /// submenu. Custom views (Finder's tag colours) look the same - they can
    /// not be drawn from outside anyway, so they fall away like one.
    public static func isSeparator(_ entry: AXMenuEntry) -> Bool {
        entry.title.trimmingCharacters(in: .whitespaces).isEmpty && !entry.hasSubmenu
    }

    /// Which entries are Option alternates of the one before them.
    ///
    /// Accessibility lists alternates as plain entries and marks them in no
    /// way (measured 23.09.: `AXMenuItemPrimaryUIElement` points at the entry
    /// itself, frames are zero while closed). AppKit's rule for an alternate
    /// is "same key as the entry before, other modifiers" - but that also
    /// fits Finder's "New Folder" (⇧⌘N) after "New Finder Window" (⌘N), which
    /// both show. So only what Option adds counts: same key (or both none),
    /// Option held where the primary has none. That catches Close All,
    /// Show Inspector, Always Open With, Delete Immediately; an alternate on
    /// Control ("Get Summary Info") stays a line of its own - one line too
    /// many rather than one missing.
    public static func alternates(_ entries: [AXMenuEntry]) -> [Bool] {
        var result = Array(repeating: false, count: entries.count)
        var primary: Int?
        for (index, entry) in entries.enumerated() {
            if isSeparator(entry) {
                primary = nil
                continue
            }
            if let p = primary, sameKey(entries[p], entry) {
                let base = MenuModifiers(accessibility: entries[p].commandModifiers)
                let own = MenuModifiers(accessibility: entry.commandModifiers)
                if own.contains(.option), !base.contains(.option), own != base {
                    result[index] = true
                    continue
                }
            }
            primary = index
        }
        return result
    }

    private static func sameKey(_ a: AXMenuEntry, _ b: AXMenuEntry) -> Bool {
        a.commandCharacter.uppercased() == b.commandCharacter.uppercased() && a.commandGlyph == b.commandGlyph
    }

    private static func mark(_ raw: String) -> AppMenuNode.Mark {
        switch raw.trimmingCharacters(in: .whitespaces) {
        case "": .none
        case "-", "–", "−": .mixed
        default: .check
        }
    }
}

// MARK: - Making room

/// How many of the app's menu titles fit next to its name, the rest going
/// into a "…" menu - as Apple's menu bar does next to the notch.
public enum AppMenuCollapse {
    public struct Fit: Equatable, Sendable {
        /// The first `shown` titles stand in the bar.
        public var shown: Int
        /// A "…" button holds the others.
        public var overflow: Bool

        public init(shown: Int, overflow: Bool) {
            self.shown = shown
            self.overflow = overflow
        }
    }

    /// - Parameters:
    ///   - lead: the app's name, which always stands.
    ///   - titles: the widths of the menu titles, in order.
    ///   - overflow: the width of the "…" button.
    public static func fit(available: Double, lead: Double, titles: [Double], overflow: Double,
                           spacing: Double) -> Fit {
        let all = lead + titles.reduce(0) { $0 + $1 + spacing }
        if all <= available + 0.5 { return Fit(shown: titles.count, overflow: false) }
        // Everything else counts against the room with the "…" button.
        var used = lead + spacing + overflow
        var shown = 0
        for width in titles {
            guard used + width + spacing <= available + 0.5 else { break }
            used += width + spacing
            shown += 1
        }
        return Fit(shown: shown, overflow: true)
    }
}
