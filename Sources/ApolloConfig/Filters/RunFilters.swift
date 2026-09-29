import Foundation

enum RunFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("runs", arity: FilterArity(1, 1)) { input, arguments, _ in
            let items = try input.listInput("runs")
            let field = try arguments.string(0)
            return .list(runs(items, field: field).map(Value.list))
        },
    ]

    static func runs(_ items: [Value], field: String) -> [[Value]] {
        var result: [[Value]] = []
        for item in items {
            if !result.isEmpty, ValueOrdering.field(field, of: item).isTruthy {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
            }
        }
        return result
    }
}
