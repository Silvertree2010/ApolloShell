import ApolloBase
import ApolloKDL

struct ExpressionEnvironment: Sendable {
    var registry: SchemaRegistry
    var locals: Set<String>
    var context: NodeContext
    var templates: TemplateCache? = nil
    var declaredVars: Set<String>? = nil
}

enum ExpressionText {
    static func containsExpression(_ text: String) -> Bool {
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "{" else { continue }
            guard iterator.next() == "{" else { return true }
        }
        return false
    }

    static func isPlainQuoted(_ text: String, span: SourceSpan) -> Bool {
        !span.isSynthetic
            && span.start.line == span.end.line
            && span.end.offset - span.start.offset == text.utf8.count + 2
    }
}

struct NameOccurrence: Sendable {
    var root: SourceSpan
    var fields: [SourceSpan]
}

enum NameLocator {
    static func occurrences(in text: String, span: SourceSpan) -> [String: [NameOccurrence]] {
        guard ExpressionText.isPlainQuoted(text, span: span) else { return [:] }
        let characters = Array(text)
        let mapper = ExpressionSpanMapper(base: span, characters: characters, origin: 0)
        var result: [String: [NameOccurrence]] = [:]
        var index = 0
        while index < characters.count {
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if (characters[index] == "{" && next == "{") || (characters[index] == "}" && next == "}") {
                index += 2
                continue
            }
            guard characters[index] == "{" else {
                index += 1
                continue
            }
            guard case .success(let close) = ExpressionParser.closingBrace(characters, openingAt: index) else { return result }
            let inner = Array(characters[(index + 1)..<close])
            let local = mapper.shifted(to: index + 1)
            if let tokens = try? ExpressionLexer.scan(inner) {
                collect(tokens, mapper: local, into: &result)
            }
            index = close + 1
        }
        return result
    }

    private static func collect(_ tokens: [ExpressionToken], mapper: ExpressionSpanMapper, into result: inout [String: [NameOccurrence]]) {
        for (position, token) in tokens.enumerated() {
            guard case .name(let name) = token.kind else { continue }
            if position > 0, tokens[position - 1].isSymbol(".") || tokens[position - 1].isSymbol("|") { continue }
            var fields: [SourceSpan] = []
            var cursor = position + 1
            while cursor + 1 < tokens.count, tokens[cursor].isSymbol("."), case .name = tokens[cursor + 1].kind {
                fields.append(mapper.span(from: tokens[cursor + 1].start, to: tokens[cursor + 1].end))
                cursor += 2
            }
            result[name, default: []].append(NameOccurrence(root: mapper.span(from: token.start, to: token.end), fields: fields))
        }
    }
}

