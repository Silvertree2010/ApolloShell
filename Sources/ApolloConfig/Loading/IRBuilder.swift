import Foundation
import ApolloBase
import ApolloKDL

struct IRBuildResult: Sendable {
    var ir: ConfigIR
    var diagnostics: [Diagnostic]
}

struct LocalBinding: Sendable {
    var frame: UseFrame?
    var name: String
    var renamed: String
}

private struct ArgumentKey: Hashable {
    var frame: ObjectIdentifier
    var name: String
}

private struct Body {
    var children: [ChildIR] = []
    var handlers: [HandlerIR] = []
    var keyHandlers: [KeyHandlerIR] = []
    var accessibilityActions: [AccessibilityActionIR] = []
    var menu: MenuIR?
    var slots: [String: [ChildIR]] = [:]
}

private struct SwitchBranches {
    var subject: CompiledValue
    var cases: [(values: [CompiledValue], nodes: [ExpandedNode])]
    var otherwise: [ExpandedNode]
}

private final class IRBuildState {
    let registry: SchemaRegistry
    let templates: TemplateCache?
    let definesByName: [String: DefineDecl]
    var diagnostics: [Diagnostic] = []
    var argumentCache: [ArgumentKey: StringTemplate] = [:]
    var ids: [String: SourceSpan] = [:]
    var surfaceID: String?

    init(registry: SchemaRegistry, defines: [DefineDecl], templates: TemplateCache?) {
        self.registry = registry
        self.templates = templates
        var byName: [String: DefineDecl] = [:]
        for define in defines {
            byName[define.name] = define
        }
        self.definesByName = byName
    }

    func report(_ diagnostic: Diagnostic, node: ExpandedNode) {
        diagnostics.append(DiagnosticCollector.withExpansionChain(diagnostic, node: node))
    }
}

enum IRBuilder {
    static let skippedTopLevelNodes: Set<String> = ["define", "let", "include", "require", "feature", "else", "disable", "param", "slot", "fill"]

    static func build(
        _ nodes: [ExpandedNode],
        defines: [DefineDecl],
        requires: [ExpandedNode],
        location: ConfigLocation,
        files: [URL],
        registry: SchemaRegistry,
        fileSystem: any ConfigFileSystem,
        paths: ConfigPaths,
        templates: TemplateCache? = nil
    ) -> IRBuildResult {
        StackHeadroom.run {
            let state = IRBuildState(registry: registry, defines: defines, templates: templates)
            var ir = ConfigIR(id: location.id, root: location.root, files: files)
            applyRequires(requires, to: &ir)
            var blockNodes: [ExpandedNode] = []
            var implicitBindCounts: [String: Int] = [:]
            for node in nodes where !node.isExpansionMarker {
                let name = node.kdl.name
                if skippedTopLevelNodes.contains(name) { continue }
                switch name {
                case "var":
                    if let declaration = buildVar(node, state: state) {
                        ir.vars.append(declaration)
                    }
                case "style":
                    ir.styleSheets.append(contentsOf: buildStyle(node, location: location, fileSystem: fileSystem, paths: paths, state: state))
                case "bind":
                    if var bind = buildBind(node, state: state) {
                        if stringProperty(node, "id") == nil {
                            let count = (implicitBindCounts[bind.id] ?? 0) + 1
                            implicitBindCounts[bind.id] = count
                            if count > 1 {
                                bind.id += "#\(count)"
                            }
                        }
                        ir.binds.append(bind)
                    }
                case "on":
                    if let handler = buildEvent(node, state: state) {
                        ir.events.append(handler)
                    }
                case "use":
                    state.report(Diagnostic(.error, "a 'use' with an expression as name is only allowed where children are allowed", span: node.kdl.span), node: node)
                default:
                    if let schema = registry.node(name), schema.category == .surface {
                        if let surface = buildSurface(node, schema: schema, state: state) {
                            ir.surfaces.append(surface)
                        }
                    } else if SchemaRegistry.scriptSourceKinds.contains(name), case .pkg(let package) = node.origin {
                        state.report(Diagnostic(.error, "package '\(package)' may not declare '\(name)': it starts programs", span: node.kdl.span), node: node)
                    } else if registry.node(name)?.contexts.contains(.topLevel) == true || SchemaStage.providerSettingsSchema(name, registry: registry) != nil {
                        blockNodes.append(node)
                    }
                }
            }
            ir.blocks = buildBlocks(blockNodes, state: state)
            ir.commandCenter = buildCommandCenter(blockNodes, state: state)
            ir.defines = buildDefines(defines, state: state)
            return IRBuildResult(ir: ir, diagnostics: state.diagnostics)
        }
    }

    private static func buildCommandCenter(_ nodes: [ExpandedNode], state: IRBuildState) -> CommandCenterIR? {
        let blocks = nodes.filter { $0.kdl.name == "command-center" }
        guard !blocks.isEmpty else { return nil }
        var result = CommandCenterIR()
        for node in blocks {
            if let visible = node.kdl.property("visible")?.value {
                result.visible = compile(visible, node: node, scope: [], state: state)
            }
            if let items = node.children.last(where: { $0.kdl.name == "items" && !$0.isExpansionMarker }) {
                result.items = buildMenu(items.children, scope: [], state: state)
            }
        }
        return result
    }

