import ApolloShellCore

public struct KeyChord: Sendable, Hashable {
    public var modifiers: HotKeyModifiers
    public var key: String
    public var keyCode: UInt32

    public init(modifiers: HotKeyModifiers, key: String, keyCode: UInt32) {
        self.modifiers = modifiers
        self.key = key
        self.keyCode = keyCode
    }

    public static func parse(_ text: String) -> KeyChord? {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, !last.isEmpty else { return nil }
        var modifiers: HotKeyModifiers = []
        for part in parts.dropLast() {
            guard let flags = modifierNames[part] else { return nil }
            modifiers.formUnion(flags)
        }
        let key = keyAliases[last] ?? last
        guard let code = keyCodes[key] else { return nil }
        return KeyChord(modifiers: modifiers, key: key, keyCode: code)
    }

    public var canonical: String {
        var names: [String] = []
        if modifiers == .hyper {
            names = ["hyper"]
        } else {
            if modifiers.contains(.control) { names.append("ctrl") }
            if modifiers.contains(.option) { names.append("alt") }
            if modifiers.contains(.shift) { names.append("shift") }
            if modifiers.contains(.command) { names.append("cmd") }
        }
        return (names + [key]).joined(separator: "+")
    }

    public var hotKey: HotKey {
        HotKey(keyCode: keyCode, modifiers: modifiers)
    }

    public var display: String {
        let label: String
        if key.count == 1 {
            label = key.uppercased()
        } else if let symbol = Self.punctuation[key] {
            label = symbol
        } else {
            label = HotKeyKey.name(for: keyCode) ?? key
        }
        return modifiers.symbols + label
    }

    static let modifierNames: [String: HotKeyModifiers] = [
        "cmd": .command,
        "ctrl": .control,
        "alt": .option,
        "opt": .option,
        "option": .option,
        "shift": .shift,
        "hyper": .hyper,
    ]

    static let keyAliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete",
        "=": "equal", "-": "minus", ",": "comma", ".": "period", "/": "slash",
        ";": "semicolon", "'": "quote", "`": "grave", "\\": "backslash",
        "leftbracket": "[", "rightbracket": "]",
    ]

    static let punctuation: [String: String] = [
        "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/",
        "semicolon": ";", "quote": "'", "grave": "`", "backslash": "\\",
    ]

    static let keyCodes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "equal": 0x18,
        "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "l": 0x25, "j": 0x26, "quote": 0x27, "k": 0x28,
        "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B, "slash": 0x2C, "n": 0x2D, "m": 0x2E,
        "period": 0x2F, "tab": 0x30, "space": 0x31, "grave": 0x32, "delete": 0x33, "escape": 0x35,
        "forward-delete": 0x75, "keypad-enter": 0x4C, "home": 0x73, "end": 0x77, "pageup": 0x74,
        "pagedown": 0x79, "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
        "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B,
        "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
    ]
}
