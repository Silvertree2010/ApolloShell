import ApolloBase
import ApolloKDL

struct FilterStageResult: Sendable {
    var nodes: [ExpandedNode]
    var filters: [String: UserFilter]
    var diagnostics: [Diagnostic]
}

enum FilterStage {
    static let nodeName = "filter"

    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry, templates: TemplateCache, declaredVars: Set<String>? = nil) -> FilterStageResult {
        var remaining: [ExpandedNode] = []
        var filters: [String: UserFilter] = [:]
        var diagnostics: [Diagnostic] = []
        for node in nodes {
            guard node.kdl.name == nodeName else {
                remaining.append(node)
                continue
            }
            var problems: [Diagnostic] = []
            if let (name, filter) = declare(node, registry: registry, templates: templates, declaredVars: declaredVars, known: filters, problems: &problems) {
                filters[name] = filter
                templates.userFilters = filters
            }
            diagnostics += problems.map { DiagnosticCollector.withExpansionChain($0, node: node) }
        }
        return FilterStageResult(nodes: remaining, filters: filters, diagnostics: diagnostics)
    }

    private static func declare(
        _ node: ExpandedNode,
        registry: SchemaRegistry,
        templates: TemplateCache,
        declaredVars: Set<String>?,
        known: [String: UserFilter],
        problems: inout [Diagnostic]
    ) -> (String, UserFilter)? {
        let kdl = node.kdl
        guard kdl.arguments.count == 2, case .string(let name) = kdl.arguments[0].scalar, case .string = kdl.arguments[1].scalar else {
            problems.append(Diagnostic(.error, "filter needs a name and a body, like filter \"double\" \"{value * 2}\"", span: kdl.span, code: .filterDefinition))
            return nil
        }
        let nameSpan = kdl.arguments[0].span
        guard isIdentifier(name) else {
            problems.append(Diagnostic(.error, "filter name '\(name)' must be lowercase letters, digits and dashes", span: nameSpan, code: .filterDefinition))
            return nil
        }
        if registry.filters[name] != nil {
            problems.append(Diagnostic(.error, "'\(name)' is a built-in filter", span: nameSpan, code: .duplicateFilter))
            return nil
        }
        if let first = known[name] {
            problems.append(Diagnostic(.error, "duplicate filter '\(name)'", span: nameSpan, notes: [DiagnosticNote("first defined here", span: first.span)], code: .duplicateFilter))
            return nil
        }
        var parameters: [String] = []
        for property in kdl.properties {
            guard property.name == "args", case .string(let text) = property.value.scalar else {
                problems.append(Diagnostic(.error, "unknown property '\(property.name)' on filter", span: property.span, help: "filter takes only args=\"a b\"", code: .unknownProperty))
                return nil
            }
            parameters = text.split(whereSeparator: \.isWhitespace).map(String.init)
            for parameter in parameters where !isIdentifier(parameter) || parameter == UserFilterExpansion.input {
                problems.append(Diagnostic(.error, "'\(parameter)' cannot be an argument name", span: property.span, code: .filterDefinition))
                return nil
            }
            if Set(parameters).count != parameters.count {
                problems.append(Diagnostic(.error, "argument names must differ", span: property.span, code: .filterDefinition))
                return nil
            }
        }
        if !node.children.isEmpty {
            problems.append(Diagnostic(.error, "filter has no children", span: kdl.span, code: .noChildren))
            return nil
        }
        let env = ExpressionEnvironment(
            registry: registry,
            locals: Set(parameters + [UserFilterExpansion.input]),
            context: .topLevel,
            templates: templates,
            declaredVars: declaredVars
        )
        let (compiled, compileProblems) = ExpressionCompiler.compile(kdl.arguments[1], env: env, allowsExpression: true)
        problems += compileProblems
        guard !compileProblems.contains(where: { $0.severity == .error }) else { return nil }
        guard case .whole(let body) = compiled.template else {
            problems.append(Diagnostic(.error, "a filter body is one {…} expression", span: kdl.arguments[1].span, code: .filterDefinition))
            return nil
        }
        return (name, UserFilter(parameters: parameters, body: body, span: nameSpan))
    }

    private static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, ("a"..."z").contains(first) else { return false }
        return text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }
}
