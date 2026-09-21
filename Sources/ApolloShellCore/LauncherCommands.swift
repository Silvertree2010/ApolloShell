import Foundation

/// The launcher's action mode, after Caelestia (`launcher.actionPrefix`,
/// `modules/launcher/services/Actions.qml`): a search that starts with `>`
/// lists actions instead of apps, and three of them take the rest of the
/// line - `>calc`, `>theme`, `>wallpaper`.
///
/// Caelestia's list, as it maps onto the Mac: Calculator, Scheme (here the
/// themes), Wallpaper, Random, Light, Dark, Shutdown, Reboot, Logout, Lock,
/// Sleep, Settings. Variant is left out: it belongs to Caelestia's generated
/// colour schemes, which ApolloShell does not have.
public enum LauncherQuery: Equatable, Sendable {
    public static let actionPrefix = ">"

    /// No prefix: apps, as always.
    case apps(String)
    /// `>` with text that is not one of the modes below: the actions,
    /// filtered by the text.
    case actions(String)
    /// `>calc 2*(3+4)`
    case calculator(String)
    /// `>theme cla`
    case theme(String)
    /// `>wallpaper big sur`
    case wallpaper(String)

    public static func parse(_ text: String) -> LauncherQuery {
        let trimmedLeading = text.drop { $0 == " " }
        guard trimmedLeading.hasPrefix(actionPrefix) else { return .apps(text) }
        let rest = String(trimmedLeading.dropFirst(actionPrefix.count))
        for (keyword, make) in modes {
            // Only with the space after it, as in Caelestia: ">calc" alone is
            // still the action to pick, ">calc " is the calculator.
            if rest.lowercased().hasPrefix(keyword + " ") {
                return make(String(rest.dropFirst(keyword.count + 1)).trimmingCharacters(in: .whitespaces))
            }
        }
        return .actions(rest.trimmingCharacters(in: .whitespaces))
    }

    private static let modes: [(String, @Sendable (String) -> LauncherQuery)] = [
        ("calc", { .calculator($0) }),
        ("theme", { .theme($0) }),
        ("wallpaper", { .wallpaper($0) }),
    ]
}

/// The actions the `>` list offers.
public enum LauncherAction: String, CaseIterable, Identifiable, Sendable {
    case calculator, theme, wallpaper, randomWallpaper, light, dark
    case lock, sleep, logOut, restart, shutDown, settings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .calculator: String(localized: "Calculator")
        case .theme: String(localized: "Theme")
        case .wallpaper: String(localized: "Wallpaper")
        case .randomWallpaper: String(localized: "Random Wallpaper")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        case .lock: String(localized: "Lock")
        case .sleep: String(localized: "Sleep")
        case .logOut: String(localized: "Log Out")
        case .restart: String(localized: "Restart")
        case .shutDown: String(localized: "Shut Down")
        case .settings: String(localized: "Settings")
        }
    }

    public var subtitle: String {
        switch self {
        case .calculator: String(localized: "Do simple maths, the result is copied")
        case .theme: String(localized: "Change the theme")
        case .wallpaper: String(localized: "Change the wallpaper")
        case .randomWallpaper: String(localized: "Switch to a random wallpaper")
        case .light: String(localized: "Switch to light mode")
        case .dark: String(localized: "Switch to dark mode")
        case .lock: String(localized: "Lock the screen")
        case .sleep: String(localized: "Put the Mac to sleep")
        case .logOut: String(localized: "Log out of this session")
        case .restart: String(localized: "Restart the Mac")
        case .shutDown: String(localized: "Shut down the Mac")
        case .settings: String(localized: "Open the Nexus panel")
        }
    }

    public var symbol: String {
        switch self {
        case .calculator: "plus.forwardslash.minus"
        case .theme: "paintpalette"
        case .wallpaper: "photo"
        case .randomWallpaper: "dice"
        case .light: "sun.max"
        case .dark: "moon"
        case .lock: "lock"
        case .sleep: "moon.zzz"
        case .logOut: "rectangle.portrait.and.arrow.right"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .settings: "gearshape"
        }
    }

    /// Asks once more before it runs (Caelestia hides these by default;
    /// here they stay, with a second Return as the confirmation).
    public var needsConfirmation: Bool {
        switch self {
        case .logOut, .restart, .shutDown: true
        default: false
        }
    }

    /// The mode keyword the action fills in instead of running, if any.
    public var completion: String? {
        switch self {
        case .calculator: "calc"
        case .theme: "theme"
        case .wallpaper: "wallpaper"
        default: nil
        }
    }

    /// The actions for a filter text: every one whose title or keyword
    /// starts with a word of it, in catalogue order. Empty text: all.
    public static func matching(_ text: String) -> [LauncherAction] {
        let needle = text.lowercased()
        guard !needle.isEmpty else { return allCases }
        return allCases.filter { action in
            let words = (action.title.lowercased() + " " + (action.completion ?? action.rawValue.lowercased()))
                .split(separator: " ")
            return words.contains { $0.hasPrefix(needle) } || action.title.lowercased().hasPrefix(needle)
        }
    }
}

