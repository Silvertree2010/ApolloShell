import Foundation

enum StringFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("string", arity: FilterArity(0, 0), nullInput: .accept) { input, _, _ in
            .string(input.stringified)
        },
        BuiltinFilter("shell-quote", arity: FilterArity(0, 0)) { input, _, _ in
            .string(ShellQuote.word(input.stringified))
        },
        BuiltinFilter("upper", arity: FilterArity(0, 0)) { input, _, context in
            .string(try input.textInput("upper").uppercased(with: context.locale))
        },
        BuiltinFilter("lower", arity: FilterArity(0, 0)) { input, _, context in
            .string(try input.textInput("lower").lowercased(with: context.locale))
        },
        BuiltinFilter("capitalize", arity: FilterArity(0, 0)) { input, _, context in
            let text = try input.textInput("capitalize")
            guard let first = text.first else { return .string(text) }
            return .string(String(first).uppercased(with: context.locale) + text.dropFirst())
        },
        BuiltinFilter("truncate", arity: FilterArity(1, 1)) { input, arguments, _ in
            let text = try input.textInput("truncate")
            let limit = try arguments.integer(0, range: 0...1_000_000)
            guard text.count > limit else { return .string(text) }
            return .string(String(text.prefix(limit)) + "…")
        },
        BuiltinFilter("pad", arity: FilterArity(1, 2)) { input, arguments, _ in
            let text = try input.textInput("pad")
            let width = try arguments.integer(0, range: 0...10_000)
            let fill = try arguments.optionalString(1) ?? " "
            guard fill.count == 1 else { throw FilterFailure("'pad' needs exactly one fill character") }
            guard text.count < width else { return .string(text) }
            return .string(String(repeating: fill, count: width - text.count) + text)
        },
        BuiltinFilter("replace", arity: FilterArity(2, 2)) { input, arguments, _ in
            let text = try input.textInput("replace")
            let target = try arguments.string(0)
            let replacement = try arguments.string(1)
            guard !target.isEmpty else { throw FilterFailure("'replace' needs a non-empty text to replace") }
            let growth = replacement.utf8.count - target.utf8.count
            if growth > 0, text.utf8.count + text.utf8.count / target.utf8.count * growth > ExpressionLimits.maxTextBytes {
                var occurrences = 0
                var searchStart = text.startIndex
                while let found = text.range(of: target, range: searchStart..<text.endIndex) {
                    occurrences += 1
                    searchStart = found.upperBound
                }
                guard text.utf8.count + occurrences * growth <= ExpressionLimits.maxTextBytes else {
                    throw FilterFailure("'replace' would produce text longer than \(ExpressionLimits.maxTextBytes) bytes")
                }
            }
            return .string(text.replacingOccurrences(of: target, with: replacement))
        },
        BuiltinFilter("split", arity: FilterArity(1, 1)) { input, arguments, _ in
            let text = try input.textInput("split")
            let separator = try arguments.string(0)
            if separator.isEmpty {
                return .list(text.map { .string(String($0)) })
            }
            return .list(text.components(separatedBy: separator).map { .string($0) })
        },
        BuiltinFilter("starts-with", arity: FilterArity(1, 1)) { input, arguments, _ in
            .bool(try input.textInput("starts-with").hasPrefix(try arguments.string(0)))
        },
        BuiltinFilter("ends-with", arity: FilterArity(1, 1)) { input, arguments, _ in
            .bool(try input.textInput("ends-with").hasSuffix(try arguments.string(0)))
        },
        BuiltinFilter("json", arity: FilterArity(0, 0)) { input, _, _ in
            guard case .string(let text) = input else { throw FilterFailure.input("json", expected: "a string", got: input) }
            return JSONValue.parse(text) ?? .null
        },
        BuiltinFilter("number", arity: FilterArity(0, 0)) { input, _, _ in
            switch input {
            case .number:
                return input
            case .date(let date):
                return .number(date.timeIntervalSince1970)
            case .string(let text):
                guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite else { return .null }
                return .number(number)
            default:
                throw FilterFailure.input("number", expected: "a string", got: input)
            }
        },
    ]
}

public enum ShellQuote {
    public static func word(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
