import ApolloBase
import ApolloKDL

struct ParameterDecl: Sendable, Hashable {
    var name: String
    var type: ValueType
    var defaultValue: KDLValue?
    var span: SourceSpan

    var isRequired: Bool {
        defaultValue == nil
    }
}

struct DefineDecl: Sendable, Hashable {
    var name: String
    var parameters: [ParameterDecl]
    var hasUnnamedSlot: Bool
    var namedSlots: [String]
    var body: [ExpandedNode]
    var span: SourceSpan
    var includeChain: [SourceSpan]
}

struct UseStageResult: Sendable {
    var nodes: [ExpandedNode]
    var defines: [DefineDecl]
    var diagnostics: [Diagnostic]
    var nodeCount: Int
}

private struct Definition {
    var declaration: DefineDecl
    var node: ExpandedNode
    var rawBody: [ExpandedNode]
}

private struct Built {
    var nodes: [ExpandedNode] = []
    var height = 0
    var count = 0

    mutating func append(_ node: ExpandedNode, height nodeHeight: Int, count nodeCount: Int) {
        nodes.append(node)
        height = max(height, nodeHeight)
        count += nodeCount
    }

    mutating func merge(_ other: Built) {
        nodes.append(contentsOf: other.nodes)
        height = max(height, other.height)
        count += other.count
    }
}

private final class SlotContents {
    let contents: [String?: Built]
    var inserted: Set<String?> = []

    init(_ contents: [String?: Built]) {
        self.contents = contents
    }
}

private enum SlotMode {
    case notAllowed
    case placeholder
    case substitute(SlotContents)
}

private struct ExpansionContext {
    var frame: UseFrame?
    var slots: SlotMode
    var depth: Int
    var isTopLevel: Bool
    var quiet: Bool

    func nested(by levels: Int = 1) -> ExpansionContext {
        var copy = self
        copy.depth += levels
        copy.isTopLevel = false
        return copy
    }
}

private final class UseExpansionState {
    let registry: SchemaRegistry
    var definitions: [String: Definition] = [:]
    var order: [String] = []
    var diagnostics: [Diagnostic] = []
    var nodeCount = 0
    var budgetHit = false
    var depthHit = false
    var nestingHit = false
    var reportedCycles: Set<[String]> = []

    init(registry: SchemaRegistry) {
        self.registry = registry
    }

    func report(_ diagnostic: Diagnostic, at node: ExpandedNode, frame: UseFrame?) {
        diagnostics.append(DiagnosticCollector.withExpansionChain(diagnostic, includeChain: node.includeChain, frame: frame))
    }
}

