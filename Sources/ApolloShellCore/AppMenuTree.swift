import Foundation

public struct AXMenuEntry: Equatable, Sendable {
    public var title: String
    public var enabled: Bool
    public var commandCharacter: String
    public var commandModifiers: Int
    public var commandGlyph: Int
    public var mark: String
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

public struct AXMenuStep: Equatable, Sendable {
    public let title: String
    public let index: Int

    public init(title: String, index: Int) {
        self.title = title
        self.index = index
    }

    public func resolve(in titles: [String]) -> Int? {
        if titles.indices.contains(index), titles[index] == title { return index }
        return titles.firstIndex(of: title)
    }
}

public struct MenuModifiers: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = MenuModifiers(rawValue: 1 << 0)
    public static let option = MenuModifiers(rawValue: 1 << 1)
    public static let shift = MenuModifiers(rawValue: 1 << 2)
    public static let command = MenuModifiers(rawValue: 1 << 3)

    public init(accessibility raw: Int) {
        var set: MenuModifiers = raw & 8 == 0 ? .command : []
        if raw & 1 != 0 { set.insert(.shift) }
        if raw & 2 != 0 { set.insert(.option) }
        if raw & 4 != 0 { set.insert(.control) }
        self = set
    }

    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") + (contains(.shift) ? "⇧" : "")
            + (contains(.command) ? "⌘" : "")
    }
}

public struct AppMenuShortcut: Equatable, Sendable {
    public var modifiers: MenuModifiers
    public var key: String
    public var keyEquivalent: String

    public init(modifiers: MenuModifiers, key: String, keyEquivalent: String) {
        self.modifiers = modifiers
        self.key = key
        self.keyEquivalent = keyEquivalent
    }

    public var display: String { modifiers.symbols + key }

    public static func from(character: String, modifiers: Int, glyph: Int) -> AppMenuShortcut? {
        let set = MenuModifiers(accessibility: modifiers)
        if glyph != 0, let special = glyphs[glyph] {
            return AppMenuShortcut(modifiers: set, key: special.key, keyEquivalent: special.equivalent)
        }
        guard let scalar = character.unicodeScalars.first else { return nil }
        if let special = characters[scalar.value] {
            return AppMenuShortcut(modifiers: set, key: special.key, keyEquivalent: special.equivalent)
        }
        if (0xF704...0xF726).contains(scalar.value) {
            return AppMenuShortcut(modifiers: set, key: "F\(scalar.value - 0xF704 + 1)", keyEquivalent: character)
        }
        guard scalar.value >= 0x20 else { return nil }
        return AppMenuShortcut(modifiers: set, key: character.uppercased(), keyEquivalent: character.lowercased())
    }

    private typealias Special = (key: String, equivalent: String)

    private static let glyphs: [Int: Special] = {
        var table: [Int: Special] = [
            0x02: ("⇥", "\t"), 0x03: ("⇤", "\u{19}"), 0x04: ("⌤", "\u{3}"), 0x09: ("Space", " "),
            0x0A: ("⌦", "\u{F728}"), 0x0B: ("↩", "\r"), 0x0D: ("↩", "\r"), 0x17: ("⌫", "\u{8}"),
            0x1B: ("⎋", "\u{1B}"), 0x1C: ("⌧", "\u{F739}"), 0x62: ("⇞", "\u{F72C}"), 0x64: ("←", "\u{F702}"),
            0x65: ("→", "\u{F703}"), 0x66: ("↖", "\u{F729}"), 0x68: ("↑", "\u{F700}"), 0x69: ("↘", "\u{F72B}"),
            0x6A: ("↓", "\u{F701}"), 0x6B: ("⇟", "\u{F72D}"),
        ]
        let fKeys = Array(0x6F...0x7A) + Array(0x87...0x89) + Array(0x8F...0x92)
        for (offset, glyph) in fKeys.enumerated() {
            table[glyph] = ("F\(offset + 1)", String(UnicodeScalar(0xF704 + offset)!))
        }
        return table
    }()

    private static let characters: [UInt32: Special] = [
        0x03: ("⌤", "\u{3}"), 0x08: ("⌫", "\u{8}"), 0x09: ("⇥", "\t"), 0x0D: ("↩", "\r"), 0x1B: ("⎋", "\u{1B}"),
        0x20: ("Space", " "), 0x7F: ("⌫", "\u{8}"), 0xF700: ("↑", "\u{F700}"), 0xF701: ("↓", "\u{F701}"),
        0xF702: ("←", "\u{F702}"), 0xF703: ("→", "\u{F703}"), 0xF728: ("⌦", "\u{F728}"), 0xF729: ("↖", "\u{F729}"),
        0xF72B: ("↘", "\u{F72B}"), 0xF72C: ("⇞", "\u{F72C}"), 0xF72D: ("⇟", "\u{F72D}"),
    ]
}

public struct AppMenuNode: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case none, check, mixed }

    public let title: String
    public let enabled: Bool
    public let mark: Mark
    public let shortcut: AppMenuShortcut?
    public let modifiers: MenuModifiers
    public let isSeparator: Bool
    public let isAlternate: Bool
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

public enum AppMenuTree {
    public static let maximumDepth = 8

    public static func nodes(from entries: [AXMenuEntry], path: [AXMenuStep] = [], depth: Int = 0) -> [AppMenuNode] {
        guard depth < maximumDepth else { return [] }
        let alternate = alternates(entries)
        var result: [AppMenuNode] = []
        for (index, entry) in entries.enumerated() {
            let own = path + [AXMenuStep(title: entry.title, index: index)]
            if isSeparator(entry) {
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
        while result.last?.isSeparator == true { result.removeLast() }
        return result
    }

    public static func isSeparator(_ entry: AXMenuEntry) -> Bool {
        entry.title.trimmingCharacters(in: .whitespaces).isEmpty && !entry.hasSubmenu
    }

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

public enum AppMenuCollapse {
    public struct Fit: Equatable, Sendable {
        public var shown: Int
        public var overflow: Bool

        public init(shown: Int, overflow: Bool) {
            self.shown = shown
            self.overflow = overflow
        }
    }

    public static func fit(available: Double, lead: Double, titles: [Double], overflow: Double,
                           spacing: Double) -> Fit {
        let all = lead + titles.reduce(0) { $0 + $1 + spacing }
        if all <= available + 0.5 { return Fit(shown: titles.count, overflow: false) }
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