enum ExpressionCompiler {
    static func compile(_ kdlValue: KDLValue, env: ExpressionEnvironment, allowsExpression: Bool, validates: Bool = true) -> (CompiledValue, [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        switch kdlValue.scalar {
        case .number(let number, _):
            return (CompiledValueBuilder.literal(number.isFinite ? .number(number) : .null, span: kdlValue.span), diagnostics)
        case .bool(let flag):
            return (CompiledValueBuilder.literal(.bool(flag), span: kdlValue.span), diagnostics)
        case .null:
            return (CompiledValueBuilder.literal(.null, span: kdlValue.span), diagnostics)
        case .string(let text):
            guard text.utf8.contains(UInt8(ascii: "{")), allowsExpression || ExpressionText.containsExpression(text) else {
                return (CompiledValueBuilder.literal(.string(text), span: kdlValue.span), diagnostics)
            }
            if !allowsExpression {
                diagnostics.append(Diagnostic(.error, "no expression allowed here", span: kdlValue.span, code: .expressionNotAllowed))
                return (CompiledValueBuilder.literal(.string(text), span: kdlValue.span), diagnostics)
            }
            switch env.templates?.template(text, span: kdlValue.span) ?? ExpressionParser.parseTemplate(text, span: kdlValue.span) {
            case .failure(var diagnostic):
                if !ExpressionText.isPlainQuoted(text, span: kdlValue.span) {
                    diagnostic.span = kdlValue.span
                }
                diagnostics.append(diagnostic)
                return (CompiledValueBuilder.literal(.null, span: kdlValue.span), diagnostics)
            case .success(let template):
                let userFilters = env.templates?.userFilters ?? [:]
                var overflowed = false
                let expanded = UserFilterExpansion.apply(template, filters: userFilters, overflowed: &overflowed)
                if overflowed {
                    diagnostics.append(Diagnostic(.error, "this expression grows past \(UserFilterExpansion.maximumNodes) parts once its filters are expanded", span: kdlValue.span, code: .expressionTooLarge))
                    return (CompiledValueBuilder.literal(.null, span: kdlValue.span), diagnostics)
                }
                guard validates else {
                    return (CompiledValue(template: expanded, dependencies: [], span: kdlValue.span), diagnostics)
                }
                let span = kdlValue.span
                let templates = env.templates
                var validator = ExpressionValidator(env: env, userFilters: userFilters, fallback: span) {
                    templates?.occurrences(in: text, span: span) ?? NameLocator.occurrences(in: text, span: span)
                }
                validator.validate(template)
                diagnostics.append(contentsOf: validator.diagnostics)
                let dependencies = expanded.dependencies(locals: env.locals)
                return (CompiledValue(template: expanded, dependencies: dependencies, span: kdlValue.span), diagnostics)
            }
        }
    }
}

private struct ExpressionValidator {
    let env: ExpressionEnvironment
    let userFilters: [String: UserFilter]
    let fallback: SourceSpan
    let locate: () -> [String: [NameOccurrence]]
    var located: [String: [NameOccurrence]]?
    var visits: [String: Int] = [:]
    var diagnostics: [Diagnostic] = []

    init(env: ExpressionEnvironment, userFilters: [String: UserFilter] = [:], fallback: SourceSpan, locate: @escaping () -> [String: [NameOccurrence]]) {
        self.env = env
        self.userFilters = userFilters
        self.fallback = fallback
        self.locate = locate
    }

    mutating func validate(_ template: StringTemplate) {
        switch template {
        case .literal:
            return
        case .whole(let expr):
            validate(expr)
        case .parts(let parts):
            for part in parts {
                if case .expression(let expr) = part {
                    validate(expr)
                }
            }
        }
    }

    private mutating func validate(_ expr: Expr) {
        switch expr {
        case .literal:
            return
        case .list(let items):
            items.forEach { validate($0) }
        case .path(let root, let members):
            let visit = visits[root, default: 0]
            visits[root] = visit + 1
            validateRoot(root, visit: visit)
            validateFirstField(root: root, members: members, visit: visit)
            members.forEach { validate($0) }
        case .access(let base, let members):
            validate(base)
            members.forEach { validate($0) }
        case .unary(_, let operand):
            validate(operand)
        case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
            validate(lhs)
            validate(rhs)
        case .conditional(let condition, let then, let otherwise):
            validate(condition)
            validate(then)
            validate(otherwise)
        case .pipe(let input, let call):
            validate(input)
            validate(call)
        }
    }

    private mutating func occurrence(of root: String, visit: Int) -> NameOccurrence? {
        if located == nil { located = locate() }
        guard let list = located?[root], visit < list.count else { return nil }
        return list[visit]
    }

    private mutating func rootSpan(_ root: String, visit: Int) -> SourceSpan {
        occurrence(of: root, visit: visit)?.root ?? fallback
    }

    private mutating func validate(_ member: PathMember) {
        guard case .index(let expr) = member else { return }
        validate(expr)
    }

