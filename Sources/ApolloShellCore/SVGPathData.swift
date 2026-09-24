import CoreGraphics
import Foundation

/// Reads the `d` attribute of an SVG path into absolute drawing steps.
///
/// Enough for artwork exported from Illustrator: M/m, L/l, H/h, V/v, C/c,
/// S/s and Z/z, numbers with or without separators ("-3.97-6.38", ".5.5").
/// No arcs and no quadratic curves; a path that uses them reads up to that
/// point and stops, so a bad string draws less instead of crashing.
///
/// For the ApolloShell mark (`ApolloMark`), whose shapes come straight out of
/// the logo's SVG, so the drawn mark is the logo and not a redrawing of it.
public enum SVGPathData {
    public enum Step: Equatable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    public static func parse(_ d: String) -> [Step] {
        var scanner = NumberScanner(d)
        var steps: [Step] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character?

        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next {
                command = c
                if c == "Z" || c == "z" {
                    steps.append(.close)
                    current = subpathStart
                    lastControl = nil
                    continue
                }
            } else {
                // A number without a command letter repeats the last one.
                scanner.pushBack()
            }
            guard let c = command else { break }
            let relative = c.isLowercase
            let origin = relative ? current : .zero
            switch c {
            case "M", "m":
                guard let p = scanner.point(origin) else { return steps }
                steps.append(.move(p))
                current = p
                subpathStart = p
                lastControl = nil
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L", "l":
                guard let p = scanner.point(origin) else { return steps }
                steps.append(.line(p))
                current = p
                lastControl = nil
            case "H", "h":
                guard let x = scanner.number() else { return steps }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                steps.append(.line(current))
                lastControl = nil
            case "V", "v":
                guard let y = scanner.number() else { return steps }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                steps.append(.line(current))
                lastControl = nil
            case "C", "c":
                guard let c1 = scanner.point(origin), let c2 = scanner.point(origin),
                      let p = scanner.point(origin) else { return steps }
                steps.append(.curve(p, control1: c1, control2: c2))
                current = p
                lastControl = c2
            case "S", "s":
                guard let c2 = scanner.point(origin), let p = scanner.point(origin) else { return steps }
                // The first control mirrors the previous curve's second one.
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                steps.append(.curve(p, control1: c1, control2: c2))
                current = p
                lastControl = c2
            default:
                return steps
            }
        }
        return steps
    }

    private struct NumberScanner {
        enum Token { case command(Character), number(Double) }

        private let chars: [Character]
        private var index = 0
        private var lastStart = 0

        init(_ text: String) { chars = Array(text) }

        mutating func nextCommandOrNumber() -> Token? {
            skipSeparators()
            lastStart = index
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter {
                index += 1
                return .command(c)
            }
            return number().map(Token.number)
        }

        mutating func pushBack() { index = lastStart }

        mutating func point(_ origin: CGPoint) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: origin.x + x, y: origin.y + y)
        }

        /// One number: a sign, digits, at most one point, an exponent. A
        /// second point or a sign ends it, as SVG allows ("1.5.5" = 1.5, .5).
        mutating func number() -> Double? {
            skipSeparators()
            let start = index
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            var sawDot = false
            var sawDigit = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    sawDigit = true
                } else if c == ".", !sawDot {
                    sawDot = true
                } else if (c == "e" || c == "E"), sawDigit {
                    index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                    continue
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit else {
                index = start
                return nil
            }
            return Double(String(chars[start..<index]))
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline {
                index += 1
            }
        }
    }
}
