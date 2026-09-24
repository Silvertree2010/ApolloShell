enum OtherFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("default", arity: FilterArity(1, 1), nullInput: .accept) { input, arguments, _ in
            if case .null = input {
                return arguments.value(0)
            }
            return input
        },
        BuiltinFilter("bool", arity: FilterArity(0, 0), nullInput: .accept) { input, _, _ in
            .bool(input.isTruthy)
        },
        BuiltinFilter("keys", arity: FilterArity(0, 0)) { input, _, _ in
            .list(try input.recordInput("keys").keys.map { .string($0) })
        },
        BuiltinFilter("values", arity: FilterArity(0, 0)) { input, _, _ in
            .list(try input.recordInput("values").values)
        },
    ]
}
