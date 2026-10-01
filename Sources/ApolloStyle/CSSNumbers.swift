import ApolloBase

enum CSSDimension: String, Sendable, Hashable {
    case number
    case length
    case percent = "percentage"
    case angle
    case duration
    case fraction
}

struct CSSNumeric: Sendable, Hashable {
    var value: Double
    var dimension: CSSDimension
}

enum CSSNumbers {
    static func numeric(_ component: CSSComponent) throws -> CSSNumeric? {
        switch component {
        case let .token(token):
            switch token.kind {
            case let .number(value): return CSSNumeric(value: value, dimension: .number)
            case let .percentage(value): return CSSNumeric(value: value, dimension: .percent)
            case let .dimension(value, unit): return dimension(value, unit)
            default: return nil
            }
        case let .function(name, arguments, _) where CSSCalc.names.contains(name.lowercased()):
            return try CSSCalc.evaluate(arguments, function: name.lowercased())
        default:
            return nil
        }
    }

    static func dimension(_ value: Double, _ unit: String) -> CSSNumeric? {
        switch unit.lowercased() {
        case "px", "pt": CSSNumeric(value: value, dimension: .length)
        case "deg": CSSNumeric(value: value, dimension: .angle)
        case "ms": CSSNumeric(value: value / 1000, dimension: .duration)
        case "s": CSSNumeric(value: value, dimension: .duration)
        case "fr": CSSNumeric(value: value, dimension: .fraction)
        default: nil
        }
    }
}

enum CSSCalc {
    static let maximumNestingDepth = 64
    static let names: Set<String> = ["calc", "min", "max", "clamp"]

    static func evaluate(_ arguments: [CSSComponent], function: String = "calc") throws -> CSSNumeric {
        let outcome: Result<CSSNumeric, CSSValueError> = StackHeadroom.run {
            do {
                let result = try apply(function, arguments, depth: 0)
                guard result.value.isFinite else { return .failure(CSSValueError("\(function)() does not give a finite number")) }
                return .success(result)
            } catch let error as CSSValueError {
                return .failure(error)
            } catch {
                return .failure(CSSValueError("\(error)"))
            }
        }
        return try outcome.get()
    }

    static func apply(_ function: String, _ arguments: [CSSComponent], depth: Int) throws -> CSSNumeric {
        guard depth < maximumNestingDepth else { throw CSSValueError("\(function)() is nested too deeply") }
        if function == "calc" {
            var inner = Parser(items: CSSList.words(arguments))
            let value = try inner.sum(depth: depth)
            guard inner.isAtEnd else { throw CSSValueError("unexpected '\(inner.currentText)' in calc()") }
            return value
        }
        let parts = try CSSList.commaSeparated(arguments).map { part -> CSSNumeric in
            guard !part.isEmpty else { throw CSSValueError("\(function)() has an empty argument") }
            var inner = Parser(items: part)
            let value = try inner.sum(depth: depth + 1)
            guard inner.isAtEnd else { throw CSSValueError("unexpected '\(inner.currentText)' in \(function)()") }
            return value
        }
        guard let first = parts.first else { throw CSSValueError("\(function)() needs arguments") }
        guard parts.allSatisfy({ $0.dimension == first.dimension }) else {
            throw CSSValueError("\(function)() cannot mix \(Set(parts.map(\.dimension.rawValue)).sorted().joined(separator: " and "))")
        }
        let values = parts.map(\.value)
        let out: Double
        switch function {
        case "min":
            out = values.min() ?? first.value
        case "max":
            out = values.max() ?? first.value
        default:
            guard values.count == 3 else { throw CSSValueError("clamp() takes a minimum, a value and a maximum") }
            out = Swift.max(values[0], Swift.min(values[1], values[2]))
        }
        return CSSNumeric(value: out, dimension: first.dimension)
    }

    private struct Parser {
        let items: [CSSComponent]
        var index = 0

        var isAtEnd: Bool { index >= items.count }
        var currentText: String { isAtEnd ? "" : items[index].text }

        mutating func sum(depth: Int) throws -> CSSNumeric {
            var left = try product(depth: depth)
            while let operation = delim(), operation == "+" || operation == "-" {
                index += 1
                let right = try product(depth: depth)
                guard left.dimension == right.dimension else {
                    throw CSSValueError("calc() cannot combine \(left.dimension.rawValue) and \(right.dimension.rawValue) with \(operation)")
                }
                let value = operation == "+" ? left.value + right.value : left.value - right.value
                left = CSSNumeric(value: value, dimension: left.dimension)
            }
            return left
        }

        mutating func product(depth: Int) throws -> CSSNumeric {
            var left = try operand(depth: depth)
            while let operation = delim(), operation == "*" || operation == "/" {
                index += 1
                let right = try operand(depth: depth)
                if operation == "*" {
                    if left.dimension == .number {
                        left = CSSNumeric(value: left.value * right.value, dimension: right.dimension)
                    } else if right.dimension == .number {
                        left = CSSNumeric(value: left.value * right.value, dimension: left.dimension)
                    } else {
                        throw CSSValueError("calc() can only multiply by a plain number")
                    }
                } else {
                    guard right.dimension == .number else { throw CSSValueError("calc() can only divide by a plain number") }
                    guard right.value != 0 else { throw CSSValueError("calc() divides by zero") }
                    left = CSSNumeric(value: left.value / right.value, dimension: left.dimension)
                }
            }
            return left
        }

