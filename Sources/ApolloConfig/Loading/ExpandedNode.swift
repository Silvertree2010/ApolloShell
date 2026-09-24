import Foundation
import ApolloBase
import ApolloKDL

enum FileOrigin: Sendable, Hashable {
    case user
    case builtin(String)
    case pkg(String)
}

struct ExpandedNode: Sendable, Hashable {
    var kdl: KDLNode
    var file: String
    var includeChain: [SourceSpan]
    var children: [ExpandedNode]
    var origin: FileOrigin
    var useFrame: UseFrame?
    var letValues: [String: Value] = [:]
    var poisonedLets: Set<String> = []
    var isExpansionMarker = false

    init(kdl: KDLNode, file: String, includeChain: [SourceSpan], children: [ExpandedNode], origin: FileOrigin = .user, useFrame: UseFrame? = nil, letValues: [String: Value] = [:]) {
        var stripped = kdl
        stripped.children = nil
        self.kdl = stripped
        self.file = file
        self.includeChain = includeChain
        self.children = children
        self.origin = origin
        self.useFrame = useFrame
        self.letValues = letValues
    }
}

extension ExpandedNode {
    func reattachingChildren() -> KDLNode {
        var result = kdl
        result.children = children.isEmpty ? nil : children.map { $0.reattachingChildren() }
        return result
    }
}

struct IncludeExpansionResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
    var files: [URL]
}