    private static func applyRequires(_ requires: [ExpandedNode], to ir: inout ConfigIR) {
        for node in requires {
            if let version = firstString(node) {
                if let current = ir.requiredVersion {
                    if let comparison = SemanticVersion.compare(version, current), comparison > 0 {
                        ir.requiredVersion = version
                    }
                } else {
                    ir.requiredVersion = version
                }
            }
            if let feature = stringProperty(node, "feature"), !ir.requiredFeatures.contains(feature) {
                ir.requiredFeatures.append(feature)
            }
        }
    }

    private static func buildVar(_ node: ExpandedNode, state: IRBuildState) -> VarDecl? {
        var diagnostics: [Diagnostic] = []
        let declaration = VarStage.declaration(for: node, diagnostics: &diagnostics)
        for diagnostic in diagnostics {
            state.report(diagnostic, node: node)
        }
        guard var result = declaration else { return nil }
        result.defaultValue = substitutingLets(result.defaultValue, node: node, state: state)
        result.derived = result.derived.map { substitutingLets($0, node: node, state: state) }
        return result
    }

    private static func substitutingLets(_ template: ValueTemplate, node: ExpandedNode, state: IRBuildState) -> ValueTemplate {
        switch template {
        case .scalar(let compiled):
            return .scalar(substitutingLets(compiled, node: node, state: state))
        case .list(let items):
            return .list(items.map { substitutingLets($0, node: node, state: state) })
        case .record(let fields):
            return .record(fields.map { ValueTemplateField(name: $0.name, value: substitutingLets($0.value, node: node, state: state)) })
        }
    }

    private static func substitutingLets(_ compiled: CompiledValue, node: ExpandedNode, state: IRBuildState) -> CompiledValue {
        if compiled.template.literalValue != nil, compiled.dependencies.isEmpty { return compiled }
        let locals = Set(node.useFrame?.bindings.keys.map { $0 } ?? [])
        var raw = compiled
        raw.template = LetSubstitution.apply(compiled.template, lets: node.letValues, locals: locals)
        return finish(raw, frame: node.useFrame, scope: [], state: state)
    }

    private static func buildStyle(_ node: ExpandedNode, location: ConfigLocation, fileSystem: any ConfigFileSystem, paths: ConfigPaths, state: IRBuildState) -> [StyleRef] {
        guard let raw = firstString(node) else { return [] }
        let argumentSpan = node.kdl.arguments.first?.span ?? node.kdl.span
        switch IncludeExpander.resolveAsset(raw, currentFile: node.file, origin: node.origin, configRoot: location.root, fileSystem: fileSystem, paths: paths) {
        case .failure(var diagnostic):
            if diagnostic.span == nil {
                diagnostic.span = argumentSpan
            }
            state.report(diagnostic, node: node)
            return []
        case .success(let urls):
            if urls.isEmpty {
                state.report(Diagnostic(.warning, "glob '\(raw)' matched no files", span: node.kdl.span), node: node)
            }
            var result: [StyleRef] = []
            for url in urls {
                if fileSystem.exists(url) {
                    result.append(StyleRef(url: url, span: node.kdl.span))
                } else {
                    state.report(Diagnostic(.warning, "stylesheet '\(raw)' does not exist", span: argumentSpan), node: node)
                }
            }
            return result
        }
    }

    private static func buildBind(_ node: ExpandedNode, state: IRBuildState) -> BindIR? {
        guard let chordValue = node.kdl.arguments.first else { return nil }
        let chord = compile(chordValue, node: node, scope: [], state: state)
        let id: String
        if let explicit = stringProperty(node, "id") {
            id = explicit
        } else if case .string(let raw) = chordValue.scalar {
            id = KeyChord.parse(raw)?.canonical ?? raw
        } else {
            id = ""
        }
        return BindIR(
            id: id,
            chord: chord,
            when: node.kdl.property("when").map { compile($0.value, node: node, scope: [], state: state) },
            repeats: boolProperty(node, "repeat") ?? false,
            actions: buildActions(node.children, scope: [], state: state),
            span: node.kdl.span
        )
    }

    private static func buildEvent(_ node: ExpandedNode, state: IRBuildState) -> EventHandlerIR? {
        guard let event = firstString(node) else { return nil }
        return EventHandlerIR(
            event: event,
            when: node.kdl.property("when").map { compile($0.value, node: node, scope: [], state: state) },
            actions: buildActions(node.children, scope: [], state: state),
            span: node.kdl.span
        )
    }

    private static func buildSurface(_ node: ExpandedNode, schema: NodeSchema, state: IRBuildState) -> SurfaceIR? {
        guard let id = firstString(node) else { return nil }
        if ExpressionText.containsExpression(id) {
            state.report(Diagnostic(.error, "a surface id cannot be an expression", span: node.kdl.arguments[0].span), node: node)
            return nil
        }
        state.ids = [:]
        state.surfaceID = id
        defer { state.surfaceID = nil }
        var properties = compileProperties(node, schema: schema.properties, scope: [], state: state)
        properties["override"] = nil
        let body = buildBody(node.children, handlerNames: Set(schema.handlers), scope: [], state: state)
        return SurfaceIR(
            kind: node.kdl.name,
            id: id,
            properties: properties,
            handlers: body.handlers,
            keyHandlers: body.keyHandlers,
            children: body.children,
            span: node.kdl.span
        )
    }

