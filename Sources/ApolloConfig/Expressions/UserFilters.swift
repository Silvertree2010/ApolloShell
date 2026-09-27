import ApolloBase

struct UserFilter: Sendable, Hashable {
    var parameters: [String]
    var body: Expr
    var span: SourceSpan
}

enum UserFilterExpansion {
    static let input = "value"

    static func apply(_ template: StringTemplate, filters: [String: UserFilter]) -> StringTemplate {
        guard !filters.isEmpty else { return template }
        switch template {
        case .literal:
            return template
        case .whole(let expr):
            return .whole(apply(expr, filters: filters))
        case .parts(let parts):
            return .parts(parts.map { part in
                guard case .expression(let expr) = part else { return part }
                return .expression(apply(expr, filters: filters))
            })
        }
    }

    static func apply(_ expr: Expr, filters: [String: UserFilter]) -> Expr {
        map(expr) { node in
            guard case .pipe(let input, let call) = node, let filter = filters[call.name], call.arguments.count == filter.parameters.count else { return nil }
            var bindings = [Self.input: apply(input, filters: filters)]
            for (name, argument) in zip(filter.parameters, call.arguments) {
                bindings[name] = apply(argument, filters: filters)
            }
            return substitute(filter.body, bindings)
        }
    }

    static func substitute(_ expr: Expr, _ bindings: [String: Expr]) -> Expr {
        map(expr) { node in
            guard case .path(let root, let members) = node, let replacement = bindings[root] else { return nil }
            let rewritten = members.map { member -> PathMember in
                guard case .index(let index) = member else { return member }
                return .index(substitute(index, bindings))
            }
            return rewritten.isEmpty ? replacement : .access(replacement, rewritten)
        }
    }

    private static func map(_ expr: Expr, _ transform: (Expr) -> Expr?) -> Expr {
        if let replaced = transform(expr) { return replaced }
        switch expr {
        case .literal:
            return expr
        case .list(let items):
            return .list(items.map { map($0, transform) })
        case .path(let root, let members):
            return .path(root: root, members: members.map { map($0, transform) })
        case .access(let base, let members):
            return .access(map(base, transform), members.map { map($0, transform) })
        case .unary(let op, let operand):
            return .unary(op, map(operand, transform))
        case .binary(let op, let lhs, let rhs):
            return .binary(op, map(lhs, transform), map(rhs, transform))
        case .conditional(let condition, let then, let otherwise):
            return .conditional(map(condition, transform), map(then, transform), map(otherwise, transform))
        case .coalesce(let lhs, let rhs):
            return .coalesce(map(lhs, transform), map(rhs, transform))
        case .pipe(let input, let call):
            var mapped = call
            mapped.arguments = call.arguments.map { map($0, transform) }
            return .pipe(map(input, transform), mapped)
        }
    }

    private static func map(_ member: PathMember, _ transform: (Expr) -> Expr?) -> PathMember {
        guard case .index(let index) = member else { return member }
        return .index(map(index, transform))
    }
}
