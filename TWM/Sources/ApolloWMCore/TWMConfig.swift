import Foundation

/// The window manager's config file (like Hyprland's hyprland.conf): which
/// Super + key does what, and rules for particular apps. One setting per
/// line, `#` starts a comment:
///
///     bind = H, swap left
///     unbind = Q
///     rule = float, app:com.apple.calculator
///     rule = ignore, app:zoom.us, title:Meeting
///
/// Lines it cannot read are reported with their number and skipped; the rest
/// still apply.
public struct TWMConfig: Sendable, Equatable {
    /// Super + key (virtual key code) to command, defaults included.
    public var bindings: [UInt16: Command]
    public var rules: [WindowRule]
    public var problems: [String]

    public init(bindings: [UInt16: Command] = Command.defaultBindings, rules: [WindowRule] = [],
                problems: [String] = []) {
        self.bindings = bindings
        self.rules = rules
        self.problems = problems
    }

    public static func parse(_ text: String) -> TWMConfig {
        var config = TWMConfig()
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            let number = index + 1
            guard let equals = line.firstIndex(of: "=") else {
                config.problems.append("line \(number): expected `name = value`")
                continue
            }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            switch name {
            case "bind":
                guard parts.count == 2, let key = KeyNames.code(parts[0]) else {
                    config.problems.append("line \(number): unknown key in `\(value)`")
                    continue
                }
                guard let command = Command(parsing: parts[1]) else {
                    config.problems.append("line \(number): unknown command `\(parts[1])`")
                    continue
                }
                config.bindings[key] = command
            case "unbind":
                guard let key = KeyNames.code(value) else {
                    config.problems.append("line \(number): unknown key `\(value)`")
                    continue
                }
                config.bindings[key] = nil
            case "rule":
                switch WindowRule.parse(value) {
                case .success(let rule): config.rules.append(rule)
                case .failure(let problem): config.problems.append("line \(number): \(problem.message)")
                }
            default:
                config.problems.append("line \(number): unknown setting `\(name)`")
            }
        }
        return config
    }

    /// The file a user starts from: every default key as a comment, and how
    /// to write rules.
    public static var template: String {
        var lines = [
            "# ApolloShell TWM: keys and window rules. Changes apply as soon as",
            "# the file is saved. Keys are pressed together with Super (fn held).",
            "#",
            "#   bind = KEY, COMMAND      give a key a command (replaces the default)",
            "#   unbind = KEY             take a default key away",
            "#   rule = ACTION, app:APP[, title:TEXT]",
            "#     ACTION: float (never tiled), tile (tiled even if a dialog),",
            "#     ignore (left alone completely). APP: bundle id or app name.",
            "#     TEXT: part of the window title.",
            "#",
            "# Commands: focus left|right|up|down|next, swap left|right|up|down,",
            "# split, equalize, grow W H (fractions, e.g. grow 0.05 0), terminal,",
            "# group, tab next|prev, float, fullscreen, close, desktop N, send N,",
            "# scratchpad, display next|prev,",
            "# move-display next|prev, tab-move next|prev, group-app",
            "#",
            "# The defaults:",
        ]
        let sorted = Command.defaultBindings.sorted { (KeyNames.name($0.key) ?? "") < (KeyNames.name($1.key) ?? "") }
        for (key, command) in sorted {
            lines.append("# bind = \(KeyNames.name(key) ?? "?"), \(command.text)")
        }
        lines += [
            "#",
            "# Examples:",
            "# rule = float, app:com.apple.calculator",
            "# rule = float, app:System Settings",
            "# rule = ignore, app:zoom.us, title:Meeting",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}

/// What happens to the windows of a particular app.
public struct WindowRule: Sendable, Equatable, Codable {
    public enum Action: String, Sendable, Codable, CaseIterable {
        /// Never tiled: floats where the app puts it.
        case float
        /// Tiled even when it would float by itself (a dialog, a panel).
        case tile
        /// Left alone completely: never moved, focused or bordered.
        case ignore
    }

    public var action: Action
    /// Bundle id or app name, compared without case.
    public var app: String?
    /// Part of the window title, compared without case.
    public var title: String?

    public init(action: Action, app: String? = nil, title: String? = nil) {
        self.action = action
        self.app = app
        self.title = title
    }

    public struct Problem: Error, Equatable {
        public let message: String
    }

    /// `float, app:com.apple.calculator, title:Converter`
    public init?(parsing text: String) {
        guard case .success(let rule) = Self.parse(text) else { return nil }
        self = rule
    }

    static func parse(_ text: String) -> Result<WindowRule, Problem> {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let action = Action(rawValue: first.lowercased()) else {
            return .failure(Problem(message: "a rule starts with float, tile or ignore"))
        }
        var rule = WindowRule(action: action)
        for part in parts.dropFirst() {
            guard let colon = part.firstIndex(of: ":") else {
                return .failure(Problem(message: "expected app:… or title:…, got `\(part)`"))
            }
            let key = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return .failure(Problem(message: "`\(key):` needs a value")) }
            switch key {
            case "app": rule.app = value
            case "title": rule.title = value
            default: return .failure(Problem(message: "unknown matcher `\(key)`"))
            }
        }
        guard rule.app != nil || rule.title != nil else {
            return .failure(Problem(message: "a rule needs app:… or title:…"))
        }
        return .success(rule)
    }

    public func matches(bundleID: String?, appName: String?, title windowTitle: String) -> Bool {
        if let app {
            let wanted = app.lowercased()
            guard bundleID?.lowercased() == wanted || appName?.lowercased() == wanted else { return false }
        }
        if let title {
            guard windowTitle.lowercased().contains(title.lowercased()) else { return false }
        }
        return true
    }
}

extension Array where Element == WindowRule {
    /// The action of the last rule that matches (later lines win).
    public func action(bundleID: String?, appName: String?, title: String) -> WindowRule.Action? {
        last { $0.matches(bundleID: bundleID, appName: appName, title: title) }?.action
    }
}
