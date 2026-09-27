#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

public enum Command: Sendable, Equatable {
    case focus(Direction)
    case swap(Direction)
    case cycleFocus
    case toggleSplit
    case equalize
    case grow(CGSize)
    case newTerminal
    case toggleGroup
    case cycleTab(Bool)
    case moveTab(Bool)
    case groupApp
    case toggleFloating
    case toggleFullscreen
    case closeWindow
    case workspace(Int)
    case sendToDesktop(Int)
    case scratchpad
    case focusDisplay(Bool)
    case sendToDisplay(Bool)

    public init?(parsing text: String) {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let verb = words.first else { return nil }
        let rest = Array(words.dropFirst())
        func direction() -> Direction? {
            guard rest.count == 1 else { return nil }
            return switch rest[0] {
            case "left", "l": .left
            case "right", "r": .right
            case "up", "u": .up
            case "down", "d": .down
            default: nil
            }
        }
        func number() -> Int? {
            guard rest.count == 1, let n = Int(rest[0]), (1...9).contains(n) else { return nil }
            return n
        }
        func none() -> Bool { rest.isEmpty }
        switch verb {
        case "focus":
            if rest == ["next"] { self = .cycleFocus; return }
            guard let d = direction() else { return nil }
            self = .focus(d)
        case "swap":
            guard let d = direction() else { return nil }
            self = .swap(d)
        case "split" where none(): self = .toggleSplit
        case "equalize" where none(): self = .equalize
        case "grow":
            guard rest.count == 2, let w = Double(rest[0]), let h = Double(rest[1]),
                  abs(w) <= 1, abs(h) <= 1 else { return nil }
            self = .grow(CGSize(width: w, height: h))
        case "terminal" where none(): self = .newTerminal
        case "group" where none(): self = .toggleGroup
        case "tab":
            guard rest.count == 1, ["next", "prev", "previous"].contains(rest[0]) else { return nil }
            self = .cycleTab(rest[0] == "next")
        case "tab-move":
            guard rest.count == 1, ["next", "prev", "previous"].contains(rest[0]) else { return nil }
            self = .moveTab(rest[0] == "next")
        case "group-app" where none(): self = .groupApp
        case "float" where none(): self = .toggleFloating
        case "fullscreen" where none(): self = .toggleFullscreen
        case "close" where none(): self = .closeWindow
        case "desktop":
            guard let n = number() else { return nil }
            self = .workspace(n)
        case "send":
            guard let n = number() else { return nil }
            self = .sendToDesktop(n)
        case "scratchpad" where none(): self = .scratchpad
        case "display":
            guard rest.count == 1, ["next", "prev", "previous"].contains(rest[0]) else { return nil }
            self = .focusDisplay(rest[0] == "next")
        case "move-display":
            guard rest.count == 1, ["next", "prev", "previous"].contains(rest[0]) else { return nil }
            self = .sendToDisplay(rest[0] == "next")
        default: return nil
        }
    }

    public var text: String {
        func name(_ d: Direction) -> String {
            switch d {
            case .left: "left"
            case .right: "right"
            case .up: "up"
            case .down: "down"
            }
        }
        func number(_ v: CGFloat) -> String {
            v == v.rounded() ? String(Int(v)) : String(Double(v))
        }
        return switch self {
        case .focus(let d): "focus \(name(d))"
        case .swap(let d): "swap \(name(d))"
        case .cycleFocus: "focus next"
        case .toggleSplit: "split"
        case .equalize: "equalize"
        case .grow(let s): "grow \(number(s.width)) \(number(s.height))"
        case .newTerminal: "terminal"
        case .toggleGroup: "group"
        case .cycleTab(let forward): forward ? "tab next" : "tab prev"
        case .moveTab(let forward): forward ? "tab-move next" : "tab-move prev"
        case .groupApp: "group-app"
        case .toggleFloating: "float"
        case .toggleFullscreen: "fullscreen"
        case .closeWindow: "close"
        case .workspace(let n): "desktop \(n)"
        case .sendToDesktop(let n): "send \(n)"
        case .scratchpad: "scratchpad"
        case .focusDisplay(let next): next ? "display next" : "display prev"
        case .sendToDisplay(let next): next ? "move-display next" : "move-display prev"
        }
    }