    private static func buildDefines(_ defines: [DefineDecl], state: IRBuildState) -> [String: DefineIR] {
        var result: [String: DefineIR] = [:]
        for define in defines {
            let parameters = define.parameters.map { parameter in
                ParameterIR(
                    name: parameter.name,
                    type: parameter.type,
                    defaultValue: parameter.defaultValue.map { .scalar(compile($0, node: defaultNode(for: define), scope: [], validation: .elementBody, state: state)) }
                )
            }
            if SchemaStage.bodyContext(define.body, registry: state.registry) == .actions { continue }
            state.surfaceID = nil
            let body = buildBody(define.body, handlerNames: [], scope: [], state: state)
            result[define.name] = DefineIR(name: define.name, parameters: parameters, body: body.children, span: define.span)
        }
        return result
    }

    private static func defaultNode(for define: DefineDecl?) -> ExpandedNode {
        var node = ExpandedNode(kdl: KDLNode(name: "param"), file: define?.span.file ?? "", includeChain: define?.includeChain ?? [], children: [])
        node.letValues = define?.letValues ?? [:]
        node.poisonedLets = define?.poisonedLets ?? []
        return node
    }

    private static func buildBody(_ nodes: [ExpandedNode], handlerNames: Set<String>, scope: [LocalBinding], state: IRBuildState) -> Body {
        var body = Body()
        let visible = nodes.filter { !$0.isExpansionMarker }
        var index = 0
        while index < visible.count {
            let node = visible[index]
            let name = node.kdl.name
            index += 1
            if handlerNames.contains(name) {
                if name == "key" {
                    body.keyHandlers.append(KeyHandlerIR(chord: firstString(node) ?? "", actions: buildActions(node.children, scope: scope, state: state)))
                } else {
                    body.handlers.append(HandlerIR(
                        name: name,
                        properties: compileProperties(node, schema: HandlerSchema.synthesize(name).properties, scope: scope, state: state),
                        actions: buildActions(node.children, scope: scope, state: state),
                        span: node.kdl.span
                    ))
                }
                continue
            }
            switch name {
            case "menu":
                if body.menu != nil {
                    state.report(Diagnostic(.error, "an element can have only one 'menu'", span: node.kdl.span), node: node)
                    continue
                }
                body.menu = MenuIR(
                    properties: compileProperties(node, schema: CommonProperties.elementHandlerNode.properties, scope: scope, state: state),
                    items: buildMenu(node.children, scope: scope, state: state)
                )
            case "accessibility-action":
                body.accessibilityActions.append(AccessibilityActionIR(
                    title: compileArgument(node, at: 0, scope: scope, state: state) ?? CompiledValueBuilder.literal(.string(""), span: node.kdl.span),
                    actions: buildActions(node.children, scope: scope, state: state)
                ))
            case "fill":
                if let slot = firstString(node) {
                    body.slots[slot] = buildBody(node.children, handlerNames: [], scope: scope, state: state).children
                }
            case "else", "let", "define", "param":
                continue
            default:
                var elseNode: ExpandedNode?
                if name == "when", index < visible.count, visible[index].kdl.name == "else" {
                    elseNode = visible[index]
                    index += 1
                }
                if let child = buildChild(node, elseNode: elseNode, key: String(body.children.count), scope: scope, state: state) {
                    body.children.append(child)
                }
            }
        }
        return body
    }

