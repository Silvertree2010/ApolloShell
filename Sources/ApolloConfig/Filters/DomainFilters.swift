import Foundation

enum DomainFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("app-search", arity: FilterArity(1, 1)) { input, arguments, context in
            let apps = try input.listInput("app-search")
            let query = try arguments.optionalString(0) ?? ""
            return .list(context.services.appSearch(apps, query: query))
        },
        BuiltinFilter("month-grid", arity: FilterArity(0, 2)) { input, arguments, context in
            let date = try input.dateInput("month-grid")
            let offset = try arguments.optionalInteger(0, default: 0, range: -12_000...12_000)
            let firstWeekday = try arguments.optionalChoice(1, among: ["monday", "sunday", "system"]) ?? "system"
            return context.services.monthGrid(date, offset: offset, firstWeekday: firstWeekday)
        },
        BuiltinFilter("url", arity: FilterArity(0, 0)) { input, _, context in
            let text = try stringInput(input, filter: "url")
            return context.services.normalizedURL(text).map { Value.string($0) } ?? .null
        },
        BuiltinFilter("symbol-exists", arity: FilterArity(0, 0)) { input, _, context in
            .bool(context.services.symbolExists(try stringInput(input, filter: "symbol-exists")))
        },
        BuiltinFilter("chord", arity: FilterArity(0, 0)) { input, _, context in
            let text = try stringInput(input, filter: "chord")
            guard !text.isEmpty else { return .string("") }
            return .string(context.services.chordDisplay(try chord(text, filter: "chord").canonical))
        },
        BuiltinFilter("hotkey-warning", arity: FilterArity(0, 0)) { input, _, context in
            let text = try stringInput(input, filter: "hotkey-warning")
            guard !text.isEmpty else { return .null }
            let warning = context.services.hotkeyWarning(try chord(text, filter: "hotkey-warning").canonical)
            return warning.map { Value.string($0) } ?? .null
        },
    ]

    static func stringInput(_ input: Value, filter: String) throws -> String {
        guard case .string(let text) = input else { throw FilterFailure.input(filter, expected: "a string", got: input) }
        return text
    }

    static func chord(_ text: String, filter: String) throws -> KeyChord {
        guard let chord = KeyChord.parse(text) else {
            throw FilterFailure("'\(filter)' got an unknown key combination '\(text)'")
        }
        return chord
    }
}
