import Foundation
import ApolloBase
import ApolloKDL

struct FeatureStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
}

enum FeatureStage {
    static func run(_ nodes: [ExpandedNode], shellVersion: String, registry: SchemaRegistry) -> FeatureStageResult {
        StackHeadroom.run {
            if let failure = checkRequire(nodes, shellVersion: shellVersion, registry: registry) {
                return FeatureStageResult(nodes: [], diagnostics: [failure])
            }
            var diagnostics: [Diagnostic] = []
            var resolved = resolveFeatures(nodes, shellVersion: shellVersion, registry: registry, diagnostics: &diagnostics)
            resolved = DisableStage.applyOverride(resolved, kinds: [.define], registry: registry, diagnostics: &diagnostics)
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

    private static func argumentString(_ node: ExpandedNode) -> String? {
        guard let first = node.kdl.arguments.first, case .string(let value) = first.scalar else { return nil }
        return value
    }
}
