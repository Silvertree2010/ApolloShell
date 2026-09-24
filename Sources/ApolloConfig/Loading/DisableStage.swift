import ApolloBase
import ApolloKDL

struct DisableStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
}

enum OverrideKind: Sendable, Hashable {
    case define
    case surface
    case bind
}

private enum NodeIdentity: Hashable {
    case define(String)
    case surface(String)
    case bind(String)
    case on(String)
}

enum DisableStage {
    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry) -> DisableStageResult {
        var diagnostics: [Diagnostic] = []
        var resolved = applyOverride(nodes, kinds: [.surface, .bind], registry: registry, diagnostics: &diagnostics)
        resolved = applyDisable(resolved, registry: registry, diagnostics: &diagnostics)
        return DisableStageResult(nodes: resolved, diagnostics: diagnostics)
    }

    static func applyOverride(
        _ nodes: [ExpandedNode],
        kinds: Set<OverrideKind>,
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic]
    ) -> [ExpandedNode] {
        var result: [ExpandedNode] = []
        var indexByIdentity: [NodeIdentity: Int] = [:]
        for node in nodes {
            guard let identity = overridableIdentity(of: node, kinds: kinds, registry: registry) else {
                result.append(node)
                continue
            }
            let isOverride = boolProperty(node, "override") ?? false
            if let existingIndex = indexByIdentity[identity] {
                if isOverride {
                    result[existingIndex] = node
                } else {
                    diagnostics.append(DiagnosticCollector.withExpansionChain(
                        Diagnostic(
                            .error,
                            "duplicate \(describe(identity)); add override=#true to replace it",
                            span: node.kdl.span,
                            notes: [DiagnosticNote("first defined here", span: result[existingIndex].kdl.span)]
                        ),
                        node: node
                    ))
                }
            } else {
                if isOverride {
                    diagnostics.append(DiagnosticCollector.withExpansionChain(
                        Diagnostic(.warning, "override=#true on \(describe(identity)) without a previous definition", span: node.kdl.span),
                        node: node
                    ))
                }
                indexByIdentity[identity] = result.count
                result.append(node)
            }
        }
        return result
    }

    private static func applyDisable(
        _ nodes: [ExpandedNode],
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic]
    ) -> [ExpandedNode] {
        var targets: [NodeIdentity: ExpandedNode] = [:]
        var targetOrder: [NodeIdentity] = []
        for node in nodes where node.kdl.name == "disable" {
            let identity: NodeIdentity
            if let property = node.kdl.property("surface"), case .string(let id) = property.value.scalar {
                identity = .surface(id)
            } else if let property = node.kdl.property("bind"), case .string(let raw) = property.value.scalar {
                identity = .bind(normalizeChord(raw))
            } else if let property = node.kdl.property("on"), case .string(let event) = property.value.scalar {
                identity = .on(event)
            } else {
                diagnostics.append(DiagnosticCollector.withExpansionChain(
                    Diagnostic(.error, "'disable' needs 'surface=', 'bind=' or 'on='", span: node.kdl.span),
                    node: node
                ))
                continue
            }
            if targets[identity] == nil {
                targetOrder.append(identity)
            }
            targets[identity] = node
        }
        var matched: Set<NodeIdentity> = []
        var result: [ExpandedNode] = []
        for node in nodes {
            if node.kdl.name == "disable" { continue }
            if let identity = disableIdentity(of: node, registry: registry), targets[identity] != nil {
                matched.insert(identity)
                continue
            }
            result.append(node)
        }
        for identity in targetOrder where !matched.contains(identity) {
            guard let node = targets[identity] else { continue }
            diagnostics.append(DiagnosticCollector.withExpansionChain(
                Diagnostic(.warning, "unknown target for disable: \(describe(identity))", span: node.kdl.span),
                node: node
            ))
        }
        return result
    }

    private static func overridableIdentity(of node: ExpandedNode, kinds: Set<OverrideKind>, registry: SchemaRegistry) -> NodeIdentity? {
        if node.kdl.name == "define" {
            guard kinds.contains(.define), let name = argumentString(node) else { return nil }
            return .define(name)
        }
        if node.kdl.name == "bind" {
            guard kinds.contains(.bind) else { return nil }
            return .bind(bindIdentity(node))
        }
        if kinds.contains(.surface), let schema = registry.node(node.kdl.name), schema.category == .surface, let id = argumentString(node) {
            return .surface(id)
        }
        return nil
    }

    private static func disableIdentity(of node: ExpandedNode, registry: SchemaRegistry) -> NodeIdentity? {
        if node.kdl.name == "bind" {
            return .bind(bindIdentity(node))
        }
        if node.kdl.name == "on", let event = argumentString(node) {
            return .on(event)
        }
        if let schema = registry.node(node.kdl.name), schema.category == .surface, let id = argumentString(node) {
            return .surface(id)
        }
        return nil
    }

    private static func bindIdentity(_ node: ExpandedNode) -> String {
        if let explicit = stringProperty(node, "id") {
            return explicit
        }
        return normalizeChord(argumentString(node) ?? "")
    }

    private static func normalizeChord(_ raw: String) -> String {
        KeyChord.parse(raw)?.canonical ?? raw
    }

    private static func argumentString(_ node: ExpandedNode) -> String? {
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

    private static func describe(_ identity: NodeIdentity) -> String {
        switch identity {
        case .define(let name): return "define '\(name)'"
        case .surface(let id): return "surface '\(id)'"
        case .bind(let id): return "bind '\(id)'"
        case .on(let event): return "on '\(event)'"
        }
    }
}