/// A small calculator for `>calc`: + − × ÷, powers (^), percent of a number
/// (`%` after a number divides by 100), parentheses, decimals with a point
/// or a comma, the constants pi and e, and sqrt, abs, round, floor, ceil,
/// sin, cos, tan (radians), ln, log (base 10).
///
/// Its own parser on purpose: `NSExpression` raises an Objective-C exception
/// on half-typed input (`2*(`), which cannot be caught in Swift - the
/// launcher evaluates on every keystroke.
public enum LauncherCalculator {
    /// `nil` when the text is not (yet) a complete expression or the result
    /// is not a finite number.
    public static func evaluate(_ text: String) -> Double? {
        var parser = Parser(text)
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

    /// Up to ten significant digits, no trailing zeros, no scientific
    /// notation for everyday sizes: 7, 0.5, 3.1415926536, 1e+21.
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 10
        formatter.numberStyle = abs(value) >= 1e15 || abs(value) < 1e-6 ? .scientific : .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) {
            chars = Array(text.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-"))
        }

        var atEnd: Bool {
            mutating get {
                skipSpaces()
                return index >= chars.count
            }
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "+" || op == "-" else { return value }
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
        }

        private mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while true {
                skipSpaces()
                guard let op = peek(), op == "*" || op == "/" else { return value }
                index += 1
                guard let rhs = power() else { return nil }
                value = op == "*" ? value * rhs : value / rhs
            }
        }

        /// Right-associative: 2^3^2 = 2^9.
        private mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            skipSpaces()
            guard peek() == "^" else { return base }
            index += 1
            guard let exponent = power() else { return nil }
            return pow(base, exponent)
        }

        private mutating func unary() -> Double? {
            skipSpaces()
            if peek() == "-" {
                index += 1
                return unary().map { -$0 }
            }
            if peek() == "+" {
                index += 1
                return unary()
            }
            return postfix()
        }

        private mutating func postfix() -> Double? {
            guard var value = primary() else { return nil }
            skipSpaces()
            while peek() == "%" {
                index += 1
                value /= 100
                skipSpaces()
            }
            return value
        }

        private mutating func primary() -> Double? {
            skipSpaces()
            guard let c = peek() else { return nil }
            if c == "(" {
                index += 1
                guard let value = expression() else { return nil }
                skipSpaces()
                guard peek() == ")" else { return nil }
                index += 1
                return value
            }
            if c.isNumber || c == "." || c == "," { return number() }
            if c.isLetter { return function() }
            return nil
        }

        private mutating func number() -> Double? {
            let start = index
            while let c = peek(), c.isNumber || c == "." || c == "," { index += 1 }
            let text = String(chars[start..<index]).replacingOccurrences(of: ",", with: ".")
            return Double(text)
        }

        private mutating func function() -> Double? {
            let start = index
            while let c = peek(), c.isLetter { index += 1 }
            let name = String(chars[start..<index]).lowercased()
            switch name {
            case "pi", "π": return .pi
            case "e": return M_E
            default: break
            }
            guard let apply = Self.functions[name] else { return nil }
            skipSpaces()
            guard peek() == "(" else { return nil }
            guard let argument = primary() else { return nil }
            return apply(argument)
        }

        private static let functions: [String: @Sendable (Double) -> Double] = [
            "sqrt": { $0.squareRoot() }, "abs": { abs($0) }, "round": { $0.rounded() },
            "floor": { $0.rounded(.down) }, "ceil": { $0.rounded(.up) },
            "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
            "ln": { log($0) }, "log": { log10($0) },
        ]

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func skipSpaces() {
            while let c = peek(), c == " " { index += 1 }
        }
    }
}
