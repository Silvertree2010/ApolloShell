import ApolloBase

struct DefineReach: Sendable {
    var all = false
    var exact: Set<String> = []
    var affixes: [(String, String)] = []

    static let everything = DefineReach(all: true)

    func keeps(_ name: String) -> Bool {
        all || exact.contains(name) || affixes.contains { name.count >= $0.0.count + $0.1.count && name.hasPrefix($0.0) && name.hasSuffix($0.1) }
    }

    static func scan(_ nodes: [ExpandedNode], defines: [DefineDecl]) -> DefineReach {
        var r = DefineReach()
        var st: [ExpandedNode] = nodes
        for d in defines { st.append(contentsOf: d.body) }
        while let n = st.popLast(), !r.all {
            st.append(contentsOf: n.children)
            guard n.kdl.name == "use", !n.isExpansionMarker else { continue }
            guard n.kdl.arguments.count == 1, case .string(let t) = n.kdl.arguments[0].scalar else { continue }
            guard t.utf8.contains(UInt8(ascii: "{")) else { continue }
            r.add(t, span: n.kdl.arguments[0].span)
        }
        return r
    }

    mutating func add(_ t: String, span: SourceSpan) {
        guard case .success(let tp) = ExpressionParser.parseTemplate(t, span: span) else {
            all = true
            return
        }
        switch tp {
        case .literal(let s):
            exact.insert(s)
        case .whole:
            all = true
        case .parts(let ps):
            var pre = "", suf = ""
            if case .text(let s)? = ps.first { pre = s }
            if ps.count > 1, case .text(let s)? = ps.last { suf = s }
            if pre.isEmpty && suf.isEmpty { all = true } else { affixes.append((pre, suf)) }
        }
    }
}
