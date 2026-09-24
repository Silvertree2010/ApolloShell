import Foundation

struct FilterFailure: Error, Sendable, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    static func input(_ filter: String, expected: String, got value: Value) -> FilterFailure {
        FilterFailure("'\(filter)' expects \(expected), got \(value.typeName)")
    }
}

enum NullInput: Sendable {
    case propagate
    case accept
}

struct BuiltinFilter: Sendable {
    let name: String
    let arity: FilterArity
    let nullInput: NullInput
    let body: @Sendable (Value, FilterArguments, FilterContext) throws -> Value

    init(
        _ name: String,
        arity: FilterArity,
        nullInput: NullInput = .propagate,
        body: @escaping @Sendable (Value, FilterArguments, FilterContext) throws -> Value
    ) {
        self.name = name
        self.arity = arity
        self.nullInput = nullInput
        self.body = body
    }

    func run(_ input: Value, _ arguments: [Value], _ context: FilterContext) -> FilterResult {
        guard arity.accepts(arguments.count) else {
            return .failure("'\(name)' takes \(arity.phrase), got \(arguments.count)")
        }
        if case .null = input, nullInput == .propagate {
            return .value(.null)
        }
        do {
            return .value(try body(input, FilterArguments(filter: name, values: arguments), context))
        } catch let failure as FilterFailure {
            return .failure(failure.message)
        } catch {
            return .failure("'\(name)' failed: \(error)")
        }
    }
}

struct FilterArguments: Sendable {
    let filter: String
    let values: [Value]

    var count: Int { values.count }

    func value(_ index: Int) -> Value {
        index < values.count ? values[index] : .null
    }

    func number(_ index: Int) throws -> Double {
        guard case .number(let number) = value(index) else { throw mismatch(index, expected: "a number") }
        return number
    }

    func integer(_ index: Int, range: ClosedRange<Int>) throws -> Int {
        let number = try self.number(index)
        guard let whole = ValueIndexing.wholeNumber(number), range.contains(whole) else {
            throw FilterFailure("'\(filter)' expects a whole number from \(range.lowerBound) to \(range.upperBound) as argument \(index + 1)")
        }
        return whole
    }

    func optionalInteger(_ index: Int, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        if case .null = value(index) { return fallback }
        return try integer(index, range: range)
    }

    func string(_ index: Int) throws -> String {
        guard case .string(let text) = value(index) else { throw mismatch(index, expected: "a string") }
        return text
    }

    func optionalString(_ index: Int) throws -> String? {
        if case .null = value(index) { return nil }
        return try string(index)
    }

    func choice(_ index: Int, among choices: [String]) throws -> String {
        let text = try string(index)
        guard choices.contains(text) else {
            throw FilterFailure("'\(filter)' expects \(Self.alternatives(choices)) as argument \(index + 1), got '\(text)'")
        }
        return text
    }

    func optionalChoice(_ index: Int, among choices: [String]) throws -> String? {
        if case .null = value(index) { return nil }
        return try choice(index, among: choices)
    }

    private func mismatch(_ index: Int, expected: String) -> FilterFailure {
        FilterFailure("'\(filter)' expects \(expected) as argument \(index + 1), got \(value(index).typeName)")
    }

    static func alternatives(_ choices: [String]) -> String {
        let quoted = choices.map { "'\($0)'" }
        guard quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " or " + quoted[quoted.count - 1]
    }
}

enum ValueSequence {
    case list([Value])
    case text([Character])
}

extension Value {
    func numberInput(_ filter: String) throws -> Double {
        guard case .number(let number) = self else { throw FilterFailure.input(filter, expected: "a number", got: self) }
        return number
    }

    func textInput(_ filter: String) throws -> String {
        switch self {
        case .string(let text): return text
        case .number, .bool: return stringified
        default: throw FilterFailure.input(filter, expected: "a string", got: self)
        }
    }

    func listInput(_ filter: String) throws -> [Value] {
        guard case .list(let items) = self else { throw FilterFailure.input(filter, expected: "a list", got: self) }
        return items
    }

    func recordInput(_ filter: String) throws -> Record {
        guard case .record(let record) = self else { throw FilterFailure.input(filter, expected: "a record", got: self) }
        return record
    }

    func dateInput(_ filter: String) throws -> Date {
        guard case .date(let date) = self else { throw FilterFailure.input(filter, expected: "a date", got: self) }
        return date
    }

    func sequenceInput(_ filter: String) throws -> ValueSequence {
        switch self {
        case .list(let items): return .list(items)
        case .string(let text): return .text(Array(text))
        default: throw FilterFailure.input(filter, expected: "a list or a string", got: self)
        }
    }
}
