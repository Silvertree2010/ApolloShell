import ApolloBase
import ApolloKDL

struct ExpressionEnvironment: Sendable {
    var registry: SchemaRegistry
    var letValues: [String: Value]
    var locals: Set<String>
    var context: NodeContext
}

enum ExpressionCompiler {
    static func compile(_ kdlValue: KDLValue, env: ExpressionEnvironment, allowsExpression: Bool) -> (CompiledValue, [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        switch kdlValue.scalar {
        case .number(let number, _):
            return (CompiledValueBuilder.literal(number.isFinite ? .number(number) : .null, span: kdlValue.span), diagnostics)
        case .bool(let flag):
            return (CompiledValueBuilder.literal(.bool(flag), span: kdlValue.span), diagnostics)
        case .null:
            return (CompiledValueBuilder.literal(.null, span: kdlValue.span), diagnostics)
        case .string(let text):
            guard text.contains("{") else {
                return (CompiledValueBuilder.literal(.string(text), span: kdlValue.span), diagnostics)
            }
            if !allowsExpression {
                diagnostics.append(Diagnostic(.error, "no expression allowed here", span: kdlValue.span))
                return (CompiledValueBuilder.literal(.string(text), span: kdlValue.span), diagnostics)
            }
            switch ExpressionParser.parseTemplate(text, span: kdlValue.span) {
            case .failure(let diagnostic):
                diagnostics.append(diagnostic)
                return (CompiledValueBuilder.literal(.null, span: kdlValue.span), diagnostics)
            case .success(let template):
                let substituted = LetSubstitution.apply(template, lets: env.letValues, locals: env.locals)
                diagnostics.append(contentsOf: validate(substituted, env: env, fallback: kdlValue.span))
                let dependencies = substituted.dependencies(locals: env.locals)
                return (CompiledValue(template: substituted, dependencies: dependencies, span: kdlValue.span), diagnostics)
            }
        }
    }

    private static func validate(_ template: StringTemplate, env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        switch template {
        case .literal:
            return []
        case .whole(let expr):
            return validate(expr, env: env, fallback: fallback)
        case .parts(let parts):
            var diagnostics: [Diagnostic] = []
            for part in parts {
                if case .expression(let expr) = part {
                    diagnostics.append(contentsOf: validate(expr, env: env, fallback: fallback))
                }
            }
            return diagnostics
        }
    }

    private static func validate(_ expr: Expr, env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        switch expr {
        case .literal:
            return []
        case .list(let items):
            return items.flatMap { validate($0, env: env, fallback: fallback) }
        case .path(let root, let members):
            var diagnostics = validateRoot(root, env: env, fallback: fallback)
            diagnostics.append(contentsOf: validateFirstField(root: root, members: members, env: env, fallback: fallback))
            diagnostics.append(contentsOf: members.flatMap { validate($0, env: env, fallback: fallback) })
            return diagnostics
        case .access(let base, let members):
            return validate(base, env: env, fallback: fallback) + members.flatMap { validate($0, env: env, fallback: fallback) }
        case .unary(_, let operand):
            return validate(operand, env: env, fallback: fallback)
        case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
            return validate(lhs, env: env, fallback: fallback) + validate(rhs, env: env, fallback: fallback)
        case .conditional(let condition, let then, let otherwise):
            return validate(condition, env: env, fallback: fallback) + validate(then, env: env, fallback: fallback) + validate(otherwise, env: env, fallback: fallback)
        case .pipe(let input, let call):
            return validate(input, env: env, fallback: fallback) + validate(call, env: env, fallback: fallback)
        }
    }

    private static func validate(_ member: PathMember, env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        guard case .index(let expr) = member else { return [] }
        return validate(expr, env: env, fallback: fallback)
    }

    private static func validateRoot(_ root: String, env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        if env.locals.contains(root) { return [] }
        if root == "var" { return [] }
        if let provider = env.registry.providers[root] {
            if provider.stability == .experimental {
                return [Diagnostic(.note, "'\(root)' is experimental and may change", span: fallback)]
            }
            return []
        }
        if let contextRoot = env.registry.contextRoots[root] {
            if !contextRoot.validIn.contains(env.context.rawValue) {
                return [Diagnostic(.error, "'\(root)' is not valid here", span: fallback)]
            }
            return []
        }
        if env.registry.reservedProviderNames.contains(root) {
            return [Diagnostic(.error, "unknown root '\(root)'", span: fallback, help: "'\(root)' will be a provider in a later version")]
        }
        let candidates = Array(env.locals) + Array(env.registry.providers.keys) + Array(env.registry.contextRoots.keys) + ["var"]
        let suggestion = Suggestion.closest(to: root, among: candidates)
        return [Diagnostic(.error, "unknown root '\(root)'", span: fallback, help: suggestion.map { "did you mean '\($0)'?" })]
    }

    private static func validateFirstField(root: String, members: [PathMember], env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        guard case .field(let first)? = members.first else { return [] }
        let fields: [FieldSchema]
        if let provider = env.registry.providers[root] {
            fields = provider.fields
        } else if let contextRoot = env.registry.contextRoots[root] {
            fields = contextRoot.fields
        } else {
            return []
        }
        guard !fields.isEmpty else { return [] }
        let names = Set(fields.map { $0.path[0] })
        if names.contains(first) { return [] }
        let suggestion = Suggestion.closest(to: first, among: Array(names))
        return [Diagnostic(.error, "unknown field '\(first)' on '\(root)'", span: fallback, help: suggestion.map { "did you mean '\($0)'?" })]
    }

    private static func validate(_ call: FilterCall, env: ExpressionEnvironment, fallback: SourceSpan) -> [Diagnostic] {
        var diagnostics = call.arguments.flatMap { validate($0, env: env, fallback: fallback) }
        if call.name == "lua" {
            diagnostics.append(Diagnostic(.error, "Lua scripting comes in a later version", span: call.span))
            return diagnostics
        }
        guard let schema = env.registry.filters[call.name] else {
            let suggestion = Suggestion.closest(to: call.name, among: Array(env.registry.filters.keys))
            diagnostics.append(Diagnostic(.error, "unknown filter '\(call.name)'", span: call.span, help: suggestion.map { "did you mean '\($0)'?" }))
            return diagnostics
        }
        if schema.stability == .experimental {
            diagnostics.append(Diagnostic(.note, "'\(call.name)' is experimental and may change", span: call.span))
        }
        let minimum = schema.arguments.filter(\.required).count
        let maximum = schema.arguments.count
        if call.arguments.count < minimum || call.arguments.count > maximum {
            let phrase = minimum == maximum ? "\(minimum) argument\(minimum == 1 ? "" : "s")" : "\(minimum) to \(maximum) arguments"
            diagnostics.append(Diagnostic(.error, "'\(call.name)' expects \(phrase)", span: call.span))
        }
        return diagnostics
    }
}

enum LetSubstitution {
    static func apply(_ template: StringTemplate, lets: [String: Value], locals: Set<String>) -> StringTemplate {
        guard !lets.isEmpty else { return template }
        switch template {
        case .literal:
            return template
        case .whole(let expr):
            return .whole(apply(expr, lets: lets, locals: locals))
        case .parts(let parts):
            return .parts(parts.map { part in
                guard case .expression(let expr) = part else { return part }
                return .expression(apply(expr, lets: lets, locals: locals))
            })
        }
    }