        mutating func operand(depth: Int) throws -> CSSNumeric {
            guard !isAtEnd else { throw CSSValueError("calc() ends too early") }
            guard depth < CSSCalc.maximumNestingDepth else { throw CSSValueError("calc() is nested too deeply") }
            let item = items[index]
            index += 1
            if case let .block(.paren, contents, _) = item {
                var inner = Parser(items: CSSList.words(contents))
                let value = try inner.sum(depth: depth + 1)
                guard inner.isAtEnd else { throw CSSValueError("unexpected '\(inner.currentText)' in calc()") }
                return value
            }
            if let name = item.functionName, CSSCalc.names.contains(name), case let .function(_, arguments, _) = item {
                let value = try CSSCalc.apply(name, arguments, depth: depth + 1)
                guard value.value.isFinite else { throw CSSValueError("\(name)() does not give a finite number") }
                return value
            }
            guard let value = try CSSNumbers.numeric(item) else {
                throw CSSValueError("calc() expects numbers and lengths, found '\(item.text)'")
            }
            return value
        }

        func delim() -> Character? {
            guard !isAtEnd else { return nil }
            return items[index].delimCharacter
        }
    }
}

enum CSSRead {
    static func single(_ components: [CSSComponent]) throws -> CSSComponent {
        let words = CSSList.words(components)
        guard words.count == 1 else {
            throw CSSValueError(words.isEmpty ? "a value is missing" : "expected one value, found '\(CSSList.text(components))'")
        }
        return words[0]
    }

    static func numeric(_ component: CSSComponent) throws -> CSSNumeric {
        guard let value = try CSSNumbers.numeric(component) else {
            throw CSSValueError("expected a number, found '\(component.text)'")
        }
        return value
    }

    static func length(_ component: CSSComponent, percent: Bool = false, auto: Bool = false, negative: Bool = true) throws -> CSSLength {
        if auto, component.lowercasedIdent == "auto" { return CSSLength(0, .auto) }
        let value = try numeric(component)
        let length: CSSLength
        switch value.dimension {
        case .length:
            length = CSSLength(value.value, .points)
        case .percent where percent:
            length = CSSLength(value.value, .percent)
        case .number where value.value == 0:
            length = CSSLength(0, .points)
        default:
            throw CSSValueError("expected a length such as 12px, found '\(component.text)'")
        }
        guard negative || length.value >= 0 else { throw CSSValueError("'\(component.text)' must not be negative") }
        return length
    }

    static func number(_ component: CSSComponent, minimum: Double? = nil, maximum: Double? = nil) throws -> Double {
        let value = try numeric(component)
        guard value.dimension == .number else { throw CSSValueError("expected a plain number, found '\(component.text)'") }
        if let minimum, value.value < minimum { throw CSSValueError("'\(component.text)' is too small") }
        if let maximum, value.value > maximum { throw CSSValueError("'\(component.text)' is too large") }
        return value.value
    }

    static func integer(_ component: CSSComponent, in range: ClosedRange<Int>) throws -> Int {
        let value = try number(component)
        guard value == value.rounded(), value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
            throw CSSValueError("expected a whole number from \(range.lowerBound) to \(range.upperBound), found '\(component.text)'")
        }
        return Int(value)
    }

    static func ratio(_ component: CSSComponent) throws -> Double {
        let value = try numeric(component)
        switch value.dimension {
        case .number: return min(max(value.value, 0), 1)
        case .percent: return min(max(value.value / 100, 0), 1)
        default: throw CSSValueError("expected a number from 0 to 1 or a percentage, found '\(component.text)'")
        }
    }

    static func angle(_ component: CSSComponent) throws -> Double {
        let value = try numeric(component)
        if value.dimension == .angle { return value.value }
        if value.dimension == .number, value.value == 0 { return 0 }
        throw CSSValueError("expected an angle such as 90deg, found '\(component.text)'")
    }

    static func duration(_ component: CSSComponent) throws -> Double {
        let value = try numeric(component)
        if value.dimension == .duration { return value.value }
        if value.dimension == .number, value.value == 0 { return 0 }
        throw CSSValueError("expected a duration such as 200ms, found '\(component.text)'")
    }

    static func keyword(_ component: CSSComponent, _ allowed: [String], aliases: [String: String] = [:]) throws -> String {
        guard let word = component.lowercasedIdent else {
            throw CSSValueError("expected \(allowed.joined(separator: ", ")), found '\(component.text)'")
        }
        let name = aliases[word] ?? word
        guard allowed.contains(name) else {
            throw CSSValueError("expected \(allowed.joined(separator: ", ")), found '\(component.text)'")
        }
        return name
    }
}