    public static let defaultBindings: [UInt16: Command] = {
        var map: [UInt16: Command] = [
            KeyNames.code("space")!: .toggleFloating,
            KeyNames.code("f")!: .toggleFullscreen,
            KeyNames.code("q")!: .closeWindow,
            KeyNames.code("left")!: .focus(.left),
            KeyNames.code("right")!: .focus(.right),
            KeyNames.code("up")!: .focus(.up),
            KeyNames.code("down")!: .focus(.down),
            KeyNames.code("h")!: .swap(.left),
            KeyNames.code("j")!: .swap(.down),
            KeyNames.code("k")!: .swap(.up),
            KeyNames.code("l")!: .swap(.right),
            KeyNames.code("tab")!: .cycleFocus,
            KeyNames.code("t")!: .newTerminal,
            KeyNames.code("v")!: .toggleSplit,
            KeyNames.code("e")!: .equalize,
            KeyNames.code("minus")!: .grow(CGSize(width: -0.05, height: 0)),
            KeyNames.code("equal")!: .grow(CGSize(width: 0.05, height: 0)),
            KeyNames.code("return")!: .newTerminal,
            KeyNames.code("keypad-enter")!: .newTerminal,
            KeyNames.code("g")!: .toggleGroup,
            KeyNames.code("]")!: .cycleTab(true),
            KeyNames.code("[")!: .cycleTab(false),
            KeyNames.code("a")!: .groupApp,
            KeyNames.code("s")!: .scratchpad,
            KeyNames.code("o")!: .focusDisplay(false),
            KeyNames.code("p")!: .focusDisplay(true),
            KeyNames.code("comma")!: .sendToDisplay(false),
            KeyNames.code("period")!: .sendToDisplay(true),
        ]
        for n in 1...9 { map[KeyNames.code(String(n))!] = .workspace(n) }
        return map
    }()
}

public enum KeyNames {
    static let table: [(String, UInt16)] = [
        ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05), ("z", 0x06),
        ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C), ("w", 0x0D), ("e", 0x0E),
        ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("1", 0x12), ("2", 0x13), ("3", 0x14), ("4", 0x15),
        ("6", 0x16), ("5", 0x17), ("equal", 0x18), ("9", 0x19), ("7", 0x1A), ("minus", 0x1B),
        ("8", 0x1C), ("0", 0x1D), ("]", 0x1E), ("o", 0x1F), ("u", 0x20), ("[", 0x21), ("i", 0x22),
        ("p", 0x23), ("return", 0x24), ("l", 0x25), ("j", 0x26), ("quote", 0x27), ("k", 0x28),
        ("semicolon", 0x29), ("backslash", 0x2A), ("comma", 0x2B), ("slash", 0x2C), ("n", 0x2D),
        ("m", 0x2E), ("period", 0x2F), ("tab", 0x30), ("space", 0x31), ("grave", 0x32),
        ("delete", 0x33), ("escape", 0x35),
        ("f1", 0x7A), ("f2", 0x78), ("f3", 0x63), ("f4", 0x76), ("f5", 0x60), ("f6", 0x61),
        ("f7", 0x62), ("f8", 0x64), ("f9", 0x65), ("f10", 0x6D), ("f11", 0x67), ("f12", 0x6F),
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
        ("keypad-enter", 0x4C), ("home", 0x73), ("end", 0x77), ("pageup", 0x74), ("pagedown", 0x79),
    ]
    static let aliases: [String: String] = [
        "=": "equal", "-": "minus", "enter": "return", "esc": "escape", ",": "comma", ".": "period",
        "/": "slash", ";": "semicolon", "'": "quote", "`": "grave", "\\": "backslash",
        "leftbracket": "[", "rightbracket": "]", "backspace": "delete",
    ]

    public static func code(_ name: String) -> UInt16? {
        let key = name.lowercased()
        let canonical = aliases[key] ?? key
        return table.first { $0.0 == canonical }?.1
    }

    public static func name(_ code: UInt16) -> String? {
        table.first { $0.1 == code }?.0
    }
}
