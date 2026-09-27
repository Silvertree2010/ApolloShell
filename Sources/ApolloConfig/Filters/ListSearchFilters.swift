import Foundation
import ApolloShellCore

enum ListSearchFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("where", arity: FilterArity(2, 2)) { input, arguments, _ in
            let items = try input.listInput("where")
            let field = try arguments.string(0)
            let wanted = arguments.value(1)
            return .list(items.filter { ValueOrdering.field(field, of: $0) == wanted })
        },
        BuiltinFilter("where-not", arity: FilterArity(2, 2)) { input, arguments, _ in
            let items = try input.listInput("where-not")
            let field = try arguments.string(0)
            let unwanted = arguments.value(1)
            return .list(items.filter { ValueOrdering.field(field, of: $0) != unwanted })
        },
        BuiltinFilter("map", arity: FilterArity(1, 1)) { input, arguments, _ in
            let items = try input.listInput("map")
            let field = try arguments.string(0)
            return .list(items.map { ValueOrdering.field(field, of: $0) })
        },
        BuiltinFilter("contains", arity: FilterArity(1, 1)) { input, arguments, _ in
            switch input {
            case .list(let items):
                return .bool(items.contains(arguments.value(0)))
            case .string(let text):
                let needle = try needleText(arguments, filter: "contains")
                return .bool(needle.isEmpty || text.contains(needle))
            default:
                throw FilterFailure.input("contains", expected: "a list or a string", got: input)
            }
        },
        BuiltinFilter("index-of", arity: FilterArity(1, 1)) { input, arguments, _ in
            switch input {
            case .list(let items):
                return items.firstIndex(of: arguments.value(0)).map { Value.number(Double($0)) } ?? .null
            case .string(let text):
                let needle = try needleText(arguments, filter: "index-of")
                guard !needle.isEmpty else { return .number(0) }
                guard let range = text.range(of: needle) else { return .null }
                return .number(Double(text.distance(from: text.startIndex, to: range.lowerBound)))
            default:
                throw FilterFailure.input("index-of", expected: "a list or a string", got: input)
            }
        },
        BuiltinFilter("index-where", arity: FilterArity(2, 3)) { input, arguments, _ in
            let items = try input.listInput("index-where")
            let field = try arguments.string(0)
            let candidates: [Value]
            if case .list(let values) = arguments.value(1) {
                candidates = values
            } else {
                candidates = [arguments.value(1)]
            }
            let fromEnd = try arguments.optionalChoice(2, among: ["last"]) != nil
            let matches = items.indices.filter { candidates.contains(ValueOrdering.field(field, of: items[$0])) }
            guard let found = fromEnd ? matches.last : matches.first else { return .null }
            return .number(Double(found))
        },
        BuiltinFilter("fuzzy", arity: FilterArity(1, 2)) { input, arguments, _ in
            let items = try input.listInput("fuzzy")
            let query = try arguments.optionalString(0) ?? ""
            let field = try arguments.optionalString(1) ?? "name"
            return .list(FuzzyMatcher().rank(items, query: query) { searchName($0, field: field) })
        },
    ]

    static func needleText(_ arguments: FilterArguments, filter: String) throws -> String {
        switch arguments.value(0) {
        case .string(let text): return text
        case .number, .bool: return arguments.value(0).stringified
        default: throw FilterFailure("'\(filter)' expects a string as argument 1, got \(arguments.value(0).typeName)")
        }
    }

    static func searchName(_ item: Value, field: String) -> String {
        switch item {
        case .string(let text):
            return text
        case .record(let record):
            if case .string(let name)? = record[field] {
                return name
            }
            return ""
        default:
            return ""
        }
    }
}
