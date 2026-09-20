import Foundation

// Global keyboard shortcuts: model, defaults, display and the rules for
// recording. Registering happens in the app (GlobalHotKey, Carbon); only what
// can be checked without a user interface stands here.

/// The modifier keys of a shortcut. The bits are the same as Carbon's
/// `cmdKey`, `shiftKey`, `optionKey` and `controlKey` (HIToolbox): so the
/// value goes to RegisterEventHotKey unchanged, and ApolloShellCore needs no
/// Carbon. The tests compare against the real constants.
///
/// In settings.json as names ("option", "command" ...), not as a number -
/// whoever reads the file by hand should not have to count bits.
public struct HotKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 8)
    public static let shift = HotKeyModifiers(rawValue: 1 << 9)
    public static let option = HotKeyModifiers(rawValue: 1 << 11)
    public static let control = HotKeyModifiers(rawValue: 1 << 12)
    /// All four together (⌃⌥⇧⌘) - that is what Karabiner and friends call it.
    public static let hyper: HotKeyModifiers = [.control, .option, .shift, .command]

    /// The order as in Apple's menus: ⌃⌥⇧⌘.
    private static let ordered: [(flag: HotKeyModifiers, symbol: String, name: String)] = [
        (.control, "⌃", "control"),
        (.option, "⌥", "option"),
        (.shift, "⇧", "shift"),
        (.command, "⌘", "command"),
    ]

    /// "⌃⌥⇧⌘" - only the ones that are set, in Apple's order.
    public var symbols: String {
        Self.ordered.filter { contains($0.flag) }.map(\.symbol).joined()
    }

    /// The names for settings.json, in the same order.
    public var names: [String] {
        Self.ordered.filter { contains($0.flag) }.map(\.name)
    }

    /// Unknown names (a typo, a later version) fall away.
    public init(names: [String]) {
        var flags: HotKeyModifiers = []
        for name in names {
            if let entry = Self.ordered.first(where: { $0.name == name.lowercased() }) { flags.insert(entry.flag) }
        }
        self = flags
    }
}

extension HotKeyModifiers: Codable {
    public init(from decoder: any Decoder) throws {
        let names = try decoder.singleValueContainer().decode([String].self)
        self.init(names: names)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(names)
    }
}

/// One keyboard shortcut: the virtual key code (Carbon `kVK_…`, the place of
/// the key, not its character) plus modifier keys.
public struct HotKey: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: HotKeyModifiers

    public init(keyCode: UInt32, modifiers: HotKeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers
    }

    /// Key codes go up to 127. Anything else is broken and counts as missing
    /// - then the default holds for this action.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let code = try c.decode(Int.self, forKey: .keyCode)
        guard (0..<128).contains(code) else {
            throw DecodingError.dataCorruptedError(forKey: .keyCode, in: c, debugDescription: "Tastencode ausserhalb 0...127")
        }
        keyCode = UInt32(code)
        modifiers = (try? c.decodeIfPresent(HotKeyModifiers.self, forKey: .modifiers)) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Int(keyCode), forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
    }

    /// "⌥Space", "⌃⌥⇧⌘D", "F20". `keyName`: the character of the key on the
    /// current keyboard layout (the app asks macOS for it) - without it the US
    /// label out of `HotKeyKey` holds.
    public func display(keyName: String? = nil) -> String {
        modifiers.symbols + (keyName ?? HotKeyKey.name(for: keyCode) ?? String(localized: "Key \(keyCode)"))
    }
}

/// Virtual key codes and their labels. The values are Carbon's `kVK_…`
/// (Events.h); the tests check them against the real constants.
///
/// Letters, digits and punctuation carry the US label here. On other layouts
/// a different character lies there (Z and Y are swapped on German
/// keyboards); so the app asks the current layout for exactly these keys
/// (`isCharacterKey`).
public enum HotKeyKey {
    public static let space: UInt32 = 0x31
    public static let escape: UInt32 = 0x35
    public static let delete: UInt32 = 0x33
    public static let forwardDelete: UInt32 = 0x75
    public static let d: UInt32 = 0x02
    public static let u: UInt32 = 0x20
    public static let comma: UInt32 = 0x2B
    public static let f20: UInt32 = 0x5A