    private static func buildChild(_ node: ExpandedNode, elseNode: ExpandedNode?, key: String, scope: [LocalBinding], state: IRBuildState) -> ChildIR? {
        switch node.kdl.name {
        case "each":
            guard let variable = firstString(node), let inValue = node.kdl.property("in")?.value else { return nil }
            let list = compile(inValue, node: node, scope: scope, state: state)
            let (inner, renamedVariable, renamedIndex) = entering(node, variable: variable, scope: scope)
            return .each(EachIR(
                key: key,
                variable: renamedVariable,
                indexVariable: renamedIndex,
                list: list,
                itemKey: node.kdl.property("key").map { compile($0.value, node: node, scope: inner, state: state) },
                body: buildBody(node.children, handlerNames: [], scope: inner, state: state).children
            ))
        case "when":
            guard let condition = compileArgument(node, at: 0, scope: scope, state: state) else { return nil }
            let base = state.ids
            let then = buildBody(node.children, handlerNames: [], scope: scope, state: state).children
            let afterThen = state.ids
            state.ids = base
            let otherwise = elseNode.map { buildBody($0.children, handlerNames: [], scope: scope, state: state).children } ?? []
            state.ids = afterThen.merging(state.ids) { first, _ in first }
            return .when(WhenIR(key: key, condition: condition, then: then, otherwise: otherwise))
        case "switch":
            guard let branches = switchBranches(node, scope: scope, state: state) else { return nil }
            let base = state.ids
            var merged = base
            var cases: [SwitchCaseIR] = []
            for branch in branches.cases {
                state.ids = base
                cases.append(SwitchCaseIR(values: branch.values, body: buildBody(branch.nodes, handlerNames: [], scope: scope, state: state).children))
                merged.merge(state.ids) { first, _ in first }
            }
            state.ids = base
            let otherwise = buildBody(branches.otherwise, handlerNames: [], scope: scope, state: state).children
            state.ids = merged.merging(state.ids) { first, _ in first }
            return .switchOn(SwitchIR(key: key, subject: branches.subject, cases: cases, otherwise: otherwise))
        case "use":
            guard let name = compileArgument(node, at: 0, scope: scope, state: state) else { return nil }
            var arguments: [String: CompiledValue] = [:]
            for property in node.kdl.properties {
                arguments[property.name] = compile(property.value, node: node, scope: scope, state: state)
            }
            var slots: [String: [ChildIR]] = [:]
            var unnamed: [ExpandedNode] = []
            for child in node.children where !child.isExpansionMarker {
                if child.kdl.name == "fill", let slot = firstString(child) {
                    slots[slot] = buildBody(child.children, handlerNames: [], scope: scope, state: state).children
                } else {
                    unnamed.append(child)
                }
            }
            if !unnamed.isEmpty {
                slots[""] = buildBody(unnamed, handlerNames: [], scope: scope, state: state).children
            }
            return .dynamicUse(DynamicUseIR(key: key, name: name, arguments: arguments, slots: slots))
        case "case", "default":
            reportMisplacedBranch(node, state: state)
            return nil
        case "slot":
            return .slot(name: firstString(node))
        default:
            guard let schema = state.registry.node(node.kdl.name), schema.category == .element || schema.category == .layout else { return nil }
            return .element(buildElement(node, schema: schema, key: key, scope: scope, state: state))
        }
    }