    static func apply(_ expr: Expr, lets: [String: Value], locals: Set<String>) -> Expr {
        switch expr {
        case .literal:
            return expr
        case .list(let items):
            return .list(items.map { apply($0, lets: lets, locals: locals) })
        case .path(let root, let members):
            let newMembers = members.map { substituteMember($0, lets: lets, locals: locals) }
            if !locals.contains(root), let value = lets[root] {
                return .access(.literal(value), newMembers)
            }
            return .path(root: root, members: newMembers)
        case .access(let base, let members):
            return .access(apply(base, lets: lets, locals: locals), members.map { substituteMember($0, lets: lets, locals: locals) })
        case .unary(let op, let operand):
            return .unary(op, apply(operand, lets: lets, locals: locals))
        case .binary(let op, let lhs, let rhs):
            return .binary(op, apply(lhs, lets: lets, locals: locals), apply(rhs, lets: lets, locals: locals))
        case .conditional(let condition, let then, let otherwise):
            return .conditional(apply(condition, lets: lets, locals: locals), apply(then, lets: lets, locals: locals), apply(otherwise, lets: lets, locals: locals))
        case .coalesce(let lhs, let rhs):
            return .coalesce(apply(lhs, lets: lets, locals: locals), apply(rhs, lets: lets, locals: locals))
        case .pipe(let input, let call):
            let newCall = FilterCall(name: call.name, arguments: call.arguments.map { apply($0, lets: lets, locals: locals) }, span: call.span)
            return .pipe(apply(input, lets: lets, locals: locals), newCall)
        }
    }

    private static func substituteMember(_ member: PathMember, lets: [String: Value], locals: Set<String>) -> PathMember {
        guard case .index(let expr) = member else { return member }
        return .index(apply(expr, lets: lets, locals: locals))
    }
}
