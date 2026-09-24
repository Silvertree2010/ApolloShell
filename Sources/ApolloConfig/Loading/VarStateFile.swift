import ApolloBase
import ApolloKDL

public enum VarStateFile {
    public static func read(_ text: String, file: String, declarations: [VarDecl]) -> ([String: Value], [Diagnostic]) {
        guard let document = try? KDLDocument.parse(text, file: file) else {
            return ([:], [Diagnostic(.warning, "state file could not be parsed, using defaults", span: .synthetic(file), kind: .stateFileUnreadable)])
        }
        let byName = Dictionary(uniqueKeysWithValues: declarations.map { ($0.name, $0) })
        var values: [String: Value] = [:]
        var diagnostics: [Diagnostic] = []
        var seen: Set<String> = []
        for node in document.nodes {
            guard let declaration = byName[node.name] else { continue }
            if declaration.derived != nil { continue }
            if seen.contains(node.name) {
                diagnostics.append(Diagnostic(.warning, "duplicate '\(node.name)' in state file, using the last one", span: node.span))
            }
            seen.insert(node.name)
            let value = ValueKDLMapping.value(from: node, expectedType: declaration.type)
            if declaration.type != .any, !matches(declaration.type, value) {
                diagnostics.append(Diagnostic(.warning, "'\(node.name)' in state file has the wrong type, using the default", span: node.span, kind: .valueDiscarded))
                values.removeValue(forKey: node.name)
                continue
            }
            values[node.name] = value
        }
        return (values, diagnostics)
    }

    public static func readAll(_ text: String, file: String) -> ([String: Value], [Diagnostic]) {
        guard let document = try? KDLDocument.parse(text, file: file) else {
            return ([:], [Diagnostic(.warning, "state file could not be parsed, using defaults", span: .synthetic(file), kind: .stateFileUnreadable)])
        }
        var values: [String: Value] = [:]
        var diagnostics: [Diagnostic] = []
        for node in document.nodes {
            if values[node.name] != nil {
                diagnostics.append(Diagnostic(.warning, "duplicate '\(node.name)' in state file, using the last one", span: node.span))
            }
            values[node.name] = ValueKDLMapping.value(from: node)
        }
        return (values, diagnostics)
    }

    public static func writing(_ values: [String: Value], into text: String, file: String) throws -> String {
        let document = try KDLDocument.parse(text, file: file)
        var editor = KDLEditor(document)
        for name in values.keys.sorted() {
            guard let value = values[name] else { continue }
            let newNode = ValueKDLMapping.node(named: name, value: value)
            if let index = editor.document.nodes.lastIndex(where: { $0.name == name }) {
                let existing = ValueKDLMapping.value(from: editor.document.nodes[index])
                if existing == value { continue }
                try editor.replace(at: [index], with: newNode)
            } else {
                try editor.insert(newNode, intoChildrenOf: nil, at: editor.document.nodes.count)
            }
        }
        return editor.text
    }

    static func matches(_ type: ValueType, _ value: Value) -> Bool {
        switch type {
        case .string:
            if case .string = value { return true }
            return false
        case .number:
            if case .number = value { return true }
            return false
        case .bool:
            if case .bool = value { return true }
            return false
        case .list:
            if case .list = value { return true }
            return false
        case .record:
            if case .record = value { return true }
            return false
        default:
            return true
        }
    }
}
