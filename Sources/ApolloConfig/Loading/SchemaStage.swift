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

    func environment(for node: ExpandedNode, registry: SchemaRegistry, templates: TemplateCache?, declaredVars: Set<String>?) -> ExpressionEnvironment {
        ExpressionEnvironment(registry: registry, locals: locals(for: node), context: context, templates: templates, declaredVars: declaredVars)
    }
}

private final class SchemaWalkState {
    let registry: SchemaRegistry
    let templates: TemplateCache?
    let declaredVars: Set<String>?
    var diagnostics: [Diagnostic] = []
    var validatedFrames: Set<ObjectIdentifier> = []
    var instantiatedDefines: Set<String> = []

    init(registry: SchemaRegistry, templates: TemplateCache?, declaredVars: Set<String>?) {
        self.registry = registry
        self.templates = templates
        self.declaredVars = declaredVars
    }

    func report(_ diagnostic: Diagnostic, node: ExpandedNode) {
        diagnostics.append(DiagnosticCollector.withExpansionChain(diagnostic, node: node))
    }
}

enum SchemaStage {
    static let varActions: Set<String> = ["set", "toggle-var", "reset"]
    static let contextInheritingNodes: Set<String> = ["each", "when", "else", "switch", "case", "default"]

    static func run(_ nodes: [ExpandedNode], defines: [DefineDecl] = [], registry: SchemaRegistry, context: NodeContext = .topLevel, templates: TemplateCache? = nil, declaredVars: Set<String>? = nil) -> SchemaStageResult {
        StackHeadroom.run {
            let state = SchemaWalkState(registry: registry, templates: templates, declaredVars: declaredVars)
            let walk = WalkContext(context: context, handlerNames: [], eachStack: [])
            let checked = self.walkNodes(nodes, walk: walk, state: state)
            self.checkDefineBodies(defines, state: state)
            return SchemaStageResult(nodes: checked, diagnostics: state.diagnostics)
        }
    }

    private static func checkDefineBodies(_ defines: [DefineDecl], state: SchemaWalkState) {
        let pending = defines.filter { !state.instantiatedDefines.contains($0.name) }
        var coveredByOtherBodies: Set<String> = []
        for define in pending {
            collectStaticUseNames(define.body, into: &coveredByOtherBodies)
        }
        for define in pending where !coveredByOtherBodies.contains(define.name) {
            let walk = WalkContext(context: bodyContext(define.body, registry: state.registry), handlerNames: [], eachStack: [])
            _ = walkNodes(define.body, walk: walk, state: state)
        }
    }

    private static func collectStaticUseNames(_ nodes: [ExpandedNode], into names: inout Set<String>) {
        for node in nodes {
            var frame = node.useFrame
            while let current = frame {
                if current.callSite != nil {
                    names.insert(current.defineName)
                }
                frame = current.parent
            }
            collectStaticUseNames(node.children, into: &names)
        }
    }

    static func bodyContext(_ body: [ExpandedNode], registry: SchemaRegistry) -> NodeContext {
        let isActionBody = body.contains { registry.action($0.kdl.name) != nil && registry.node($0.kdl.name) == nil }
        return isActionBody ? .actions : .elementBody
    }

    private static func walkNodes(_ nodes: [ExpandedNode], walk: WalkContext, state: SchemaWalkState) -> [CheckedNode] {
        var result: [CheckedNode] = []
        for node in nodes {
            if let checked = check(node, walk: walk, state: state) {
                result.append(checked)
            }
        }
        return result
    }

    private static func validateCallSites(of frame: UseFrame?, walk: WalkContext, state: SchemaWalkState) {
        guard let frame, !state.validatedFrames.contains(ObjectIdentifier(frame)) else { return }
        state.validatedFrames.insert(ObjectIdentifier(frame))
        validateCallSites(of: frame.parent, walk: walk, state: state)
        guard let callSite = frame.callSite else { return }
        state.instantiatedDefines.insert(frame.defineName)
        let env = walk.environment(for: callSite, registry: state.registry, templates: state.templates, declaredVars: state.declaredVars)
        for property in callSite.kdl.properties {
            guard case .argument? = frame.bindings[property.name] else { continue }
            let (_, diagnostics) = ExpressionCompiler.compile(property.value, env: env, allowsExpression: true)
            for diagnostic in diagnostics { state.report(diagnostic, node: callSite) }
        }
    }