    private static func buildElement(_ node: ExpandedNode, schema: NodeSchema, key: String, scope: [LocalBinding], state: IRBuildState) -> ElementIR {
        let arguments = compileArguments(node, schema: schema.arguments, scope: scope, state: state)
        let properties = compileProperties(node, schema: schema.properties, scope: scope, state: state)
        var elementKey = key
        if let id = properties["id"], let text = staticText(id) {
            if !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) {
                state.report(Diagnostic(.error, "an id cannot consist only of digits", span: id.span), node: node)
            } else {
                elementKey = text
                register(id: text, span: id.span, node: node, state: state)
            }
        }
        let body = buildBody(node.children, handlerNames: Set(schema.handlers), scope: scope, state: state)
        return ElementIR(
            kind: node.kdl.name,
            key: elementKey,
            arguments: arguments,
            properties: properties,
            handlers: body.handlers,
            keyHandlers: body.keyHandlers,
            accessibilityActions: body.accessibilityActions,
            menu: body.menu,
            slots: body.slots,
            children: body.children,
            span: node.kdl.span
        )
    }

    private static func register(id: String, span: SourceSpan, node: ExpandedNode, state: IRBuildState) {
        guard let surface = state.surfaceID else { return }
        if let first = state.ids[id] {
            state.report(Diagnostic(.error, "duplicate id '\(id)' in surface '\(surface)'", span: span, notes: [DiagnosticNote("first used here", span: first)]), node: node)
            return
        }
        state.ids[id] = span
    }

    private static func staticText(_ value: CompiledValue) -> String? {
        switch value.template {
        case .literal(let text): return text
        case .whole(.literal(.string(let text))): return text
        default: return nil
        }
    }

    private static func switchBranches(_ node: ExpandedNode, scope: [LocalBinding], state: IRBuildState) -> SwitchBranches? {
        guard let subject = compileArgument(node, at: 0, scope: scope, state: state) else { return nil }
        var branches = SwitchBranches(subject: subject, cases: [], otherwise: [])
        var sawDefault = false
        for child in node.children where !child.isExpansionMarker {
            switch child.kdl.name {
            case "case":
                if sawDefault {
                    state.report(Diagnostic(.error, "'default' must be the last branch of 'switch'", span: child.kdl.span), node: child)
                }
                let values = compileArguments(child, schema: [], scope: scope, state: state)
                branches.cases.append((values, child.children))
            case "default":
                if sawDefault {
                    state.report(Diagnostic(.error, "'switch' has more than one 'default'", span: child.kdl.span), node: child)
                    continue
                }
                sawDefault = true
                branches.otherwise = child.children
            default:
                state.report(Diagnostic(.error, "'switch' can only contain 'case' and 'default'", span: child.kdl.span), node: child)
            }
        }
        return branches
    }

    private static func reportMisplacedBranch(_ node: ExpandedNode, state: IRBuildState) {
        state.report(Diagnostic(.error, "'\(node.kdl.name)' is only allowed inside 'switch'", span: node.kdl.span), node: node)
    }

    private static func entering(_ node: ExpandedNode, variable: String, scope: [LocalBinding]) -> ([LocalBinding], String, String?) {
        var inner = scope
        let renamedVariable = renamed(variable, frame: node.useFrame)
        inner.append(LocalBinding(frame: node.useFrame, name: variable, renamed: renamedVariable))
        var renamedIndex: String?
        if let index = stringProperty(node, "index") {
            let name = renamed(index, frame: node.useFrame)
            inner.append(LocalBinding(frame: node.useFrame, name: index, renamed: name))
            renamedIndex = name
        }
        return (inner, renamedVariable, renamedIndex)
    }

    static func renamed(_ name: String, frame: UseFrame?) -> String {
        guard let frame else { return name }
        return "\(name)#\(frame.defineName)"
    }

    private static func buildActions(_ nodes: [ExpandedNode], scope: [LocalBinding], state: IRBuildState) -> [ActionIR] {
        var result: [ActionIR] = []
        let visible = nodes.filter { !$0.isExpansionMarker }
        var index = 0
        while index < visible.count {
            let node = visible[index]
            index += 1
            switch node.kdl.name {
            case "each":
                guard let variable = firstString(node), let inValue = node.kdl.property("in")?.value else { continue }
                let list = compile(inValue, node: node, scope: scope, state: state)
                let (inner, renamedVariable, renamedIndex) = entering(node, variable: variable, scope: scope)
                result.append(.each(variable: renamedVariable, index: renamedIndex, list: list, body: buildActions(node.children, scope: inner, state: state)))
            case "when":
                guard let condition = compileArgument(node, at: 0, scope: scope, state: state) else { continue }
                var otherwise: [ActionIR] = []
                if index < visible.count, visible[index].kdl.name == "else" {
                    otherwise = buildActions(visible[index].children, scope: scope, state: state)
                    index += 1
                }
                result.append(.when(condition: condition, then: buildActions(node.children, scope: scope, state: state), otherwise: otherwise))
            case "switch":
                guard let branches = switchBranches(node, scope: scope, state: state) else { continue }
                result.append(.switchOn(
                    subject: branches.subject,
                    cases: branches.cases.map { ActionCaseIR(values: $0.values, body: buildActions($0.nodes, scope: scope, state: state)) },
                    otherwise: buildActions(branches.otherwise, scope: scope, state: state)
                ))
            case "repeat":
                guard let count = compileArgument(node, at: 0, scope: scope, state: state) else { continue }
                result.append(.repeatBlock(count: count, body: buildActions(node.children, scope: scope, state: state)))
            case "case", "default":
                reportMisplacedBranch(node, state: state)
            case "use":
                state.report(Diagnostic(.error, "a 'use' with an expression as name is not allowed in actions", span: node.kdl.span), node: node)
            case "else":
                continue
            default:
                guard let schema = state.registry.action(node.kdl.name) else { continue }
                if schema.startsProgramsOrControlsApps, case .pkg(let package) = node.origin {
                    state.report(Diagnostic(.error, "package '\(package)' may not use '\(node.kdl.name)': it starts programs or controls apps", span: node.kdl.span), node: node)
                    continue
                }
                var children: [ValueTemplate] = []
                for child in node.children where !child.isExpansionMarker && schema.acceptsChildren {
                    guard child.kdl.name == "-" else {
                        state.report(Diagnostic(.error, "children of '\(node.kdl.name)' must be '-' entries", span: child.kdl.span), node: child)
                        break
                    }
                    children.append(valueTemplate(node: child, scope: scope, state: state))
                }
                var arguments = compileArguments(node, schema: schema.arguments, scope: scope, state: state)
                for position in arguments.indices where position < schema.arguments.count && schema.arguments[position].shellQuoted {
                    arguments[position] = shellQuoted(arguments[position])
                }
                result.append(.call(ActionCallIR(
                    name: node.kdl.name,
                    arguments: arguments,
                    properties: compileProperties(node, schema: schema.properties, scope: scope, state: state),
                    children: children,
                    span: node.kdl.span
                )))
            }
        }
        return result
    }

    static func shellQuoted(_ value: CompiledValue) -> CompiledValue {
        func quote(_ expr: Expr) -> Expr {
            if case .literal = expr { return expr }
            return .pipe(expr, FilterCall(name: "shell-quote", span: value.span))
        }
        var result = value
        switch value.template {
        case .literal:
            return value
        case .whole(let expr):
            result.template = .whole(quote(expr))
        case .parts(let parts):
            result.template = .parts(parts.map { part in
                if case .expression(let expr) = part { return .expression(quote(expr)) }
                return part
            })
        }
        return result
    }

    private static func valueTemplate(node: ExpandedNode, scope: [LocalBinding], state: IRBuildState) -> ValueTemplate {
        let children = node.children.filter { !$0.isExpansionMarker }
        if !children.isEmpty, children.allSatisfy({ $0.kdl.name == "-" }) {
            return .list(children.map { valueTemplate(node: $0, scope: scope, state: state) })
        }
        if node.kdl.arguments.count == 1, node.kdl.properties.isEmpty, children.isEmpty {
            return .scalar(compile(node.kdl.arguments[0], node: node, scope: scope, validation: .actions, state: state))
        }
        var fields: [ValueTemplateField] = []
        for property in node.kdl.properties {
            fields.append(ValueTemplateField(name: property.name, value: .scalar(compile(property.value, node: node, scope: scope, validation: .actions, state: state))))
        }
        for child in children where child.kdl.name != "-" {
            fields.append(ValueTemplateField(name: child.kdl.name, value: valueTemplate(node: child, scope: scope, state: state)))
        }
        return .record(fields)
    }

    private static func buildMenu(_ nodes: [ExpandedNode], scope: [LocalBinding], state: IRBuildState) -> [MenuItemIR] {
        var result: [MenuItemIR] = []
        let visible = nodes.filter { !$0.isExpansionMarker }
        var index = 0
        while index < visible.count {
            let node = visible[index]
            index += 1
            let schemaProperties = state.registry.node(node.kdl.name)?.properties ?? []
            switch node.kdl.name {
            case "item":
                result.append(.item(
                    title: compileArgument(node, at: 0, scope: scope, state: state) ?? CompiledValueBuilder.literal(.string(""), span: node.kdl.span),
                    properties: compileProperties(node, schema: schemaProperties, scope: scope, state: state),
                    actions: buildActions(node.children, scope: scope, state: state)
                ))
            case "separator":
                result.append(.separator)
            case "builtin":
                if let name = firstString(node) { result.append(.builtin(name)) }
            case "section":
                if let title = compileArgument(node, at: 0, scope: scope, state: state) {
                    result.append(.section(title))
                }
            case "submenu":
                result.append(.submenu(
                    title: compileArgument(node, at: 0, scope: scope, state: state) ?? CompiledValueBuilder.literal(.string(""), span: node.kdl.span),
                    items: buildMenu(node.children, scope: scope, state: state)
                ))
            case "source":
                guard let kind = firstString(node) else { continue }
                let properties = state.registry.menuSources[kind]?.properties ?? []
                result.append(.source(kind: kind, properties: compileProperties(node, schema: properties, scope: scope, state: state)))
            case "each":
                guard let variable = firstString(node), let inValue = node.kdl.property("in")?.value else { continue }
                let list = compile(inValue, node: node, scope: scope, state: state)
                let (inner, renamedVariable, renamedIndex) = entering(node, variable: variable, scope: scope)
                result.append(.each(
                    variable: renamedVariable,
                    index: renamedIndex,
                    list: list,
                    key: node.kdl.property("key").map { compile($0.value, node: node, scope: inner, state: state) },
                    body: buildMenu(node.children, scope: inner, state: state)
                ))
            case "when":
                guard let condition = compileArgument(node, at: 0, scope: scope, state: state) else { continue }
                var otherwise: [MenuItemIR] = []
                if index < visible.count, visible[index].kdl.name == "else" {
                    otherwise = buildMenu(visible[index].children, scope: scope, state: state)
                    index += 1
                }
                result.append(.when(condition: condition, then: buildMenu(node.children, scope: scope, state: state), otherwise: otherwise))
            case "switch":
                guard let branches = switchBranches(node, scope: scope, state: state) else { continue }
                var chain = buildMenu(branches.otherwise, scope: scope, state: state)
                for branch in branches.cases.reversed() {
                    let condition = matchCondition(subject: branches.subject, values: branch.values)
                    chain = [.when(condition: condition, then: buildMenu(branch.nodes, scope: scope, state: state), otherwise: chain)]
                }
                result.append(contentsOf: chain)
            case "case", "default":
                reportMisplacedBranch(node, state: state)
            case "use":
                state.report(Diagnostic(.error, "a 'use' with an expression as name is not allowed in a menu", span: node.kdl.span), node: node)
            default:
                continue
            }
        }
        return result
    }

    private static func matchCondition(subject: CompiledValue, values: [CompiledValue]) -> CompiledValue {
        let subjectExpression = expression(of: subject.template)
        var condition: Expr?
        var dependencies = subject.dependencies
        for value in values {
            let comparison = Expr.binary(.equal, subjectExpression, expression(of: value.template))
            condition = condition.map { .binary(.or, $0, comparison) } ?? comparison
            dependencies.formUnion(value.dependencies)
        }
        return CompiledValue(template: .whole(condition ?? .literal(.bool(false))), dependencies: dependencies, span: subject.span)
    }

    private static let errorSuffixedSourceKinds: Set<String> = ["poll", "listen"]

    private static func buildBlocks(_ nodes: [ExpandedNode], state: IRBuildState) -> [String: [BlockIR]] {
        let lastCommandCenterList = nodes.lastIndex { $0.kdl.name == "command-center" && $0.children.contains { !$0.isExpansionMarker } }
        var result: [String: [BlockIR]] = [:]
        for (position, original) in nodes.enumerated() {
            var node = original
            if node.kdl.name == "command-center", let last = lastCommandCenterList, position != last {
                node.children = []
            }
            if errorSuffixedSourceKinds.contains(node.kdl.name), let name = node.kdl.arguments.first, case .string(let text) = name.scalar, text.hasSuffix("-error") {
                state.report(Diagnostic(.error, "'\(node.kdl.name)' name '\(text)' cannot end with '-error', that suffix is reserved for the load error field", span: name.span), node: node)
            }
            let schema = state.registry.node(node.kdl.name) ?? SchemaStage.providerSettingsSchema(node.kdl.name, registry: state.registry)
            var compiled: [String: CompiledValue] = [:]
            flatten(node, prefix: "", schema: schema, into: &compiled, state: state)
            result[node.kdl.name, default: []].append(BlockIR(name: node.kdl.name, nodes: [kdlNode(node)], compiled: compiled))
        }
        return result
    }

    private static func flatten(_ node: ExpandedNode, prefix: String, schema: NodeSchema?, into compiled: inout [String: CompiledValue], state: IRBuildState) {
        func path(_ segment: String) -> String {
            prefix.isEmpty ? segment : "\(prefix).\(segment)"
        }
        let arguments = compileArguments(node, schema: schema?.arguments ?? [], scope: [], state: state)
        for (position, value) in arguments.enumerated() {
            compiled[path("#\(position)")] = value
        }
        for (name, value) in compileProperties(node, schema: schema?.properties ?? [], scope: [], state: state) {
            compiled[path(name)] = value
        }
        var occurrences: [String: Int] = [:]
        for child in node.children where !child.isExpansionMarker {
            let count = occurrences[child.kdl.name, default: 0]
            occurrences[child.kdl.name] = count + 1
            let segment = count == 0 ? child.kdl.name : "\(child.kdl.name)[\(count)]"
            flatten(child, prefix: path(segment), schema: state.registry.node(child.kdl.name), into: &compiled, state: state)
        }
    }

    private static func kdlNode(_ node: ExpandedNode) -> KDLNode {
        var result = node.kdl
        let children = node.children.filter { !$0.isExpansionMarker }
        result.children = children.isEmpty ? nil : children.map(kdlNode)
        return result
    }

    private static func compileArgument(_ node: ExpandedNode, at position: Int, scope: [LocalBinding], state: IRBuildState) -> CompiledValue? {
        guard position < node.kdl.arguments.count else { return nil }
        return compile(node.kdl.arguments[position], node: node, scope: scope, state: state)
    }

    private static func compileArguments(_ node: ExpandedNode, schema: [ArgumentSchema], scope: [LocalBinding], state: IRBuildState) -> [CompiledValue] {
        node.kdl.arguments.enumerated().map { position, value in
            let argument = position < schema.count ? schema[position] : schema.last { $0.variadic }
            return compile(value, node: node, scope: scope, allowsExpression: argument?.allowsExpression ?? true, state: state)
        }
    }

    private static func compileProperties(_ node: ExpandedNode, schema: [PropertySchema], scope: [LocalBinding], state: IRBuildState) -> [String: CompiledValue] {
        var result: [String: CompiledValue] = [:]
        for property in node.kdl.properties {
            let allowsExpression = schema.first { $0.name == property.name }?.allowsExpression ?? true
            result[property.name] = compile(property.value, node: node, scope: scope, allowsExpression: allowsExpression, state: state)
        }
        return result
    }

    private static func compile(
        _ value: KDLValue,
        node: ExpandedNode,
        scope: [LocalBinding],
        allowsExpression: Bool = true,
        validation: NodeContext? = nil,
        state: IRBuildState
    ) -> CompiledValue {
        let frame = node.useFrame
        var locals = Set<String>()
        for binding in scope where binding.frame === frame {
            locals.insert(binding.name)
        }
        if let frame {
            locals.formUnion(frame.bindings.keys)
        }
        let environment = ExpressionEnvironment(registry: state.registry, letValues: node.letValues, poisonedLets: node.poisonedLets, locals: locals, context: validation ?? .elementBody, templates: state.templates)
        let (compiled, diagnostics) = ExpressionCompiler.compile(value, env: environment, allowsExpression: allowsExpression, validates: validation != nil)
        for diagnostic in diagnostics where validation != nil {
            state.report(diagnostic, node: node)
        }
        return finish(compiled, frame: frame, scope: scope, state: state)
    }

    private static func finish(_ compiled: CompiledValue, frame: UseFrame?, scope: [LocalBinding], state: IRBuildState) -> CompiledValue {
        switch compiled.template {
        case .literal, .whole(.literal):
            var result = compiled
            result.dependencies = []
            return result
        default:
            let template = rewrite(compiled.template, frame: frame, scope: scope, state: state)
            return CompiledValue(template: template, dependencies: template.dependencies(locals: localNames(frame: frame, scope: scope)), span: compiled.span)
        }
    }

    private static func localNames(frame: UseFrame?, scope: [LocalBinding]) -> Set<String> {
        var names = Set(scope.map(\.renamed))
        var current = frame
        while let link = current {
            for (name, binding) in link.bindings {
                if case .runtime = binding {
                    names.insert(name)
                }
            }
            current = link.parent
        }
        return names
    }

    private static func rewrite(_ template: StringTemplate, frame: UseFrame?, scope: [LocalBinding], state: IRBuildState) -> StringTemplate {
        switch template {
        case .literal:
            return template
        case .whole(let expr):
            if case .path(let root, let members) = expr, members.isEmpty, let argument = parameter(root, frame: frame, scope: scope, state: state) {
                return argument
            }
            return .whole(rewrite(expr, frame: frame, scope: scope, state: state))
        case .parts(let parts):
            var result: [TemplatePart] = []
            for part in parts {
                guard case .expression(let expr) = part else {
                    result.append(part)
                    continue
                }
                if case .path(let root, let members) = expr, members.isEmpty, let argument = parameter(root, frame: frame, scope: scope, state: state) {
                    switch argument {
                    case .literal(let text):
                        result.append(.text(text))
                        continue
                    case .parts(let inner):
                        result.append(contentsOf: inner)
                        continue
                    case .whole(let inner):
                        result.append(.expression(inner))
                        continue
                    }
                }
                result.append(.expression(rewrite(expr, frame: frame, scope: scope, state: state)))
            }
            return .parts(result)
        }
    }

    private static func rewrite(_ expr: Expr, frame: UseFrame?, scope: [LocalBinding], state: IRBuildState) -> Expr {
        switch expr {
        case .literal:
            return expr
        case .list(let items):
            return .list(items.map { rewrite($0, frame: frame, scope: scope, state: state) })
        case .path(let root, let members):
            let newMembers = members.map { rewrite($0, frame: frame, scope: scope, state: state) }
            if let local = scope.last(where: { $0.frame === frame && $0.name == root }) {
                return .path(root: local.renamed, members: newMembers)
            }
            if let argument = parameter(root, frame: frame, scope: scope, state: state) {
                let base = expression(of: argument)
                return newMembers.isEmpty ? base : .access(base, newMembers)
            }
            return .path(root: root, members: newMembers)
        case .access(let base, let members):
            return .access(rewrite(base, frame: frame, scope: scope, state: state), members.map { rewrite($0, frame: frame, scope: scope, state: state) })
        case .unary(let op, let operand):
            return .unary(op, rewrite(operand, frame: frame, scope: scope, state: state))
        case .binary(let op, let lhs, let rhs):
            return .binary(op, rewrite(lhs, frame: frame, scope: scope, state: state), rewrite(rhs, frame: frame, scope: scope, state: state))
        case .conditional(let condition, let then, let otherwise):
            return .conditional(rewrite(condition, frame: frame, scope: scope, state: state), rewrite(then, frame: frame, scope: scope, state: state), rewrite(otherwise, frame: frame, scope: scope, state: state))
        case .coalesce(let lhs, let rhs):
            return .coalesce(rewrite(lhs, frame: frame, scope: scope, state: state), rewrite(rhs, frame: frame, scope: scope, state: state))
        case .pipe(let input, let call):
            let arguments = call.arguments.map { rewrite($0, frame: frame, scope: scope, state: state) }
            return .pipe(rewrite(input, frame: frame, scope: scope, state: state), FilterCall(name: call.name, arguments: arguments, span: call.span))
        }
    }

    private static func rewrite(_ member: PathMember, frame: UseFrame?, scope: [LocalBinding], state: IRBuildState) -> PathMember {
        guard case .index(let expr) = member else { return member }
        return .index(rewrite(expr, frame: frame, scope: scope, state: state))
    }

    private static func parameter(_ name: String, frame: UseFrame?, scope: [LocalBinding], state: IRBuildState) -> StringTemplate? {
        guard let frame, let binding = frame.bindings[name] else { return nil }
        if scope.contains(where: { $0.frame === frame && $0.name == name }) { return nil }
        let key = ArgumentKey(frame: ObjectIdentifier(frame), name: name)
        if let cached = state.argumentCache[key] {
            return cached
        }
        let template: StringTemplate
        switch binding {
        case .runtime:
            return nil
        case .argument(let value):
            guard let callSite = frame.callSite else { return nil }
            template = compile(value, node: callSite, scope: scope, state: state).template
        case .defaultValue(let value):
            template = compile(value, node: defaultNode(for: state.definesByName[frame.defineName]), scope: [], state: state).template
        }
        state.argumentCache[key] = template
        return template
    }

    private static func expression(of template: StringTemplate) -> Expr {
        switch template {
        case .literal(let text):
            return .literal(.string(text))
        case .whole(let expr):
            return expr
        case .parts(let parts):
            var result: Expr?
            for part in parts {
                let piece: Expr
                switch part {
                case .text(let text): piece = .literal(.string(text))
                case .expression(let expr): piece = expr
                }
                result = .binary(.add, result ?? .literal(.string("")), piece)
            }
            return result ?? .literal(.string(""))
        }
    }

    private static func firstString(_ node: ExpandedNode) -> String? {
        guard let first = node.kdl.arguments.first, case .string(let value) = first.scalar else { return nil }
        return value
    }

    private static func stringProperty(_ node: ExpandedNode, _ name: String) -> String? {
        guard let property = node.kdl.property(name), case .string(let value) = property.value.scalar else { return nil }
        return value
    }

    private static func boolProperty(_ node: ExpandedNode, _ name: String) -> Bool? {
        guard let property = node.kdl.property(name), case .bool(let value) = property.value.scalar else { return nil }
        return value
    }
}
