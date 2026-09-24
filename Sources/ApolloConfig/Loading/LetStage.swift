import Foundation
import ApolloBase
import ApolloKDL

struct LetStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
    var values: [String: Value]
}

private final class LetFrame: @unchecked Sendable {
    let parent: LetFrame?
    var bindings: [String: Value] = [:]

    init(parent: LetFrame?) {
        self.parent = parent
    }

    func lookup(_ name: String) -> Value? {
        bindings[name] ?? parent?.lookup(name)
    }

    func declares(_ name: String) -> Bool {
        bindings[name] != nil
    }

    func visibleFromParent(_ name: String) -> Bool {
        parent?.lookup(name) != nil
    }

    func allNames() -> Set<String> {
        var result = parent?.allNames() ?? []
        result.formUnion(bindings.keys)
        return result
    }
}

private struct LetEvalScope: EvaluationScope {
    let frame: LetFrame

    func local(_ name: String) -> Value? {
        frame.lookup(name)
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        .null
    }
}

enum LetStage {
    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry) -> LetStageResult {
        StackHeadroom.run {
            var diagnostics: [Diagnostic] = []
            var values: [String: Value] = [:]
            let root = LetFrame(parent: nil)
            let resultNodes = process(nodes, frame: root, registry: registry, diagnostics: &diagnostics, values: &values)
            return LetStageResult(nodes: resultNodes, diagnostics: diagnostics, values: values)
        }
    }

    private static func process(
        _ nodes: [ExpandedNode],
        frame: LetFrame,
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value]
    ) -> [ExpandedNode] {
        var result: [ExpandedNode] = []
        for node in nodes {
            if node.kdl.name == "let" {
                handleLet(node, frame: frame, registry: registry, diagnostics: &diagnostics, values: &values)
                continue
            }
            var copy = node
            let childFrame = LetFrame(parent: frame)
            copy.children = process(node.children, frame: childFrame, registry: registry, diagnostics: &diagnostics, values: &values)
            result.append(copy)
        }
        return result
    }

    private static func handleLet(
        _ node: ExpandedNode,
        frame: LetFrame,
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value]
    ) {
        let kdl = node.kdl
        if kdl.arguments.count == 1, case .string(let name) = kdl.arguments[0].scalar, kdl.properties.isEmpty, !node.children.isEmpty {
            let attached = node.reattachingChildren()
            declare(
                name: name,
                nameSpan: kdl.arguments[0].span,
                frame: frame,
                registry: registry,
                diagnostics: &diagnostics,
                values: &values
            ) { locals in
                ValueTemplateKDLMapping.template(from: attached, locals: locals)
            }
            return
        }
        if !kdl.arguments.isEmpty || !node.children.isEmpty {
            diagnostics.append(Diagnostic(
                .error,
                "'let' must be written as 'let name=value ...' or 'let name { ... }'",
                span: kdl.span
            ))
            return
        }
        guard !kdl.properties.isEmpty else {
            diagnostics.append(Diagnostic(.error, "'let' needs at least one constant", span: kdl.span))
            return
        }
        for property in kdl.properties {
            declare(
                name: property.name,
                nameSpan: property.span,
                frame: frame,
                registry: registry,
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
        frame: LetFrame,
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic],
        values: inout [String: Value],
        build: (Set<String>) -> Result<ValueTemplate, Diagnostic>
    ) {
        if registry.fixedRoots.contains(name) || registry.providers[name] != nil {
            diagnostics.append(Diagnostic(.error, "'\(name)' is reserved", span: nameSpan))
            return
        }
        if registry.reservedProviderNames.contains(name) {
            diagnostics.append(Diagnostic(.note, "'\(name)' hides provider '\(name)'", span: nameSpan))
        }
        if frame.declares(name) {
            diagnostics.append(Diagnostic(.error, "duplicate 'let' '\(name)' in this scope", span: nameSpan))
            return
        }
        if frame.visibleFromParent(name) {
            diagnostics.append(Diagnostic(.warning, "'\(name)' shadows an outer 'let'", span: nameSpan))
        }
        let locals = frame.allNames()
        switch build(locals) {
        case .failure(let diagnostic):
            diagnostics.append(diagnostic)
        case .success(let template):
            let dependencies = template.dependencies
            if let offending = dependencies.first {
                diagnostics.append(Diagnostic(
                    .error,
                    "'let' cannot reference '\(offending.root)' at load time; only earlier 'let' constants are allowed",
                    span: nameSpan
                ))
                return
            }
            let evaluator = Evaluator(filters: .builtin, context: { fixedContext() }, warn: { _ in })
            let value = template.evaluate(with: evaluator, scope: LetEvalScope(frame: frame))
            frame.bindings[name] = value
            values[name] = value
        }
    }

    static func fixedContext() -> FilterContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return FilterContext(
            now: Date(),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "UTC")!,
            services: DefaultFilterServices(calendar: calendar)
        )
    }
}