    private static func check(_ node: ExpandedNode, walk: WalkContext, state: SchemaWalkState) -> CheckedNode? {
        validateCallSites(of: node.useFrame, walk: walk, state: state)
        if node.isExpansionMarker { return nil }
        let registry = state.registry
        let kdl = node.kdl
        let env = walk.environment(for: node, registry: registry, templates: state.templates, declaredVars: state.declaredVars)

        if kdl.name == "script" {
            state.report(Diagnostic(.error, "Lua scripting comes in a later version", span: kdl.span), node: node)
            return nil
        }

        if kdl.name == "use", let schema = registry.node("use"), schema.contexts.contains(walk.context) {
            return checkRuntimeUse(node, schema: schema, walk: walk, env: env, state: state)
        }

        if var schema = registry.node(kdl.name), schema.contexts.contains(walk.context) {
            if kdl.name == "source", let first = kdl.arguments.first, case .string(let kind) = first.scalar {
                if let source = registry.menuSources[kind] {
                    schema.properties += source.properties
                } else {
                    let suggestion = Suggestion.closest(to: kind, among: Array(registry.menuSources.keys))
                    state.report(Diagnostic(.error, "unknown menu source '\(kind)'", span: first.span, help: suggestion.map { "did you mean '\($0)'?" }), node: node)
                    return nil
                }
            }
            return checkStructural(node, schema: schema, walk: walk, env: env, state: state)
        }

        if walk.context == .topLevel, let schema = providerSettingsSchema(kdl.name, registry: registry) {
            return checkStructural(node, schema: schema, walk: walk, env: env, state: state)
        }

        if walk.context == .actions, let action = registry.action(kdl.name) {
            return checkAction(node, schema: action, walk: walk, env: env, state: state)
        }

        if walk.handlerNames.contains(kdl.name) {
            let schema = HandlerSchema.synthesize(kdl.name)
            return checkStructural(node, schema: schema, walk: walk, env: env, state: state)
        }

        if walk.context != .actions, kdl.name.contains("."), registry.action(kdl.name) != nil {
            state.report(Diagnostic(.error, "'\(kdl.name)' is only valid inside a handler", span: kdl.span), node: node)
            return nil
        }

        var candidates = registry.nodes.values.filter { $0.contexts.contains(walk.context) }.map(\.name)
        candidates.append(contentsOf: walk.handlerNames)
        if walk.context == .actions {
            candidates.append(contentsOf: registry.actions.keys)
        }
        let suggestion = Suggestion.closest(to: kdl.name, among: candidates)
        state.report(Diagnostic(.error, "unknown node '\(kdl.name)'", span: kdl.span, help: suggestion.map { "did you mean '\($0)'?" }), node: node)
        return nil
    }

    static func providerSettingsSchema(_ name: String, registry: SchemaRegistry) -> NodeSchema? {
        guard let provider = registry.providers[name] else { return nil }
        return NodeSchema(name: name, category: .providerSettings, feature: provider.feature, stability: provider.stability, properties: provider.settings, contexts: [.topLevel], doc: provider.doc, example: "")
    }

