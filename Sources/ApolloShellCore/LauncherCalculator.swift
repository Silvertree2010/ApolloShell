import Foundation

public enum LauncherCalculator {
    public static func evaluate(_ text: String) -> Double? {
        var parser = Parser(text)
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

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
