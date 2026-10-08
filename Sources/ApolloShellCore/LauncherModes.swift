import Foundation

public enum LauncherMode: Equatable, Sendable {
    case apps(String)
    case calc(String)
    case actions(String)
    case clipboard(String)

    public static func parse(_ q: String) -> LauncherMode {
        let t = q.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("=") { return .calc(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if t.hasPrefix(">") { return .actions(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if t.hasPrefix(":") { return .clipboard(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        return .apps(t)
    }
}

public enum LauncherCalc {
    public static func evaluate(_ s: String) -> Double? {
        var p = Parser(Array(s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: ".")))
        guard let v = p.expr(), p.done, v.isFinite else { return nil }
        return v
    }

    public static func looksLikeMath(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, t.contains(where: { "+-*/^%×÷".contains($0) }),
              t.allSatisfy({ "0123456789.,+-*/^%()×÷ ".contains($0) }), t.contains(where: \.isNumber)
        else { return false }
        return evaluate(t) != nil
    }

    public static func format(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        f.usesGroupingSeparator = false
        f.decimalSeparator = "."
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    struct Parser {
        var c: [Character]
        var i = 0

        init(_ c: [Character]) { self.c = c.filter { $0 != " " } }

        var done: Bool { i == c.count }

        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while i < c.count, c[i] == "+" || c[i] == "-" {
                let op = c[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = unary() else { return nil }
            while i < c.count, "*/%".contains(c[i]) {
                let op = c[i]; i += 1
                guard let r = unary() else { return nil }
                switch op {
                case "*": v *= r
                case "/": guard r != 0 else { return nil }; v /= r
                default: guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
                }
            }
            return v
        }

        mutating func power() -> Double? {
            guard let b = atom() else { return nil }
            if i < c.count, c[i] == "^" {
                i += 1
                guard let e = unary() else { return nil }
                return pow(b, e)
            }
            return b
        }

        mutating func unary() -> Double? {
            if i < c.count, c[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < c.count, c[i] == "+" { i += 1; return unary() }
            return power()
        }

        mutating func atom() -> Double? {
            guard i < c.count else { return nil }
            if c[i] == "(" {
                i += 1
                guard let v = expr(), i < c.count, c[i] == ")" else { return nil }
                i += 1
                return v
            }
            let s = i
            while i < c.count, c[i].isNumber || c[i] == "." { i += 1 }
            guard i > s else { return nil }
            return Double(String(c[s..<i]))
        }
    }
}

public enum LauncherAction: String, CaseIterable, Sendable, Identifiable {
    case lock, sleep, darkMode, screenshot, showDesktop, emptyTrash, settings, restart, shutDown, logOut

    public var id: Self { self }

    public var title: String {
        switch self {
        case .lock: String(localized: "Lock Screen")
        case .sleep: String(localized: "Sleep")
        case .darkMode: String(localized: "Toggle Dark Mode")
        case .screenshot: String(localized: "Screenshot")
        case .showDesktop: String(localized: "Show Desktop")
        case .emptyTrash: String(localized: "Empty Trash")
        case .settings: String(localized: "ApolloShell Settings")
        case .restart: String(localized: "Restart…")
        case .shutDown: String(localized: "Shut Down…")
        case .logOut: String(localized: "Log Out…")
        }
    }

    public var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .sleep: "moon.fill"
        case .darkMode: "circle.lefthalf.filled"
        case .screenshot: "camera.viewfinder"
        case .showDesktop: "macwindow.on.rectangle"
        case .emptyTrash: "trash.fill"
        case .settings: "gearshape.fill"
        case .restart: "arrow.clockwise"
        case .shutDown: "power"
        case .logOut: "rectangle.portrait.and.arrow.right"
        }
    }

    public var keywords: [String] {
        switch self {
        case .lock: ["sperren", "lock"]
        case .sleep: ["ruhezustand", "schlafen"]
        case .darkMode: ["dunkel", "hell", "appearance", "theme"]
        case .screenshot: ["bildschirmfoto", "capture", "screen"]
        case .showDesktop: ["schreibtisch", "desktop"]
        case .emptyTrash: ["papierkorb", "leeren"]
        case .settings: ["nexus", "einstellungen", "preferences"]
        case .restart: ["neustart", "reboot"]
        case .shutDown: ["ausschalten", "power off"]
        case .logOut: ["abmelden", "sign out"]
        }
    }

    public static func matching(_ q: String) -> [LauncherAction] {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return allCases }
        return allCases.filter { a in
            ([a.title, a.rawValue] + a.keywords).contains { $0.localizedStandardContains(t) }
        }
    }
}