    private static let characters: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "E",
        0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K",
        0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`",
    ]

    /// The way Apple shows them in menus; the space bar as "Space".
    private static let special: [UInt32: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋", 0x75: "⌦",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟", 0x72: "Hilfe",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
        0x4C: "⌅", 0x47: "⌧", 0x41: "Num .", 0x43: "Num *", 0x45: "Num +", 0x4B: "Num /",
        0x4E: "Num -", 0x51: "Num =", 0x52: "Num 0", 0x53: "Num 1", 0x54: "Num 2", 0x55: "Num 3",
        0x56: "Num 4", 0x57: "Num 5", 0x58: "Num 6", 0x59: "Num 7", 0x5B: "Num 8", 0x5C: "Num 9",
    ]

    /// F1 to F20. On laptops the topmost keys send brightness and sound
    /// instead of F keys without fn; Karabiner and friends like to put F13-F20
    /// on free keys - so F keys may stand entirely on their own.
    private static let function: [UInt32: Int] = [
        0x7A: 1, 0x78: 2, 0x63: 3, 0x76: 4, 0x60: 5, 0x61: 6, 0x62: 7, 0x64: 8, 0x65: 9, 0x6D: 10,
        0x67: 11, 0x6F: 12, 0x69: 13, 0x6B: 14, 0x71: 15, 0x6A: 16, 0x40: 17, 0x4F: 18, 0x50: 19, 0x5A: 20,
    ]

    public static func name(for keyCode: UInt32) -> String? {
        if let number = function[keyCode] { return "F\(number)" }
        return characters[keyCode] ?? special[keyCode]
    }

    /// A key with a character that depends on the layout.
    public static func isCharacterKey(_ keyCode: UInt32) -> Bool {
        characters[keyCode] != nil
    }

    public static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        function[keyCode] != nil
    }
}

/// What can be opened with a shortcut.
public enum HotKeyAction: String, CaseIterable, Identifiable, Sendable {
    case launcher, dashboard, utilities, nexus

    public var id: Self { self }

    /// As a `String`, not a `LocalizedStringKey`: it runs through variables all
    /// the way to `Text(action.title)` (see the contract).
    public var title: String {
        switch self {
        case .launcher: "Launcher"
        case .dashboard: "Dashboard"
        case .utilities: String(localized: "Control Centre")
        case .nexus: "Nexus"
        }
    }

    public var subtitle: String {
        switch self {
        case .launcher: String(localized: "Search and open apps")
        case .dashboard: String(localized: "Weather, calendar, media, performance")
        case .utilities: String(localized: "Keep Awake, sound and quick toggles")
        case .nexus: String(localized: "This settings window")
        }
    }

    public var symbol: String {
        switch self {
        case .launcher: "magnifyingglass"
        case .dashboard: "square.grid.2x2.fill"
        case .utilities: "slider.horizontal.3"
        case .nexus: "gearshape.fill"
        }
    }
}

/// The four shortcuts in settings.json (section "hotKeys"). `nil` = no
/// shortcut (`null` in the file): the action then only goes through the bar.
///
/// Two defaults, because there are two kinds of users:
/// - `firstLaunch` for fresh installations. ⌥Space for the launcher, as with
///   Alfred and Raycast; Spotlight stays on ⌘Space. The panels on ⌃⌥ instead
///   of ⌥ alone: ⌥ with a letter or punctuation key types a character, and a
///   global shortcut swallows it. Measured with UCKeyTranslate (14.09.,
///   macOS 26.6): ⌥U is the umlaut key (a dead key) on US, ABC, British and
///   German, and ⌥, types « on Swiss and French layouts. ⌃⌥ gives a character
///   on no layout.
/// - `existingInstall`: whoever has a settings.json without this section
///   already keeps the shortcuts from before (F20 and Hyper+D/U/,).
public struct HotKeySettings: Codable, Equatable, Sendable {
    public var launcher: HotKey?
    public var dashboard: HotKey?
    public var utilities: HotKey?
    public var nexus: HotKey?

    public init(launcher: HotKey? = nil, dashboard: HotKey? = nil, utilities: HotKey? = nil, nexus: HotKey? = nil) {
        self.launcher = launcher
        self.dashboard = dashboard
        self.utilities = utilities
        self.nexus = nexus
    }

    public static let firstLaunch = HotKeySettings(
        launcher: HotKey(keyCode: HotKeyKey.space, modifiers: .option),
        dashboard: HotKey(keyCode: HotKeyKey.d, modifiers: [.control, .option]),
        utilities: HotKey(keyCode: HotKeyKey.u, modifiers: [.control, .option]),
        nexus: HotKey(keyCode: HotKeyKey.comma, modifiers: [.control, .option])
    )

    public static let existingInstall = HotKeySettings(
        launcher: HotKey(keyCode: HotKeyKey.f20),
        dashboard: HotKey(keyCode: HotKeyKey.d, modifiers: .hyper),
        utilities: HotKey(keyCode: HotKeyKey.u, modifiers: .hyper),
        nexus: HotKey(keyCode: HotKeyKey.comma, modifiers: .hyper)
    )

    public subscript(action: HotKeyAction) -> HotKey? {
        get {
            switch action {
            case .launcher: launcher
            case .dashboard: dashboard
            case .utilities: utilities
            case .nexus: nexus
            }
        }
        set {
            switch action {
            case .launcher: launcher = newValue
            case .dashboard: dashboard = newValue
            case .utilities: utilities = newValue
            case .nexus: nexus = newValue
            }
        }
    }

    /// Which other action has this shortcut already.
    public func action(using key: HotKey, except excluded: HotKeyAction? = nil) -> HotKeyAction? {
        HotKeyAction.allCases.first { $0 != excluded && self[$0] == key }
    }

    private enum CodingKeys: String, CodingKey {
        case launcher, dashboard, utilities, nexus

        var action: HotKeyAction {
            switch self {
            case .launcher: .launcher
            case .dashboard: .dashboard
            case .utilities: .utilities
            case .nexus: .nexus
            }
        }
    }

    /// Per action: when the key is missing or unreadable, the default for
    /// fresh installations holds (the section comes out of this version
    /// anyway); `null` means "no shortcut" on purpose.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var result = HotKeySettings()
        for key in [CodingKeys.launcher, .dashboard, .utilities, .nexus] {
            let fallback = Self.firstLaunch[key.action]
            if !c.contains(key) {
                result[key.action] = fallback
            } else if (try? c.decodeNil(forKey: key)) == true {
                result[key.action] = nil
            } else {
                result[key.action] = (try? c.decode(HotKey.self, forKey: key)) ?? fallback
            }
        }
        self = result
    }

    /// Write a missing shortcut as `null` too: if the key were missing, the
    /// default would hold again on the next read.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.launcher, .dashboard, .utilities, .nexus] {
            if let hotKey = self[key.action] {
                try c.encode(hotKey, forKey: key)
            } else {
                try c.encodeNil(forKey: key)
            }
        }
    }
}

// MARK: - Recording

/// What a key press in the recording field does.
public enum HotKeyRecording: Equatable, Sendable {
    case record(HotKey)
    /// ⎋ without a modifier: cancel, change nothing.
    case cancel
    /// ⌫ or ⌦ without a modifier: remove the shortcut.
    case clear
    case rejected(HotKeyRejection)

    /// The rules as in System Settings: without a modifier only F keys
    /// (otherwise the key would be missing while typing), ⇧ alone is not
    /// enough (otherwise there would be no capitals any more).
    public static func evaluate(keyCode: UInt32, modifiers: HotKeyModifiers) -> HotKeyRecording {
        if modifiers.isEmpty {
            if keyCode == HotKeyKey.escape { return .cancel }
            if keyCode == HotKeyKey.delete || keyCode == HotKeyKey.forwardDelete { return .clear }
        }
        if HotKeyKey.isFunctionKey(keyCode) { return .record(HotKey(keyCode: keyCode, modifiers: modifiers)) }
        if modifiers.isEmpty { return .rejected(.needsModifier) }
        if modifiers == .shift { return .rejected(.shiftOnly) }
        return .record(HotKey(keyCode: keyCode, modifiers: modifiers))
    }
}

public enum HotKeyRejection: Equatable, Sendable {
    case needsModifier, shiftOnly
}

/// A notice about a valid but tricky shortcut. It holds all the same -
/// whoever switched Spotlight off, say, should be able to take ⌘Space.
public enum HotKeyWarning: Equatable, Sendable {
    /// macOS or practically every app uses it already.
    case system(String)
    /// ⌥ (maybe with ⇧) and a character key: types a special character.
    case typesCharacters
}

public enum HotKeyAdvice {
    /// The well-known shortcuts of macOS (Keyboard > Keyboard Shortcuts) and
    /// the ones every app has. No claim to completeness - whatever another app
    /// has registered already is reported by the registration itself.
    private static let system: [HotKey: String] = {
        let cmd = HotKeyModifiers.command, opt = HotKeyModifiers.option
        let ctrl = HotKeyModifiers.control, shift = HotKeyModifiers.shift
        // The names run as data all the way into HotKeyText.warning(_:) -
        // there they are put into a sentence (String, not
        // LocalizedStringKey; see the contract).
        let entries: [(UInt32, HotKeyModifiers, String)] = [
            (HotKeyKey.space, cmd, "Spotlight"),
            (HotKeyKey.space, [cmd, opt], String(localized: "Finder Search Window")),
            (HotKeyKey.space, ctrl, String(localized: "Previous Input Source")),
            (HotKeyKey.space, [ctrl, opt], String(localized: "Next Input Source")),
            (HotKeyKey.space, [ctrl, cmd], String(localized: "Emoji & Symbols")),
            (0x30, cmd, String(localized: "App Switcher")),
            (0x32, cmd, String(localized: "Switch Windows Within the App")),
            (0x14, [cmd, shift], String(localized: "Screenshot")),
            (0x15, [cmd, shift], String(localized: "Screenshot")),
            (0x17, [cmd, shift], String(localized: "Screenshot and Screen Recording")),
            (0x0C, [ctrl, cmd], String(localized: "Lock Screen")),
            (HotKeyKey.d, [opt, cmd], String(localized: "Show and Hide the Dock")),
            (HotKeyKey.escape, [opt, cmd], String(localized: "Force Quit")),
            (0x7E, ctrl, "Mission Control"),
            (0x7D, ctrl, "App-Exposé"),
            (0x7B, ctrl, String(localized: "Space to the Left")),
            (0x7C, ctrl, String(localized: "Space to the Right")),
            (0x0C, cmd, String(localized: "Quit, in Any App")),
            (0x0D, cmd, String(localized: "Close Window, in Any App")),
            (0x04, cmd, String(localized: "Hide, in Any App")),
            (0x2E, cmd, String(localized: "Minimize, in Any App")),
            (HotKeyKey.comma, cmd, String(localized: "Settings, in Any App")),
            (0x08, cmd, String(localized: "Copy, in Any App")),
            (0x09, cmd, String(localized: "Paste, in Any App")),
            (0x07, cmd, String(localized: "Cut, in Any App")),
            (0x06, cmd, String(localized: "Undo, in Any App")),
            (0x00, cmd, String(localized: "Select All, in Any App")),
        ]
        return Dictionary(entries.map { (HotKey(keyCode: $0.0, modifiers: $0.1), $0.2) }, uniquingKeysWith: { first, _ in first })
    }()

    public static func warning(for key: HotKey) -> HotKeyWarning? {
        if let name = system[key] { return .system(name) }
        if key.modifiers.contains(.option), key.modifiers.isSubset(of: [.option, .shift]),
           HotKeyKey.isCharacterKey(key.keyCode) {
            return .typesCharacters
        }
        return nil
    }
}

/// The texts around the shortcuts (Nexus and the introduction).
public enum HotKeyText {
    public static func rejection(_ reason: HotKeyRejection) -> String {
        switch reason {
        case .needsModifier: String(localized: "Please use ⌘, ⌥ or ⌃ – otherwise the key would be missing while typing. Only F-keys work alone.")
        case .shiftOnly: String(localized: "⇧ alone is not enough – otherwise capital letters could no longer be typed.")
        }
    }

    public static func taken(by action: HotKeyAction) -> String {
        String(localized: "Already assigned to “\(action.title)”.")
    }

    public static func warning(_ warning: HotKeyWarning) -> String {
        switch warning {
        case .system(let name):
            String(localized: "macOS already uses this shortcut: \(name). Only useful if it's turned off there.")
        case .typesCharacters:
            String(localized: "⌥ with this key types a special character (depending on the keyboard, e.g. umlauts, « or ∂). As long as the shortcut is active, it can no longer be typed this way.")
        }
    }

    /// The registration was turned down. `alreadyTaken`: Carbon reports
    /// eventHotKeyExistsErr - another app registered it first.
    public static func registrationFailed(alreadyTaken: Bool, status: Int32) -> String {
        alreadyTaken
            ? String(localized: "Not active: Another app already uses this shortcut.")
            : String(localized: "Not active: macOS declined the shortcut (error \(status, format: .number.grouping(.never))).")
    }

    public static let recordingPrompt = String(localized: "Press a shortcut…")
    public static let recordingHelp = String(localized: "⎋ cancels, ⌫ removes the shortcut.")
    public static let none = String(localized: "No Shortcut")
}