    private static func checkRuntimeUse(_ node: ExpandedNode, schema: NodeSchema, walk: WalkContext, env: ExpressionEnvironment, state: SchemaWalkState) -> CheckedNode {
        let kdl = node.kdl
        let (arguments, argumentDiagnostics) = checkArguments(schema.arguments, kdl.arguments, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in argumentDiagnostics { state.report(diagnostic, node: node) }
        var properties: [String: CompiledValue] = [:]
        for property in kdl.properties {
            let (compiled, diagnostics) = ExpressionCompiler.compile(property.value, env: env, allowsExpression: true)
            for diagnostic in diagnostics { state.report(diagnostic, node: node) }
            properties[property.name] = compiled
        }
        var nextWalk = walk
        nextWalk.context = schema.childContext ?? .elementBody
        nextWalk.handlerNames = []
        let children = walkNodes(node.children, walk: nextWalk, state: state)
        return CheckedNode(name: kdl.name, span: kdl.span, arguments: arguments, properties: properties, children: children)
    }

    private static func checkLocalName(_ value: KDLValue, node: ExpandedNode, state: SchemaWalkState) -> String? {
        guard case .string(let name) = value.scalar else { return nil }
        let registry = state.registry
        if registry.fixedRoots.contains(name) || registry.providers[name] != nil {
            state.report(Diagnostic(.error, "'\(name)' is reserved", span: value.span), node: node)
        } else if registry.reservedProviderNames.contains(name) {
            state.report(Diagnostic(.note, "'\(name)' hides provider '\(name)'", span: value.span), node: node)
        }
        return name
    }

    private static func checkStructural(
        _ node: ExpandedNode,
        schema: NodeSchema,
        walk: WalkContext,
        env: ExpressionEnvironment,
        state: SchemaWalkState
    ) -> CheckedNode {
        let kdl = node.kdl
        var env = env
        if schema.category == .surface {
            env.context = .surfaceBody
        }
        let isVar = kdl.name == "var"
        var loopLocals: [EachLocal] = []
        if kdl.name == "each" {
            if let variable = kdl.arguments.first, let name = checkLocalName(variable, node: node, state: state) {
                loopLocals.append(EachLocal(name: name, frame: node.useFrame))
            }
            if let index = kdl.property("index"), let name = checkLocalName(index.value, node: node, state: state) {
                loopLocals.append(EachLocal(name: name, frame: node.useFrame))
            }
        }
        if schema.stability == .experimental {
            state.report(Diagnostic(.note, "'\(kdl.name)' is experimental and may change", span: kdl.span), node: node)
        }
        let (arguments, argumentDiagnostics) = checkArguments(schema.arguments, kdl.arguments, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in argumentDiagnostics { state.report(diagnostic, node: node) }
        var keyEnv = env
        keyEnv.locals.formUnion(loopLocals.map(\.name))
        let checkedProperties = isVar ? kdl.properties.filter { VarStage.controlProperties.contains($0.name) } : kdl.properties
        let (properties, propertyDiagnostics) = checkProperties(schema.properties, checkedProperties, nodeName: kdl.name, nodeSpan: kdl.span, env: env, overrides: ["key": keyEnv])
        for diagnostic in propertyDiagnostics { state.report(diagnostic, node: node) }
        if isVar {
            let dataProperties = kdl.properties.filter { !VarStage.controlProperties.contains($0.name) }
            checkDataValues(dataProperties.map(\.value), node: node, env: env, state: state)
            checkDataNodes(node.children, env: env, state: state)
        }

        var children: [CheckedNode] = []
        if schema.childContext != nil || !schema.handlers.isEmpty {
            var nextWalk = walk
            if contextInheritingNodes.contains(kdl.name), walk.context != .topLevel {
                nextWalk.context = walk.context
            } else if let childContext = schema.childContext {
                nextWalk.context = childContext
            } else if walk.context == .surfaceBody {
                nextWalk.context = .elementBody
            }
            nextWalk.handlerNames = schema.handlers
            nextWalk.eachStack.append(contentsOf: loopLocals)
            children = walkNodes(node.children, walk: nextWalk, state: state)
        } else if !node.children.isEmpty, !isVar {
            state.report(Diagnostic(.error, "'\(kdl.name)' cannot have children", span: kdl.span), node: node)
        }

        return CheckedNode(name: kdl.name, span: kdl.span, arguments: arguments, properties: properties, children: children)
    }

    private static func checkDataNodes(_ nodes: [ExpandedNode], env: ExpressionEnvironment, state: SchemaWalkState) {
        for node in nodes where !node.isExpansionMarker {
            checkDataValues(node.kdl.arguments + node.kdl.properties.map(\.value), node: node, env: env, state: state)
            checkDataNodes(node.children, env: env, state: state)
        }
    }

    private static func checkDataValues(_ values: [KDLValue], node: ExpandedNode, env: ExpressionEnvironment, state: SchemaWalkState) {
        for value in values {
            let (_, diagnostics) = ExpressionCompiler.compile(value, env: env, allowsExpression: true)
            for diagnostic in diagnostics { state.report(diagnostic, node: node) }
        }
    }

    private static func checkAction(
        _ node: ExpandedNode,
        schema: ActionSchema,
        walk: WalkContext,
        env: ExpressionEnvironment,
        state: SchemaWalkState
    ) -> CheckedNode {
        let kdl = node.kdl
        if schema.stability == .experimental {
            state.report(Diagnostic(.note, "'\(kdl.name)' is experimental and may change", span: kdl.span), node: node)
        }
        let (arguments, argumentDiagnostics) = checkArguments(schema.arguments, kdl.arguments, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in argumentDiagnostics { state.report(diagnostic, node: node) }
        if Self.varActions.contains(kdl.name), let declared = env.declaredVars,
           let first = kdl.arguments.first, case .string(let name) = first.scalar,
           !name.utf8.contains(UInt8(ascii: "{")), !declared.contains(name) {
            let suggestion = Suggestion.closest(to: name, among: Array(declared))
            state.report(Diagnostic(.warning, "unknown var '\(name)'", span: first.span, help: suggestion.map { "did you mean '\($0)'?" }), node: node)
        }
        let (properties, propertyDiagnostics) = checkProperties(schema.properties, kdl.properties, nodeName: kdl.name, nodeSpan: kdl.span, env: env)
        for diagnostic in propertyDiagnostics { state.report(diagnostic, node: node) }

        var children: [CheckedNode] = []
        if schema.acceptsChildren {
            if kdl.name == "repeat" {
                var nextWalk = walk
                nextWalk.context = .actions
                children = walkNodes(node.children, walk: nextWalk, state: state)
            }
        } else if !node.children.isEmpty {
            state.report(Diagnostic(.error, "'\(kdl.name)' cannot have children", span: kdl.span), node: node)
        }

        return CheckedNode(name: kdl.name, span: kdl.span, arguments: arguments, properties: properties, children: children)
    }

    private static func checkArguments(_ schema: [ArgumentSchema], _ values: [KDLValue], nodeName: String, nodeSpan: SourceSpan, env: ExpressionEnvironment) -> ([CompiledValue], [Diagnostic]) {
        var diagnostics: [Diagnostic] = []
        var compiled: [CompiledValue] = []
        var index = 0
        for argument in schema {
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
        }
        if index < values.count {
            diagnostics.append(Diagnostic(.error, "'\(nodeName)' takes too many arguments", span: values[index].span))
        }
        return (compiled, diagnostics)
    }

    private static func checkOneArgument(_ argument: ArgumentSchema, _ value: KDLValue, env: ExpressionEnvironment, diagnostics: inout [Diagnostic]) -> [CompiledValue] {
        if !isExpression(value), !TypeChecker.literalMatches(value, argument.type) {
            diagnostics.append(Diagnostic(.error, "argument '\(argument.name)' expects \(TypeChecker.typeName(argument.type))", span: value.span, help: TypeChecker.suggestion(for: value, argument.type)))
        }
        let (compiledValue, more) = ExpressionCompiler.compile(value, env: env, allowsExpression: argument.allowsExpression)
        diagnostics.append(contentsOf: more)
        return [compiledValue]
    }

    private static func isExpression(_ value: KDLValue) -> Bool {
        guard case .string(let text) = value.scalar else { return false }
        return ExpressionText.containsExpression(text)
    }

    private static func checkProperties(
        _ schema: [PropertySchema],
        _ properties: [KDLProperty],
        nodeName: String,
        nodeSpan: SourceSpan,
        env: ExpressionEnvironment,
        overrides: [String: ExpressionEnvironment] = [:]
    ) -> ([String: CompiledValue], [Diagnostic]) {
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
            if !isExpression(property.value), !TypeChecker.literalMatches(property.value, propertySchema.type) {
                diagnostics.append(Diagnostic(.error, "property '\(property.name)' expects \(TypeChecker.typeName(propertySchema.type))", span: property.value.span, help: TypeChecker.suggestion(for: property.value, propertySchema.type)))
            }
            let (compiledValue, more) = ExpressionCompiler.compile(property.value, env: overrides[property.name] ?? env, allowsExpression: propertySchema.allowsExpression)
            diagnostics.append(contentsOf: more)
            compiled[property.name] = compiledValue
        }
        for propertySchema in schema where propertySchema.required && !seen.contains(propertySchema.name) {
            diagnostics.append(Diagnostic(.error, "'\(nodeName)' is missing property '\(propertySchema.name)'", span: nodeSpan))
        }
        return (compiled, diagnostics)
    }
}
