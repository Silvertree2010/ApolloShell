import Foundation
import ApolloConfig
import ApolloKDL
import ApolloShellCore
import ApolloWMCore

public struct WMSettings: Sendable, Equatable {
    public enum Layout: String, Sendable, CaseIterable {
        case dwindle, canvas
    }

    public enum Resize: String, Sendable, CaseIterable {
        case smooth, snap, proxy
    }

    public struct Reserve: Sendable, Equatable {
        public var top: Double
        public var left: Double
        public var bottom: Double
        public var right: Double
        public var screen: String?

        public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0, screen: String? = nil) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
            self.screen = screen
        }
    }

    public static let defaultTerminals = ["net.kovidgoyal.kitty", "com.mitchellh.ghostty", "com.apple.Terminal"]

    public var enabled: CompiledValue?
    public var layout = Layout.dwindle
    public var innerGap = 10.0
    public var outerGap = 12.0
    public var focusFollowsMouse = true
    public var focusDelay = 0.025
    public var focusSuspendWith: HotKeyModifiers = []
    public var dragModifiers: HotKeyModifiers = .hyper
    public var scrollPans = true
    public var scrollSpeed = 1.5
    public var invertScroll = false
    public var resize = Resize.smooth
    public var springResponse = 0.28
    public var frameRate = 120.0
    public var tabBarHeight = 30.0
    public var columnWidth = 0.5
    public var centerFocused = false
    public var scratchpadShare = 0.7
    public var terminals = WMSettings.defaultTerminals
    public var appleDesktops = true
    public var rules: [WindowRule] = []
    public var reservePanels = true
    public var reserves: [Reserve] = []
    public var problems: [String] = []

    public init() {}

    public init?(config: ConfigIR) {
        guard let blocks = config.blocks["wm"], !blocks.isEmpty else { return nil }
        self.init(blocks: blocks)
    }

    public init(blocks: [BlockIR]) {
        for block in blocks {
            if let enabled = block.compiled["enabled"] {
                self.enabled = enabled
            }
            for node in block.nodes {
                for child in node.children ?? [] {
                    read(child)
                }
            }
        }
    }

    private mutating func read(_ node: KDLNode) {
        let reader = NodeReader(node: node)
        switch node.name {
        case "layout":
            reader.argument(0).flatMap(Layout.init(rawValue:)).map { layout = $0 }
        case "gaps":
            reader.number("inner").map { innerGap = max(0, $0) }
            reader.number("outer").map { outerGap = max(0, $0) }
        case "focus-follows-mouse":
            reader.flag(0).map { focusFollowsMouse = $0 }
            if let text = reader.string("delay") {
                if let seconds = Self.seconds(text) { focusDelay = seconds } else { problem(node, "delay \"\(text)\" is not a duration") }
            }
            if let text = reader.string("suspend-with") {
                if let flags = Self.modifiers(text) { focusSuspendWith = flags } else { problem(node, "unknown modifier in \"\(text)\"") }
            }
        case "drag":
            if let text = reader.string("super") {
                if let flags = Self.modifiers(text), !flags.isEmpty { dragModifiers = flags } else { problem(node, "unknown modifier in \"\(text)\"") }
            }
            reader.bool("scroll-pans").map { scrollPans = $0 }
            reader.number("scroll-speed").map { scrollSpeed = $0 }
            reader.bool("invert-scroll").map { invertScroll = $0 }
        case "resize-animation":
            reader.argument(0).flatMap(Resize.init(rawValue:)).map { resize = $0 }
        case "spring":
            reader.number("response").map { springResponse = max(0.01, $0) }
            reader.number("frame-rate").map { frameRate = min(max(1, $0), 240) }
        case "tab-bar":
            reader.number("height").map { tabBarHeight = max(0, $0) }
        case "canvas":
            if let width = reader.number("column-width") {
                if (0.05...1).contains(width) { columnWidth = width } else { problem(node, "column-width must be between 0.05 and 1") }
            }
            reader.bool("center-focused").map { centerFocused = $0 }
        case "scratchpad":
            if let share = reader.number("share") {
                if (0.1...1).contains(share) { scratchpadShare = share } else { problem(node, "share must be between 0.1 and 1") }
            }
        case "terminal":
            let ids = node.arguments.compactMap { NodeReader.text($0) }.filter { !$0.isEmpty }
            if ids.isEmpty { problem(node, "terminal needs at least one bundle id") } else { terminals = ids }
        case "apple-desktops":
            reader.flag(0).map { appleDesktops = $0 }
        case "rule":
            guard let action = reader.argument(0).flatMap(WindowRule.Action.init(rawValue:)) else { return }
            let app = reader.string("app").flatMap { $0.isEmpty ? nil : $0 }
            let title = reader.string("title").flatMap { $0.isEmpty ? nil : $0 }
            guard app != nil || title != nil else {
                problem(node, "a rule needs app= or title=")
                return
            }
            rules.append(WindowRule(action: action, app: app, title: title))
        case "reserve-panels":
            reader.flag(0).map { reservePanels = $0 }
        case "reserve":
            reserves.append(Reserve(
                top: max(0, reader.number("top") ?? 0),
                left: max(0, reader.number("left") ?? 0),
                bottom: max(0, reader.number("bottom") ?? 0),
                right: max(0, reader.number("right") ?? 0),
                screen: reader.string("screen")
            ))
        default:
            break
        }
    }

    private mutating func problem(_ node: KDLNode, _ message: String) {
        problems.append("wm \(node.name): \(message)")
    }

    public static func seconds(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for (suffix, factor) in [("ms", 0.001), ("s", 1.0), ("m", 60.0), ("h", 3600.0)] where trimmed.hasSuffix(suffix) {
            guard let amount = Double(trimmed.dropLast(suffix.count)), amount.isFinite, amount >= 0 else { return nil }
            return amount * factor
        }
        return Double(trimmed).flatMap { $0.isFinite && $0 >= 0 ? $0 / 1000 : nil }
    }

    public static func modifiers(_ text: String) -> HotKeyModifiers? {
        let names: [String: HotKeyModifiers] = [
            "cmd": .command, "command": .command, "ctrl": .control, "control": .control,
            "alt": .option, "opt": .option, "option": .option, "shift": .shift, "hyper": .hyper,
        ]
        var result: HotKeyModifiers = []
        for part in text.lowercased().split(separator: "+") {
            guard let flags = names[part.trimmingCharacters(in: .whitespaces)] else { return nil }
            result.formUnion(flags)
        }
        return result
    }
}

private struct NodeReader {
    let node: KDLNode

    static func text(_ value: KDLValue) -> String? {
        if case .string(let text) = value.scalar { return text }
        return nil
    }

    func argument(_ index: Int) -> String? {
        node.arguments.indices.contains(index) ? Self.text(node.arguments[index]) : nil
    }

    func flag(_ index: Int) -> Bool? {
        guard node.arguments.indices.contains(index), case .bool(let flag) = node.arguments[index].scalar else { return nil }
        return flag
    }

    func string(_ name: String) -> String? {
        node.property(name).flatMap { Self.text($0.value) }
    }

    func number(_ name: String) -> Double? {
        guard let value = node.property(name)?.value, case .number(let number, _) = value.scalar, number.isFinite else { return nil }
        return number
    }

    func bool(_ name: String) -> Bool? {
        guard let value = node.property(name)?.value, case .bool(let flag) = value.scalar else { return nil }
        return flag
    }
}
