import Foundation

enum ListShapeFilters {
    static let indexRange = -1_000_000_000...1_000_000_000
    static let countRange = 0...1_000_000_000

    static let all: [BuiltinFilter] = [
        BuiltinFilter("count", arity: FilterArity(0, 0)) { input, _, _ in
            switch input {
            case .list(let items): return .number(Double(items.count))
            case .string(let text): return .number(Double(text.count))
            case .record(let record): return .number(Double(record.count))
            default: throw FilterFailure.input("count", expected: "a list, a string or a record", got: input)
            }
        },
        BuiltinFilter("first", arity: FilterArity(0, 0)) { input, _, _ in
            element(of: try input.sequenceInput("first"), at: 0)
        },
        BuiltinFilter("last", arity: FilterArity(0, 0)) { input, _, _ in
            element(of: try input.sequenceInput("last"), at: -1)
        },
        BuiltinFilter("at", arity: FilterArity(1, 1)) { input, arguments, _ in
            let sequence = try input.sequenceInput("at")
            return element(of: sequence, at: try arguments.integer(0, range: indexRange))
        },
        BuiltinFilter("take", arity: FilterArity(1, 1)) { input, arguments, _ in
            let sequence = try input.sequenceInput("take")
            return slice(sequence, from: 0, to: try arguments.integer(0, range: countRange))
        },
        BuiltinFilter("skip", arity: FilterArity(1, 1)) { input, arguments, _ in
            let sequence = try input.sequenceInput("skip")
            return slice(sequence, from: try arguments.integer(0, range: countRange), to: Int.max)
        },
        BuiltinFilter("slice", arity: FilterArity(2, 2)) { input, arguments, _ in
            let sequence = try input.sequenceInput("slice")
            let count = length(of: sequence)
            let lower = resolve(try arguments.integer(0, range: indexRange), count: count)
            let upper = resolve(try arguments.integer(1, range: indexRange), count: count)
            return slice(sequence, from: lower, to: upper)
        },
        BuiltinFilter("reverse", arity: FilterArity(0, 0)) { input, _, _ in
            switch try input.sequenceInput("reverse") {
            case .list(let items): return .list(items.reversed())
            case .text(let characters): return .string(String(characters.reversed()))
            }
        },
        BuiltinFilter("sort", arity: FilterArity(0, 2)) { input, arguments, _ in
            let items = try input.listInput("sort")
            var field: String?
            var descending = false
            if arguments.count == 1 {
                let first = try arguments.string(0)
                if first == "asc" || first == "desc" {
                    descending = first == "desc"
                } else {
                    field = first
                }
            } else if arguments.count == 2 {
                field = try arguments.string(0)
                descending = try arguments.choice(1, among: ["asc", "desc"]) == "desc"
            }
            let keyed = items.enumerated().map { offset, item in
                (offset: offset, item: item, key: field.map { ValueOrdering.field($0, of: item) } ?? item)
            }
            let sorted = keyed.sorted { lhs, rhs in
                let order = ValueOrdering.compare(lhs.key, rhs.key)
                if order == .orderedSame { return lhs.offset < rhs.offset }
                return descending ? order == .orderedDescending : order == .orderedAscending
            }
            return .list(sorted.map(\.item))
        },
        BuiltinFilter("unique", arity: FilterArity(0, 0)) { input, _, _ in
            var seen = Set<Value>()
            return .list(try input.listInput("unique").filter { seen.insert($0).inserted })
        },
        BuiltinFilter("join", arity: FilterArity(1, 1)) { input, arguments, _ in
            let items = try input.listInput("join")
            let separator = try arguments.string(0)
            return .string(items.map(\.stringified).joined(separator: separator))
        },
    ]

    static func element(of sequence: ValueSequence, at position: Int) -> Value {
        switch sequence {
        case .list(let items):
            return ValueIndexing.element(items, position) ?? .null
        case .text(let characters):
            return ValueIndexing.element(characters, position).map { Value.string(String($0)) } ?? .null
        }
    }

    static func length(of sequence: ValueSequence) -> Int {
        switch sequence {
        case .list(let items): items.count
        case .text(let characters): characters.count
        }
    }

    static func resolve(_ index: Int, count: Int) -> Int {
        index < 0 ? Swift.max(count + index, 0) : index
    }

    static func clamped(_ lower: Int, _ upper: Int, count: Int) -> Range<Int> {
        let start = Swift.min(Swift.max(lower, 0), count)
        let end = Swift.min(Swift.max(upper, start), count)
        return start..<end
    }

    static func slice(_ sequence: ValueSequence, from lower: Int, to upper: Int) -> Value {
        switch sequence {
        case .list(let items):
            return .list(Array(items[clamped(lower, upper, count: items.count)]))
        case .text(let characters):
            return .string(String(characters[clamped(lower, upper, count: characters.count)]))
        }
    }
}
