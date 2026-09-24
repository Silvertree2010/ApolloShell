import ApolloBase
import ApolloKDL

enum ParameterBinding: Sendable, Hashable {
    case argument(KDLValue)
    case defaultValue(KDLValue)
    case runtime
}

struct ParameterResolution: Sendable, Hashable {
    var value: KDLValue
    var scope: UseFrame?
}

final class UseFrame: Sendable, Hashable {
    let defineName: String
    let defineSpan: SourceSpan
    let useSpan: SourceSpan?
    let bindings: [String: ParameterBinding]
    let parent: UseFrame?
    let nesting: Int
    let callSite: ExpandedNode?

    init(defineName: String, defineSpan: SourceSpan, useSpan: SourceSpan?, bindings: [String: ParameterBinding], parent: UseFrame?, callSite: ExpandedNode? = nil) {
        self.defineName = defineName
        self.defineSpan = defineSpan
        self.useSpan = useSpan
        self.bindings = bindings
        self.parent = parent
        self.nesting = (parent?.nesting ?? 0) + 1
        self.callSite = callSite
    }

    func resolve(_ name: String) -> ParameterResolution? {
        switch bindings[name] {
        case .argument(let value):
            return ParameterResolution(value: value, scope: parent)
        case .defaultValue(let value):
            return ParameterResolution(value: value, scope: nil)
        case .runtime, nil:
            return nil
        }
    }

    func contains(defineName name: String) -> Bool {
        var current: UseFrame? = self
        while let frame = current {
            if frame.defineName == name { return true }
            current = frame.parent
        }
        return false
    }

    var defineNamesFromOutermost: [String] {
        var names: [String] = []
        var current: UseFrame? = self
        while let frame = current {
            names.append(frame.defineName)
            current = frame.parent
        }
        return names.reversed()
    }

    static func == (lhs: UseFrame, rhs: UseFrame) -> Bool {
        if lhs === rhs { return true }
        return lhs.defineName == rhs.defineName
            && lhs.defineSpan == rhs.defineSpan
            && lhs.useSpan == rhs.useSpan
            && lhs.bindings == rhs.bindings
            && lhs.parent == rhs.parent
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(defineName)
        hasher.combine(defineSpan)
        hasher.combine(useSpan)
        hasher.combine(bindings)
        hasher.combine(parent)
    }
}

extension DiagnosticCollector {
    static func withExpansionChain(_ diagnostic: Diagnostic, node: ExpandedNode) -> Diagnostic {
        withExpansionChain(diagnostic, includeChain: node.includeChain, frame: node.useFrame)
    }

    static func withExpansionChain(_ diagnostic: Diagnostic, includeChain: [SourceSpan], frame: UseFrame?) -> Diagnostic {
        var enriched = withIncludeChain(diagnostic, chain: includeChain)
        var current = frame
        while let link = current {
            if let span = link.useSpan {
                enriched.notes.append(DiagnosticNote("in use of '\(link.defineName)' at \(location(span))", span: span))
            }
            current = link.parent
        }
        return enriched
    }
}