    private mutating func validateRoot(_ root: String, visit: Int) {
        if env.locals.contains(root) || root == "var" { return }
        if let provider = env.registry.providers[root] {
            if provider.stability == .experimental {
                diagnostics.append(Diagnostic(.note, "'\(root)' is experimental and may change", span: rootSpan(root, visit: visit), code: .experimental))
            }
            return
        }
        if let contextRoot = env.registry.contextRoots[root] {
            if !contextRoot.validIn.contains(env.context.rawValue) {
                diagnostics.append(Diagnostic(.error, "'\(root)' is not valid here", span: rootSpan(root, visit: visit), code: .unknownRoot))
            }
            return
        }
        if env.registry.reservedProviderNames.contains(root) {
            diagnostics.append(Diagnostic(.error, "unknown root '\(root)'", span: rootSpan(root, visit: visit), help: "'\(root)' will be a provider in a later version", code: .unknownRoot))
            return
        }
        let candidates = Array(env.locals) + Array(env.registry.providers.keys) + Array(env.registry.contextRoots.keys) + ["var"]
        let suggestion = Suggestion.closest(to: root, among: candidates)
        diagnostics.append(Diagnostic(.error, "unknown root '\(root)'", span: rootSpan(root, visit: visit), help: suggestion.map { "did you mean '\($0)'?" }, code: .unknownRoot))
    }

    static let rootsKeyedById: Set<String> = ["surfaces"]

    private mutating func fieldSpan(_ root: String, visit: Int, position: Int) -> SourceSpan {
        let fields = occurrence(of: root, visit: visit)?.fields ?? []
        return position < fields.count ? fields[position] : fallback
    }

    private mutating func validateFirstField(root: String, members: [PathMember], visit: Int) {
        guard !env.locals.contains(root) else { return }
        let position = Self.rootsKeyedById.contains(root) ? 1 : 0
        guard position < members.count, case .field(let first) = members[position] else { return }
        if root == "var", let declared = env.declaredVars {
            guard !declared.contains(first) else { return }
            let suggestion = Suggestion.closest(to: first, among: Array(declared))
            diagnostics.append(Diagnostic(.warning, "unknown var '\(first)'", span: fieldSpan(root, visit: visit, position: position), help: suggestion.map { "did you mean '\($0)'?" }, code: .unknownVar))
            return
        }
        let fields: [FieldSchema]
        if let provider = env.registry.providers[root] {
            fields = provider.fields
        } else if let contextRoot = env.registry.contextRoots[root] {
            fields = contextRoot.fields
        } else {
            return
        }
        guard !fields.isEmpty else { return }
        let names = Set(fields.map { $0.path[0] })
        if names.contains(first) { return }
        let suggestion = Suggestion.closest(to: first, among: Array(names))
        diagnostics.append(Diagnostic(.error, "unknown field '\(first)' on '\(root)'", span: fieldSpan(root, visit: visit, position: position), help: suggestion.map { "did you mean '\($0)'?" }, code: .unknownField))
    }

    private mutating func validate(_ call: FilterCall) {
        call.arguments.forEach { validate($0) }
        if call.name == "lua" {
            diagnostics.append(Diagnostic(.error, "Lua scripting comes in a later version", span: call.span, code: .luaReserved))
            return
        }
        if let filter = userFilters[call.name] {
            if call.arguments.count != filter.parameters.count {
                let count = filter.parameters.count
                diagnostics.append(Diagnostic(.error, "'\(call.name)' expects \(count) argument\(count == 1 ? "" : "s")", span: call.span, code: .filterArguments))
            }
            return
        }
        guard let schema = env.registry.filters[call.name] else {
            let suggestion = Suggestion.closest(to: call.name, among: Array(env.registry.filters.keys) + Array(userFilters.keys))
            diagnostics.append(Diagnostic(.error, "unknown filter '\(call.name)'", span: call.span, help: suggestion.map { "did you mean '\($0)'?" }, code: .unknownFilter))
            return
        }
        if schema.stability == .experimental {
            diagnostics.append(Diagnostic(.note, "'\(call.name)' is experimental and may change", span: call.span, code: .experimental))
        }
        let minimum = schema.arguments.filter(\.required).count
        let maximum = schema.arguments.count
        if call.arguments.count < minimum || call.arguments.count > maximum {
            let phrase = minimum == maximum ? "\(minimum) argument\(minimum == 1 ? "" : "s")" : "\(minimum) to \(maximum) arguments"
            diagnostics.append(Diagnostic(.error, "'\(call.name)' expects \(phrase)", span: call.span, code: .filterArguments))
        }
    }
}
