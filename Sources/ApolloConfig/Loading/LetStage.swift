import Foundation
import ApolloBase
import ApolloKDL

struct LetStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
    var values: [String: Value]
}

private struct LetScope {
    var values: [String: Value]
    var poisoned: Set<String>
    var declaredHere: Set<String> = []

    func entering() -> LetScope {
        LetScope(values: values, poisoned: poisoned)
    }

    func isVisible(_ name: String) -> Bool {
        values[name] != nil || poisoned.contains(name)
    }
}

private struct LetEvalScope: EvaluationScope {
    let values: [String: Value]

    func local(_ name: String) -> Value? {
        values[name]
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        .null
    }
}

enum LetStage {
    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry, filters: FilterTable = .builtin) -> LetStageResult {
        StackHeadroom.run {
            var diagnostics: [Diagnostic] = []
            var values: [String: Value] = [:]
            let evaluator = Evaluator(filters: filters, context: { fixedContext() }, warn: { _ in })
            let resultNodes = process(nodes, inherited: LetScope(values: [:], poisoned: []), registry: registry, evaluator: evaluator, diagnostics: &diagnostics, values: &values)
            return LetStageResult(nodes: resultNodes, diagnostics: diagnostics, values: values)
        }
    }

    private static func process(
        _ nodes: [ExpandedNode],
        inherited: LetScope,
        registry: SchemaRegistry,
        evaluator: Evaluator,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value]
    ) -> [ExpandedNode] {
        var scope = inherited.entering()
        var result: [ExpandedNode] = []
        for node in nodes {
            if node.kdl.name == "let" {
                handleLet(node, scope: &scope, registry: registry, evaluator: evaluator, diagnostics: &diagnostics, values: &values)
                continue
            }
            var copy = node
            copy.letValues = scope.values
            copy.poisonedLets = scope.poisoned
            copy.children = process(node.children, inherited: scope, registry: registry, evaluator: evaluator, diagnostics: &diagnostics, values: &values)
            result.append(copy)
        }
        return result
    }

    private static func handleLet(
        _ node: ExpandedNode,
        scope: inout LetScope,
        registry: SchemaRegistry,
        evaluator: Evaluator,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value]
    ) {
        let kdl = node.kdl
        if kdl.arguments.count == 1, case .string(let name) = kdl.arguments[0].scalar, kdl.properties.isEmpty, !node.children.isEmpty {
            let attached = node.reattachingChildren()
            declare(
                name: name,
                nameSpan: kdl.arguments[0].span,
                node: node,
                scope: &scope,
                registry: registry,
                evaluator: evaluator,
                diagnostics: &diagnostics,
                values: &values
            ) { locals in
                ValueTemplateKDLMapping.template(from: attached, locals: locals)
            }
            return
        }
        if !kdl.arguments.isEmpty || !node.children.isEmpty {
            diagnostics.append(DiagnosticCollector.withExpansionChain(Diagnostic(
                .error,
                "'let' must be written as 'let name=value ...' or 'let name { ... }'",
                span: kdl.span
            ), node: node))
            return
        }
        guard !kdl.properties.isEmpty else {
            diagnostics.append(DiagnosticCollector.withExpansionChain(Diagnostic(.error, "'let' needs at least one constant", span: kdl.span), node: node))
            return
        }
        for property in kdl.properties {
            declare(
                name: property.name,
                nameSpan: property.span,
                node: node,
                scope: &scope,
                registry: registry,
                evaluator: evaluator,
                diagnostics: &diagnostics,
                values: &values
            ) { locals in
                ValueTemplateKDLMapping.scalarTemplate(property.value, locals: locals).map { .scalar($0) }
            }
        }
    }

    private static func declare(
        name: String,
        nameSpan: SourceSpan,
        node: ExpandedNode,
        scope: inout LetScope,
        registry: SchemaRegistry,
        evaluator: Evaluator,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value],
        build: (Set<String>) -> Result<ValueTemplate, Diagnostic>
    ) {
        func report(_ diagnostic: Diagnostic) {
            diagnostics.append(DiagnosticCollector.withExpansionChain(diagnostic, node: node))
        }
        if registry.fixedRoots.contains(name) || registry.providers[name] != nil {
            report(Diagnostic(.error, "'\(name)' is reserved", span: nameSpan))
            return
        }
        if registry.reservedProviderNames.contains(name) {
            report(Diagnostic(.note, "'\(name)' hides provider '\(name)'", span: nameSpan))
        }
        if scope.declaredHere.contains(name) {
            report(Diagnostic(.error, "duplicate 'let' '\(name)' in this scope", span: nameSpan))
            return
        }
        if scope.isVisible(name) {
            report(Diagnostic(.warning, "'\(name)' shadows an outer 'let'", span: nameSpan))
        }
        scope.declaredHere.insert(name)
        func poison() {
            scope.values[name] = nil
            scope.poisoned.insert(name)
        }
        switch build(Set(scope.values.keys)) {
        case .failure(let diagnostic):
            report(diagnostic)
            poison()
        case .success(let template):
            let dependencies = template.dependencies
            if !dependencies.isEmpty {
                let offending = dependencies.map(\.root).filter { !scope.poisoned.contains($0) }.sorted()
                if let first = offending.first {
                    report(Diagnostic(
                        .error,
                        "'let' cannot reference '\(first)' at load time; only earlier 'let' constants are allowed",
                        span: nameSpan
                    ))
                }
                poison()
                return
            }
            let value = template.evaluate(with: evaluator, scope: LetEvalScope(values: scope.values))
            scope.values[name] = value
            scope.poisoned.remove(name)
            values[name] = value
        }
    }

    static func fixedContext() -> FilterContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return FilterContext(
            now: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!,
            services: DefaultFilterServices(calendar: calendar)
        )
    }
}
