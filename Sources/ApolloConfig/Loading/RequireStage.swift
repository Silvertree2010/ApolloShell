import Foundation
import ApolloBase
import ApolloKDL

struct RequireStageResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
}

enum RequireStage {
    static func run(_ nodes: [ExpandedNode], shellVersion: String, registry: SchemaRegistry) -> RequireStageResult {
        StackHeadroom.run {
            if let failure = checkRequire(nodes, shellVersion: shellVersion) {
                return RequireStageResult(nodes: [], diagnostics: [failure])
            }
            var diagnostics: [Diagnostic] = []
            var resolved = checkElse(nodes, diagnostics: &diagnostics)
            resolved = DisableStage.applyOverride(resolved, kinds: [.define], registry: registry, diagnostics: &diagnostics)
            return RequireStageResult(nodes: resolved, diagnostics: diagnostics)
        }
    }

    private static func checkRequire(_ nodes: [ExpandedNode], shellVersion: String) -> Diagnostic? {
        for node in nodes where node.kdl.name == "require" {
            guard let argument = node.kdl.arguments.first, case .string(let version) = argument.scalar else { continue }
            guard let comparison = SemanticVersion.compare(shellVersion, version) else {
                return DiagnosticCollector.withIncludeChain(Diagnostic(.error, "invalid version '\(version)'", span: argument.span), chain: node.includeChain)
            }
            if comparison < 0 {
                return DiagnosticCollector.withIncludeChain(Diagnostic(.error, "this config needs ApolloShell \(version) or newer", span: node.kdl.span), chain: node.includeChain)
            }
        }
        return nil
    }

    private static func checkElse(_ nodes: [ExpandedNode], diagnostics: inout [Diagnostic]) -> [ExpandedNode] {
        var result: [ExpandedNode] = []
        for (index, node) in nodes.enumerated() {
            if node.kdl.name == "else", index == 0 || nodes[index - 1].kdl.name != "when" {
                diagnostics.append(DiagnosticCollector.withIncludeChain(
                    Diagnostic(.error, "'else' without a preceding 'when'", span: node.kdl.span),
                    chain: node.includeChain
                ))
                continue
            }
            var copy = node
            copy.children = checkElse(node.children, diagnostics: &diagnostics)
            result.append(copy)
        }
        return result
    }
}
