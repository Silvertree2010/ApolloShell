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

    init(kdl: KDLNode, file: String, includeChain: [SourceSpan], children: [ExpandedNode]) {
        var stripped = kdl
        stripped.children = nil
        self.kdl = stripped
        self.file = file
        self.includeChain = includeChain
        self.children = children
    }
}

struct IncludeExpansionResult: Sendable {
    var nodes: [ExpandedNode]
    var diagnostics: [Diagnostic]
    var files: [URL]
}