enum UseStage {
    static let parameterProperties = ["default", "type"]

    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry) -> UseStageResult {
        StackHeadroom.run {
            let state = UseExpansionState(registry: registry)
            for node in nodes where node.kdl.name == "define" {
                collectDefinition(node, state: state)
            }
            let root = ExpansionContext(frame: nil, slots: .notAllowed, depth: 0, isTopLevel: true, quiet: false)
            let expanded = expand(nodes, context: root, state: state)
            var defines: [DefineDecl] = []
            for name in state.order {
                guard let definition = state.definitions[name] else { continue }
                var bindings: [String: ParameterBinding] = [:]
                for parameter in definition.declaration.parameters {
                    bindings[parameter.name] = .runtime
                }
                let frame = UseFrame(defineName: name, defineSpan: definition.node.kdl.span, useSpan: nil, bindings: bindings, parent: nil)
                let context = ExpansionContext(frame: frame, slots: .placeholder, depth: 0, isTopLevel: false, quiet: false)
                var declaration = definition.declaration
                declaration.body = expand(definition.rawBody, context: context, state: state).nodes
                defines.append(declaration)
            }
            return UseStageResult(nodes: expanded.nodes, defines: defines, diagnostics: state.diagnostics, nodeCount: state.nodeCount)
        }
    }

    private static func collectDefinition(_ node: ExpandedNode, state: UseExpansionState) {
        let kdl = node.kdl
        guard kdl.arguments.count == 1, case .string(let name) = kdl.arguments[0].scalar else {
            state.report(Diagnostic(.error, "'define' needs exactly one name", span: kdl.span), at: node, frame: nil)
            return
        }
        guard isValidDefineName(name) else {
            state.report(Diagnostic(.error, "invalid define name '\(name)'", span: kdl.arguments[0].span, help: "use kebab-case, optionally with a package prefix like 'package-id/name'"), at: node, frame: nil)
            return
        }
        for property in kdl.properties where property.name != "override" {
            reportUnknownProperty(property, on: "define", known: ["override"], node: node, state: state)
        }
        if case .pkg(let packageID) = node.origin, !name.hasPrefix(packageID + "/") {
            state.report(Diagnostic(.warning, "define '\(name)' in package '\(packageID)' should be named '\(packageID)/\(name)'", span: kdl.arguments[0].span), at: node, frame: nil)
        }
        var parameters: [ParameterDecl] = []
        var rawBody: [ExpandedNode] = []
        for child in node.children {
            if child.kdl.name == "param" {
                if let parameter = parameter(from: child, existing: parameters, state: state) {
                    parameters.append(parameter)
                }
            } else {
                rawBody.append(child)
            }
        }
        var hasUnnamedSlot = false
        var namedSlots: [String] = []
        collectSlots(rawBody, hasUnnamedSlot: &hasUnnamedSlot, namedSlots: &namedSlots, state: state)
        guard state.definitions[name] == nil else { return }
        let declaration = DefineDecl(
            name: name,
            parameters: parameters,
            hasUnnamedSlot: hasUnnamedSlot,
            namedSlots: namedSlots,
            body: [],
            span: kdl.span,
            includeChain: node.includeChain
        )
        state.definitions[name] = Definition(declaration: declaration, node: node, rawBody: rawBody)
        state.order.append(name)
    }

    private static func parameter(from node: ExpandedNode, existing: [ParameterDecl], state: UseExpansionState) -> ParameterDecl? {
        let kdl = node.kdl
        guard kdl.arguments.count == 1, case .string(let name) = kdl.arguments[0].scalar else {
            state.report(Diagnostic(.error, "'param' needs exactly one name", span: kdl.span), at: node, frame: nil)
            return nil
        }
        let nameSpan = kdl.arguments[0].span
        guard isValidLocalName(name) else {
            state.report(Diagnostic(.error, "invalid parameter name '\(name)'", span: nameSpan, help: "names are lowercase kebab-case"), at: node, frame: nil)
            return nil
        }
        if ["true", "false", "null"].contains(name) {
            state.report(Diagnostic(.error, "'\(name)' is a keyword", span: nameSpan), at: node, frame: nil)
            return nil
        }
        if state.registry.fixedRoots.contains(name) || state.registry.providers[name] != nil {
            state.report(Diagnostic(.error, "'\(name)' is reserved", span: nameSpan), at: node, frame: nil)
        } else if state.registry.reservedProviderNames.contains(name) {
            state.report(Diagnostic(.note, "'\(name)' hides provider '\(name)'", span: nameSpan), at: node, frame: nil)
        }
        if existing.contains(where: { $0.name == name }) {
            state.report(Diagnostic(.error, "duplicate parameter '\(name)'", span: nameSpan), at: node, frame: nil)
            return nil
        }
        for property in kdl.properties where !parameterProperties.contains(property.name) {
            reportUnknownProperty(property, on: "param", known: parameterProperties, node: node, state: state)
        }
        if !node.children.isEmpty {
            state.report(Diagnostic(.error, "'param' cannot have children", span: kdl.span), at: node, frame: nil)
        }
        var type = ValueType.any
        if let typeProperty = kdl.property("type") {
            if case .string(let text) = typeProperty.value.scalar, let parsed = parseType(text) {
                type = parsed
            } else {
                state.report(Diagnostic(.error, "'type=' must be one of string, number, bool, list, record, any", span: typeProperty.span), at: node, frame: nil)
            }
        }
        let defaultValue = kdl.property("default")?.value
        if let defaultValue, !literal(defaultValue, matches: type) {
            state.report(Diagnostic(.error, "default of parameter '\(name)' does not match type \(typeName(type))", span: defaultValue.span), at: node, frame: nil)
        }
        return ParameterDecl(name: name, type: type, defaultValue: defaultValue, span: kdl.span)
    }

    private static func collectSlots(_ nodes: [ExpandedNode], hasUnnamedSlot: inout Bool, namedSlots: inout [String], state: UseExpansionState) {
        for node in nodes {
            if node.kdl.name == "slot" {
                validateSlot(node, state: state)
                if let name = slotName(node) {
                    if !namedSlots.contains(name) {
                        namedSlots.append(name)
                    }
                } else {
                    hasUnnamedSlot = true
                }
                continue
            }
            if node.kdl.name == "define" { continue }
            collectSlots(node.children, hasUnnamedSlot: &hasUnnamedSlot, namedSlots: &namedSlots, state: state)
        }
    }

    private static func validateSlot(_ node: ExpandedNode, state: UseExpansionState) {
        let kdl = node.kdl
        let hasValidName = kdl.arguments.isEmpty || (kdl.arguments.count == 1 && isValidSlotName(kdl.arguments[0]))
        if !hasValidName {
            state.report(Diagnostic(.error, "'slot' takes at most one name", span: kdl.span), at: node, frame: nil)
        }
        for property in kdl.properties {
            reportUnknownProperty(property, on: "slot", known: [], node: node, state: state)
        }
        if !node.children.isEmpty {
            state.report(Diagnostic(.error, "'slot' cannot have children", span: kdl.span), at: node, frame: nil)
        }
    }

    private static func isValidSlotName(_ value: KDLValue) -> Bool {
        guard case .string(let name) = value.scalar else { return false }
        return isValidLocalName(name)
    }

    private static func slotName(_ node: ExpandedNode) -> String? {
        guard let first = node.kdl.arguments.first, case .string(let name) = first.scalar else { return nil }
        return name
    }

    private static func expand(_ nodes: [ExpandedNode], context: ExpansionContext, state: UseExpansionState) -> Built {
        var built = Built()
        expand(nodes, context: context, state: state, into: &built)
        return built
    }

    private static func expand(_ nodes: [ExpandedNode], context: ExpansionContext, state: UseExpansionState, into built: inout Built) {
        if state.budgetHit || nodes.isEmpty { return }
        if context.depth > ConfigLimits.maxExpandedDepth {
            reportDepth(at: nodes[0], frame: context.frame, state: state)
            return
        }
        for node in nodes {
            if state.budgetHit { break }
            switch node.kdl.name {
            case "define":
                if context.isTopLevel { continue }
                reportUnlessQuiet(Diagnostic(.error, "'define' is only allowed at the top level", span: node.kdl.span), at: node, context: context, state: state)
            case "param":
                reportUnlessQuiet(Diagnostic(.error, "'param' is only allowed directly inside 'define'", span: node.kdl.span), at: node, context: context, state: state)
            case "fill":
                reportUnlessQuiet(Diagnostic(.error, "'fill' is only allowed directly inside 'use'", span: node.kdl.span), at: node, context: context, state: state)
            case "slot":
                insertSlot(node, context: context, state: state, into: &built)
            case "use":
                expandUse(node, context: context, state: state, into: &built)
            default:
                guard countNode(node, frame: context.frame, state: state) else { break }
                let children = expand(node.children, context: context.nested(), state: state)
                var copy = node
                copy.children = children.nodes
                copy.useFrame = context.frame
                built.append(copy, height: 1 + children.height, count: 1 + children.count)
            }
        }
    }

    private static func insertSlot(_ node: ExpandedNode, context: ExpansionContext, state: UseExpansionState, into built: inout Built) {
        switch context.slots {
        case .notAllowed:
            reportUnlessQuiet(Diagnostic(.error, "'slot' is only allowed inside 'define'", span: node.kdl.span), at: node, context: context, state: state)
        case .placeholder:
            guard countNode(node, frame: context.frame, state: state) else { return }
            var copy = node
            copy.children = []
            copy.useFrame = context.frame
            built.append(copy, height: 1, count: 1)
        case .substitute(let slots):
            let name = slotName(node)
            guard let content = slots.contents[name], !content.nodes.isEmpty else { return }
            if context.depth + content.height - 1 > ConfigLimits.maxExpandedDepth {
                reportDepth(at: node, frame: context.frame, state: state)
                return
            }
            if slots.inserted.contains(name) {
                guard countCopies(content.count, at: node, frame: context.frame, state: state) else { return }
            }
            slots.inserted.insert(name)
            built.merge(content)
        }
    }

    private static func expandUse(_ node: ExpandedNode, context: ExpansionContext, state: UseExpansionState, into built: inout Built) {
        let kdl = node.kdl
        guard kdl.arguments.count == 1, case .string(let name) = kdl.arguments[0].scalar else {
            reportUnlessQuiet(Diagnostic(.error, "'use' needs exactly one define name", span: kdl.span), at: node, context: context, state: state)
            return
        }
        if name.contains("{") {
            built.merge(expandRuntimeUse(node, context: context, state: state))
            return
        }
        guard let definition = state.definitions[name] else {
            let suggestion = Suggestion.closest(to: name, among: state.order)
            reportUnlessQuiet(Diagnostic(.error, "unknown define '\(name)'", span: kdl.arguments[0].span, help: suggestion.map { "did you mean '\($0)'?" }), at: node, context: context, state: state)
            return
        }
        if let frame = context.frame {
            if frame.contains(defineName: name) {
                let names = frame.defineNamesFromOutermost
                let start = names.firstIndex(of: name) ?? 0
                let cycle = Array(names[start...]) + [name]
                let key = Array(Set(cycle)).sorted()
                if !state.reportedCycles.contains(key) {
                    state.reportedCycles.insert(key)
                    state.report(Diagnostic(.error, "use cycle: \(cycle.joined(separator: " -> "))", span: kdl.span), at: node, frame: frame)
                }
                return
            }
            if frame.nesting >= ConfigLimits.maxExpandedDepth {
                if !state.nestingHit {
                    state.nestingHit = true
                    state.report(Diagnostic(.error, "use is nested deeper than \(ConfigLimits.maxExpandedDepth) levels", span: kdl.span), at: node, frame: frame)
                }
                return
            }
        }
        let declaration = definition.declaration
        var hasErrors = false
        var bindings: [String: ParameterBinding] = [:]
        let parameterNames = declaration.parameters.map(\.name)
        for property in kdl.properties {
            guard let parameter = declaration.parameters.first(where: { $0.name == property.name }) else {
                hasErrors = true
                let suggestion = Suggestion.closest(to: property.name, among: parameterNames)
                reportUnlessQuiet(Diagnostic(.error, "unknown parameter '\(property.name)' for '\(name)'", span: property.span, help: suggestion.map { "did you mean '\($0)'?" }), at: node, context: context, state: state)
                continue
            }
            if !literal(property.value, matches: parameter.type) {
                hasErrors = true
                reportUnlessQuiet(Diagnostic(.error, "parameter '\(parameter.name)' of '\(name)' expects \(typeName(parameter.type))", span: property.value.span), at: node, context: context, state: state)
            }
            bindings[parameter.name] = .argument(property.value)
        }
        for parameter in declaration.parameters where bindings[parameter.name] == nil {
            if let defaultValue = parameter.defaultValue {
                bindings[parameter.name] = .defaultValue(defaultValue)
            } else {
                hasErrors = true
                reportUnlessQuiet(Diagnostic(.error, "missing parameter '\(parameter.name)' for '\(name)'", span: kdl.span), at: node, context: context, state: state)
            }
        }
        var fills: [(String, ExpandedNode)] = []
        var unnamed: [ExpandedNode] = []
        for child in node.children {
            guard child.kdl.name == "fill" else {
                unnamed.append(child)
                continue
            }
            guard let slot = slotName(child), child.kdl.arguments.count == 1 else {
                hasErrors = true
                reportUnlessQuiet(Diagnostic(.error, "'fill' needs exactly one slot name", span: child.kdl.span), at: child, context: context, state: state)
                continue
            }
            if !declaration.namedSlots.contains(slot) {
                hasErrors = true
                let suggestion = Suggestion.closest(to: slot, among: declaration.namedSlots)
                reportUnlessQuiet(Diagnostic(.error, "'\(name)' has no slot '\(slot)'", span: child.kdl.arguments[0].span, help: suggestion.map { "did you mean '\($0)'?" }), at: child, context: context, state: state)
                continue
            }
            if fills.contains(where: { $0.0 == slot }) {
                hasErrors = true
                reportUnlessQuiet(Diagnostic(.error, "duplicate fill '\(slot)'", span: child.kdl.span), at: child, context: context, state: state)
                continue
            }
            fills.append((slot, child))
        }
        if let first = unnamed.first, !declaration.hasUnnamedSlot {
            hasErrors = true
            reportUnlessQuiet(Diagnostic(.error, "'\(name)' has no slot, so 'use' cannot have children", span: first.kdl.span), at: first, context: context, state: state)
        }
        var contentContext = context
        contentContext.isTopLevel = false
        var contents: [String?: Built] = [:]
        if !unnamed.isEmpty {
            contents[nil] = expand(unnamed, context: contentContext, state: state)
        }
        for (slot, fill) in fills {
            contents[slot] = expand(fill.children, context: contentContext, state: state)
        }
        if hasErrors || state.budgetHit { return }
        let frame = UseFrame(defineName: name, defineSpan: definition.node.kdl.span, useSpan: kdl.span, bindings: bindings, parent: context.frame)
        let bodyContext = ExpansionContext(frame: frame, slots: .substitute(SlotContents(contents)), depth: context.depth, isTopLevel: false, quiet: true)
        expand(definition.rawBody, context: bodyContext, state: state, into: &built)
    }

    private static func expandRuntimeUse(_ node: ExpandedNode, context: ExpansionContext, state: UseExpansionState) -> Built {
        var built = Built()
        guard countNode(node, frame: context.frame, state: state) else { return built }
        var children = Built()
        for child in node.children {
            if state.budgetHit { break }
            if child.kdl.name == "fill" {
                guard countNode(child, frame: context.frame, state: state) else { break }
                let inner = expand(child.children, context: context.nested(by: 2), state: state)
                var copy = child
                copy.children = inner.nodes
                copy.useFrame = context.frame
                children.append(copy, height: 1 + inner.height, count: 1 + inner.count)
            } else {
                children.merge(expand([child], context: context.nested(), state: state))
            }
        }
        var copy = node
        copy.children = children.nodes
        copy.useFrame = context.frame
        built.append(copy, height: 1 + children.height, count: 1 + children.count)
        return built
    }

    private static func countNode(_ node: ExpandedNode, frame: UseFrame?, state: UseExpansionState) -> Bool {
        countCopies(1, at: node, frame: frame, state: state)
    }

    private static func countCopies(_ amount: Int, at node: ExpandedNode, frame: UseFrame?, state: UseExpansionState) -> Bool {
        if state.budgetHit { return false }
        guard state.nodeCount + amount <= ConfigLimits.maxExpansionBudget else {
            state.nodeCount = ConfigLimits.maxExpansionBudget + 1
            state.budgetHit = true
            state.report(Diagnostic(.error, "config expands to more than \(ConfigLimits.maxExpansionBudget) nodes", span: node.kdl.span), at: node, frame: frame)
            return false
        }
        state.nodeCount += amount
        return true
    }

    private static func reportDepth(at node: ExpandedNode, frame: UseFrame?, state: UseExpansionState) {
        guard !state.depthHit else { return }
        state.depthHit = true
        state.report(Diagnostic(.error, "config is nested deeper than \(ConfigLimits.maxExpandedDepth) levels after use", span: node.kdl.span), at: node, frame: frame)
    }

    private static func reportUnlessQuiet(_ diagnostic: Diagnostic, at node: ExpandedNode, context: ExpansionContext, state: UseExpansionState) {
        guard !context.quiet else { return }
        state.report(diagnostic, at: node, frame: context.frame)
    }

    private static func reportUnknownProperty(_ property: KDLProperty, on nodeName: String, known: [String], node: ExpandedNode, state: UseExpansionState) {
        let suggestion = Suggestion.closest(to: property.name, among: known)
        state.report(Diagnostic(.error, "unknown property '\(property.name)' on '\(nodeName)'", span: property.span, help: suggestion.map { "did you mean '\($0)'?" }), at: node, frame: nil)
    }

    private static func literal(_ value: KDLValue, matches type: ValueType) -> Bool {
        let literalType: ValueType
        switch value.scalar {
        case .string(let text):
            if text.contains("{") { return true }
            literalType = .string
        case .number:
            literalType = .number
        case .bool:
            literalType = .bool
        case .null:
            return true
        }
        return type == .any || type == literalType
    }

    private static func parseType(_ text: String) -> ValueType? {
        switch text {
        case "string": return .string
        case "number": return .number
        case "bool": return .bool
        case "list": return .list
        case "record": return .record
        case "any": return .any
        default: return nil
        }
    }

    private static func typeName(_ type: ValueType) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .list: return "list"
        case .record: return "record"
        default: return "any"
        }
    }

    static func isValidDefineName(_ name: String) -> Bool {
        let segments = name.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 1 || segments.count == 2 else { return false }
        return segments.allSatisfy(isKebabSegment)
    }

    private static func isKebabSegment(_ segment: Substring) -> Bool {
        guard let first = segment.first, first.isASCII, first.isLowercase, segment.last != "-", !segment.contains("--") else { return false }
        return segment.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLowercase || $0.isNumber)) }
    }

    static func isValidLocalName(_ name: String) -> Bool {
        let characters = Array(name)
        guard let first = characters.first, ExpressionLexer.isNameStart(first) else { return false }
        var index = 1
        while index < characters.count {
            if ExpressionLexer.isNameCharacter(characters[index]) {
                index += 1
            } else if characters[index] == "-", index + 1 < characters.count, ExpressionLexer.isNameCharacter(characters[index + 1]) {
                index += 2
            } else {
                return false
            }
        }
        return true
    }
}
