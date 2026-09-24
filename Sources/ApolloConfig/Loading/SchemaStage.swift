import ApolloBase
import ApolloKDL

struct CheckedNode: Sendable {
    var name: String
    var span: SourceSpan
    var arguments: [CompiledValue]
    var properties: [String: CompiledValue]
    var children: [CheckedNode]
}

struct SchemaStageResult: Sendable {
    var nodes: [CheckedNode]
    var diagnostics: [Diagnostic]
}

private struct EachLocal {
    var name: String
    var frame: UseFrame?
}

private struct WalkContext {
    var context: NodeContext
    var handlerNames: [String]
    var eachStack: [EachLocal]

    func locals(for node: ExpandedNode) -> Set<String> {
        var names = Set(eachStack.filter { $0.frame === node.useFrame }.map(\.name))
        if let frame = node.useFrame {
            names.formUnion(frame.bindings.keys)
        }
        return names
    }
}

enum SchemaStage {
    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry, context: NodeContext = .topLevel) -> SchemaStageResult {
        StackHeadroom.run {
            var diagnostics: [Diagnostic] = []
            let walk = WalkContext(context: context, handlerNames: [], eachStack: [])
            let checked = self.walkNodes(nodes, registry: registry, walk: walk, diagnostics: &diagnostics)
            return SchemaStageResult(nodes: checked, diagnostics: diagnostics)
        }
    }

    private static func walkNodes(_ nodes: [ExpandedNode], registry: SchemaRegistry, walk: WalkContext, diagnostics: inout [Diagnostic]) -> [CheckedNode] {
        var result: [CheckedNode] = []
        for node in nodes {
            if let checked = check(node, registry: registry, walk: walk, diagnostics: &diagnostics) {
                result.append(checked)
            }
        }
        return result
    }

    private static func check(_ node: ExpandedNode, registry: SchemaRegistry, walk: WalkContext, diagnostics: inout [Diagnostic]) -> CheckedNode? {
        let kdl = node.kdl
        let env = ExpressionEnvironment(registry: registry, letValues: node.letValues, locals: walk.locals(for: node), context: walk.context)

        if kdl.name == "script" {
            report(Diagnostic(.error, "Lua scripting comes in a later version", span: kdl.span), node: node, diagnostics: &diagnostics)
            return nil
        }

        if let schema = registry.node(kdl.name), schema.contexts.contains(walk.context) {
            return checkStructural(node, schema: schema, registry: registry, walk: walk, env: env, diagnostics: &diagnostics)
        }

        if walk.context == .actions, let action = registry.action(kdl.name) {
            return checkAction(node, schema: action, registry: registry, walk: walk, env: env, diagnostics: &diagnostics)
        }

        if walk.handlerNames.contains(kdl.name) {
            let schema = HandlerSchema.synthesize(kdl.name)
            return checkStructural(node, schema: schema, registry: registry, walk: walk, env: env, diagnostics: &diagnostics)
        }

        if walk.context != .actions, kdl.name.contains("."), registry.action(kdl.name) != nil {
            report(Diagnostic(.error, "'\(kdl.name)' is only valid inside a handler", span: kdl.span), node: node, diagnostics: &diagnostics)
            return nil
        }

        var candidates = registry.nodes.values.filter { $0.contexts.contains(walk.context) }.map(\.name)
        candidates.append(contentsOf: walk.handlerNames)
        if walk.context == .actions {
            candidates.append(contentsOf: registry.actions.keys)
        }
        let suggestion = Suggestion.closest(to: kdl.name, among: candidates)
        report(Diagnostic(.error, "unknown node '\(kdl.name)'", span: kdl.span, help: suggestion.map { "did you mean '\($0)'?" }), node: node, diagnostics: &diagnostics)
        return nil
    }

    private static func checkStructural(
        _ node: ExpandedNode,
        schema: NodeSchema,
        registry: SchemaRegistry,
        walk: WalkContext,
        env: ExpressionEnvironment,
        diagnostics: inout [Diagnostic]
    ) -> CheckedNode {
        let kdl = node.kdl
        if schema.stability == .experimental {
            report(Diagnostic(.note, "'\(kdl.name)' is experimental and may change", span: kdl.span), node: node, diagnostics: &diagnostics)
        }
        let (arguments, argumentDiagnostics) = checkArguments(schema.arguments, kdl.arguments, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in argumentDiagnostics { report(diagnostic, node: node, diagnostics: &diagnostics) }
        let (properties, propertyDiagnostics) = checkProperties(schema.properties, kdl.properties, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in propertyDiagnostics { report(diagnostic, node: node, diagnostics: &diagnostics) }

        var children: [CheckedNode] = []
        if schema.childContext != nil || !schema.handlers.isEmpty {
            var nextWalk = walk
            if let childContext = schema.childContext {
                nextWalk.context = childContext
            }
            nextWalk.handlerNames = schema.handlers
            if kdl.name == "each", case .string(let variable)? = kdl.arguments.first?.scalar {
                nextWalk.eachStack.append(EachLocal(name: variable, frame: node.useFrame))
                if let indexProperty = kdl.property("index"), case .string(let index) = indexProperty.value.scalar {
                    nextWalk.eachStack.append(EachLocal(name: index, frame: node.useFrame))
                }
            }
            children = walkNodes(node.children, registry: registry, walk: nextWalk, diagnostics: &diagnostics)
        } else if !node.children.isEmpty {
            report(Diagnostic(.error, "'\(kdl.name)' cannot have children", span: kdl.span), node: node, diagnostics: &diagnostics)
        }

        return CheckedNode(name: kdl.name, span: kdl.span, arguments: arguments, properties: properties, children: children)
    }

    private static func checkAction(
        _ node: ExpandedNode,
        schema: ActionSchema,
        registry: SchemaRegistry,
        walk: WalkContext,
        env: ExpressionEnvironment,
        diagnostics: inout [Diagnostic]
    ) -> CheckedNode {
        let kdl = node.kdl
        if schema.stability == .experimental {
            report(Diagnostic(.note, "'\(kdl.name)' is experimental and may change", span: kdl.span), node: node, diagnostics: &diagnostics)
        }
        let (arguments, argumentDiagnostics) = checkArguments(schema.arguments, kdl.arguments, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in argumentDiagnostics { report(diagnostic, node: node, diagnostics: &diagnostics) }
        let (properties, propertyDiagnostics) = checkProperties(schema.properties, kdl.properties, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in propertyDiagnostics { report(diagnostic, node: node, diagnostics: &diagnostics) }

        var children: [CheckedNode] = []
        if schema.acceptsChildren {
            if kdl.name == "repeat" {
                var nextWalk = walk
                nextWalk.context = .actions
                children = walkNodes(node.children, registry: registry, walk: nextWalk, diagnostics: &diagnostics)
            }
        } else if !node.children.isEmpty {
            report(Diagnostic(.error, "'\(kdl.name)' cannot have children", span: kdl.span), node: node, diagnostics: &diagnostics)
        }

        return CheckedNode(name: kdl.name, span: kdl.span, arguments: arguments, properties: properties, children: children)
    }

    private static func checkArguments(_ schema: [ArgumentSchema], _ values: [KDLValue], nodeName: String, nodeSpan: SourceSpan, env: ExpressionEnvironment) -> ([CompiledValue], [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        var compiled: [CompiledValue] = []
        var index = 0
        for (position, argument) in schema.enumerated() {
            if argument.variadic {
                if index >= values.count, argument.required {
                    diagnostics.append(Diagnostic(.error, "'\(nodeName)' needs at least one '\(argument.name)'", span: nodeSpan))
                }
                while index < values.count {
                    compiled.append(contentsOf: checkOneArgument(argument, values[index], env: env, diagnostics: &diagnostics))
                    index += 1
                }
                continue
            }
            if index >= values.count {
                if argument.required {
                    diagnostics.append(Diagnostic(.error, "'\(nodeName)' is missing argument '\(argument.name)'", span: nodeSpan))
                }
                continue
            }
            compiled.append(contentsOf: checkOneArgument(argument, values[index], env: env, diagnostics: &diagnostics))
            index += 1
            _ = position
        }
        if index < values.count {
            diagnostics.append(Diagnostic(.error, "'\(nodeName)' takes too many arguments", span: values[index].span))
        }
        return (compiled, diagnostics)
    }

    private static func checkOneArgument(_ argument: ArgumentSchema, _ value: KDLValue, env: ExpressionEnvironment, diagnostics: inout [Diagnostic]) -> [CompiledValue] {
        let isExpression: Bool
        if case .string(let text) = value.scalar, text.contains("{") {
            isExpression = true
        } else {
            isExpression = false
        }
        if !isExpression, !TypeChecker.literalMatches(value, argument.type) {
            diagnostics.append(Diagnostic(.error, "argument '\(argument.name)' expects \(TypeChecker.typeName(argument.type))", span: value.span))
        }
        let (compiledValue, more) = ExpressionCompiler.compile(value, env: env, allowsExpression: argument.allowsExpression)
        diagnostics.append(contentsOf: more)
        return [compiledValue]
    }

    private static func checkProperties(_ schema: [PropertySchema], _ properties: [KDLProperty], nodeName: String, nodeSpan: SourceSpan, env: ExpressionEnvironment) -> ([String: CompiledValue], [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        var compiled: [String: CompiledValue] = [:]
        var seen = Set<String>()
        let known = schema.map(\.name)
        for property in properties {
            guard let propertySchema = schema.first(where: { $0.name == property.name }) else {
                let suggestion = Suggestion.closest(to: property.name, among: known)
                diagnostics.append(Diagnostic(.error, "unknown property '\(property.name)' on '\(nodeName)'", span: property.span, help: suggestion.map { "did you mean '\($0)'?" }))
                continue
            }
            seen.insert(property.name)
            if propertySchema.stability == .experimental {
                diagnostics.append(Diagnostic(.note, "'\(property.name)' is experimental and may change", span: property.span))
            }
            let isExpression: Bool
            if case .string(let text) = property.value.scalar, text.contains("{") {
                isExpression = true
            } else {
                isExpression = false
            }
            if !isExpression, !TypeChecker.literalMatches(property.value, propertySchema.type) {
                diagnostics.append(Diagnostic(.error, "property '\(property.name)' expects \(TypeChecker.typeName(propertySchema.type))", span: property.value.span))
            }
            let (compiledValue, more) = ExpressionCompiler.compile(property.value, env: env, allowsExpression: propertySchema.allowsExpression)
            diagnostics.append(contentsOf: more)
            compiled[property.name] = compiledValue
        }
        for propertySchema in schema where propertySchema.required && !seen.contains(propertySchema.name) {
            diagnostics.append(Diagnostic(.error, "'\(nodeName)' is missing property '\(propertySchema.name)'", span: nodeSpan))
        }
        return (compiled, diagnostics)
    }

    private static func report(_ diagnostic: Diagnostic, node: ExpandedNode, diagnostics: inout [Diagnostic]) {
        diagnostics.append(DiagnosticCollector.withExpansionChain(diagnostic, node: node))
    }
}
