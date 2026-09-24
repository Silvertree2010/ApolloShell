import Foundation
import ApolloBase
import ApolloKDL

struct FeatureStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
}

private enum NodeIdentity: Hashable {
    case define(String)
    case surface(String)
    case bind(String)
    case on(String)
}

enum FeatureStage {
    static func run(_ nodes: [ExpandedNode], shellVersion: String, registry: SchemaRegistry) -> FeatureStageResult {
        StackHeadroom.run {
            if let failure = checkRequire(nodes, shellVersion: shellVersion, registry: registry) {
                return FeatureStageResult(nodes: [], diagnostics: [failure])
            }
            var diagnostics: [Diagnostic] = []
            var resolved = resolveFeatures(nodes, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics)
            resolved = applyOverride(resolved, registry: registry, diagnostics: &diagnostics)
            resolved = applyDisable(resolved, registry: registry, diagnostics: &diagnostics)
            return FeatureStageResult(nodes: resolved, diagnostics: diagnostics)
        }
    }

    private static func checkRequire(_ nodes: [ExpandedNode], shellVersion: String, registry: SchemaRegistry) -> Diagnostic? {
        for node in nodes where node.kdl.name == "require" {
            if let argument = node.kdl.arguments.first, case .string(let version) = argument.scalar {
                guard let comparison = SemanticVersion.compare(shellVersion, version) else {
                    return DiagnosticCollector.withIncludeChain(Diagnostic(.error, "invalid version '\(version)'", span: argument.span), chain: node.includeChain)
                }
                if comparison < 0 {
                    return DiagnosticCollector.withIncludeChain(Diagnostic(.error, "this config needs ApolloShell \(version) or newer", span: node.kdl.span), chain: node.includeChain)
                }
            }
            if let property = node.kdl.property("feature"), case .string(let name) = property.value.scalar {
                if !isFeaturePresent(name, shellVersion: shellVersion, registry: registry) {
                    return DiagnosticCollector.withIncludeChain(Diagnostic(.error, "this config needs ApolloShell feature '\(name)'", span: node.kdl.span), chain: node.includeChain)
                }
            }
        }
        return nil
    }

    private static func isFeaturePresent(_ name: String, shellVersion: String, registry: SchemaRegistry) -> Bool {
        guard let schema = registry.features[name] else { return false }
        guard let comparison = SemanticVersion.compare(shellVersion, schema.since) else { return false }
        return comparison >= 0
    }

    private static func resolveFeatures(
        _ nodes: [ExpandedNode],
        shellVersion: String,
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic]
    ) -> [ExpandedNode] {
        var result: [ExpandedNode] = []
        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            if node.kdl.name == "require" {
                index += 1
                continue
            }
            if node.kdl.name == "else" {
                if index > 0, nodes[index - 1].kdl.name == "when" {
                    var copy = node
                    copy.children = resolveFeatures(node.children, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics)
                    result.append(copy)
                    index += 1
                    continue
                }
                diagnostics.append(DiagnosticCollector.withIncludeChain(
                    Diagnostic(.error, "'else' without a preceding 'when' or 'feature'", span: node.kdl.span),
                    chain: node.includeChain
                ))
                index += 1
                continue
            }
            if node.kdl.name == "feature" {
                var consumed = 1
                var elseNode: ExpandedNode?
                if index + 1 < nodes.count, nodes[index + 1].kdl.name == "else" {
                    elseNode = nodes[index + 1]
                    consumed = 2
                }
                guard let name = argumentString(node) else {
                    diagnostics.append(DiagnosticCollector.withIncludeChain(
                        Diagnostic(.error, "'feature' requires a name", span: node.kdl.span),
                        chain: node.includeChain
                    ))
                    index += consumed
                    continue
                }
                if isFeaturePresent(name, shellVersion: shellVersion, registry: registry) {
                    result.append(contentsOf: resolveFeatures(node.children, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics))
                } else {
                    diagnostics.append(DiagnosticCollector.withIncludeChain(
                        Diagnostic(.note, "unknown feature '\(name)'", span: node.kdl.span),
                        chain: node.includeChain
                    ))
                    if let elseNode {
                        result.append(contentsOf: resolveFeatures(elseNode.children, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics))
                    }
                }
                index += consumed
                continue
            }
            var copy = node
            copy.children = resolveFeatures(node.children, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics)
            result.append(copy)
            index += 1
        }
        return result
    }

    private static func applyOverride(
        _ nodes: [ExpandedNode],
        registry: SchemaRegistry,
        diagnostics: inout [Diagnostic]
    ) -> [ExpandedNode] {
        var result: [ExpandedNode] = []
        var indexByIdentity: [NodeIdentity: Int] = [:]
        for node in nodes {
            guard let identity = overridableIdentity(of: node, registry: registry) else {
                result.append(node)
                continue
            }
            let isOverride = boolProperty(node, "override") ?? false
            if let existingIndex = indexByIdentity[identity] {
                if isOverride {
                    result[existingIndex] = node
                } else {
                    diagnostics.append(DiagnosticCollector.withIncludeChain(
                        Diagnostic(
                            .error,
                            "duplicate \(describe(identity)); add override=#true to replace it",
                            span: node.kdl.span,
                            notes: [DiagnosticNote("first defined here", span: result[existingIndex].kdl.span)]
                        ),
                        chain: node.includeChain
                    ))
                }
            } else {
                if isOverride {
                    diagnostics.append(DiagnosticCollector.withIncludeChain(
                        Diagnostic(.warning, "override=#true on \(describe(identity)) without a previous definition", span: node.kdl.span),
                        chain: node.includeChain
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
        for node in nodes where node.kdl.name == "disable" {
            if let property = node.kdl.property("surface"), case .string(let id) = property.value.scalar {
                targets[.surface(id)] = node
            } else if let property = node.kdl.property("bind"), case .string(let raw) = property.value.scalar {
                targets[.bind(normalizeChord(raw))] = node
            } else if let property = node.kdl.property("on"), case .string(let event) = property.value.scalar {
                targets[.on(event)] = node
            } else {
                diagnostics.append(DiagnosticCollector.withIncludeChain(
                    Diagnostic(.error, "'disable' needs 'surface=', 'bind=' or 'on='", span: node.kdl.span),
                    chain: node.includeChain
                ))
            }
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
        for (identity, node) in targets where !matched.contains(identity) {
            diagnostics.append(DiagnosticCollector.withIncludeChain(
                Diagnostic(.warning, "unknown target for disable: \(describe(identity))", span: node.kdl.span),
                chain: node.includeChain
            ))
        }
        return result
    }

    private static func overridableIdentity(of node: ExpandedNode, registry: SchemaRegistry) -> NodeIdentity? {
        if node.kdl.name == "define", let name = argumentString(node) {
            return .define(name)
        }
        if node.kdl.name == "bind" {
            return .bind(bindIdentity(node))
        }
        if let schema = registry.node(node.kdl.name), schema.category == .surface, let id = argumentString(node) {
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
