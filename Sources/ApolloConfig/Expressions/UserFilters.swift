import ApolloBase

struct UserFilter: Sendable, Hashable {
    var parameters: [String]
    var body: Expr
    var span: SourceSpan
}

enum UserFilterExpansion {
    static let input = "value"

    static let maximumNodes = 4096

    static func apply(_ template: StringTemplate, filters: [String: UserFilter], overflowed: inout Bool) -> StringTemplate {
        guard !filters.isEmpty else { return template }
        switch template {
        case .literal:
            return template
        case .whole(let expr):
            return .whole(apply(expr, filters: filters, overflowed: &overflowed))
        case .parts(let parts):
            return .parts(parts.map { part in
                guard case .expression(let expr) = part else { return part }
                return .expression(apply(expr, filters: filters, overflowed: &overflowed))
            })
        }
    }

    static func apply(_ expr: Expr, filters: [String: UserFilter], overflowed: inout Bool) -> Expr {
        var overflow = overflowed
        let result = map(expr) { node in
            guard !overflow, case .pipe(let input, let call) = node, let filter = filters[call.name], call.arguments.count == filter.parameters.count else { return nil }
            var bindings = [Self.input: apply(input, filters: filters, overflowed: &overflow)]
            for (name, argument) in zip(filter.parameters, call.arguments) {
                bindings[name] = apply(argument, filters: filters, overflowed: &overflow)
            }
            guard !overflow else { return node }
            let expanded = substitute(filter.body, bindings)
            guard nodeCount(expanded, atMost: maximumNodes) < maximumNodes else {
                overflow = true
                return node
            }
            return expanded
        }
        overflowed = overflow
        return result
    }

    static func nodeCount(_ expr: Expr, atMost limit: Int) -> Int {
        var count = 0
        var pending = [expr]
        while let next = pending.popLast() {
            count += 1
            if count >= limit { return limit }
            switch next {
            case .literal:
                break
            case .list(let items):
                pending.append(contentsOf: items)
            case .path(_, let members):
                pending.append(contentsOf: indexExpressions(members))
            case .access(let base, let members):
                pending.append(base)
                pending.append(contentsOf: indexExpressions(members))
            case .unary(_, let operand):
                pending.append(operand)
            case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
                pending.append(lhs)
                pending.append(rhs)
            case .conditional(let condition, let then, let otherwise):
                pending.append(condition)
                pending.append(then)
                pending.append(otherwise)
            case .pipe(let input, let call):
                pending.append(input)
                pending.append(contentsOf: call.arguments)
            }
        }
        return count
    }

    static func filterNames(in template: ValueTemplate) -> [String] {
        var names: [String] = []
        var templates = [template]
        while let next = templates.popLast() {
            switch next {
            case .scalar(let compiled):
                names += filterNames(in: compiled.template)
            case .list(let items):
                templates.append(contentsOf: items)
            case .record(let fields):
                templates.append(contentsOf: fields.map(\.value))
            }
        }
        return names
    }

    static func filterNames(in template: StringTemplate) -> [String] {
        var pending: [Expr]
        switch template {
        case .literal: return []
        case .whole(let expr): pending = [expr]
        case .parts(let parts): pending = parts.compactMap { part in
            guard case .expression(let expr) = part else { return nil }
            return expr
        }
        }
        var names: [String] = []
        while let next = pending.popLast() {
            switch next {
            case .literal:
                break
            case .list(let items):
                pending.append(contentsOf: items)
            case .path(_, let members):
                pending.append(contentsOf: indexExpressions(members))
            case .access(let base, let members):
                pending.append(base)
                pending.append(contentsOf: indexExpressions(members))
            case .unary(_, let operand):
                pending.append(operand)
            case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
                pending.append(lhs)
                pending.append(rhs)
            case .conditional(let condition, let then, let otherwise):
                pending.append(condition)
                pending.append(then)
                pending.append(otherwise)
            case .pipe(let input, let call):
                names.append(call.name)
                pending.append(input)
                pending.append(contentsOf: call.arguments)
            }
        }
        return names
    }

    private static func indexExpressions(_ members: [PathMember]) -> [Expr] {
        members.compactMap { member in
            guard case .index(let index) = member else { return nil }
            return index
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
