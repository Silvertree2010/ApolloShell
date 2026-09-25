import Foundation
import ApolloBase

extension SchemaRegistry {
    public static let scriptSourceKinds = ["poll", "listen"]

    public func addingScriptSources(_ names: [String: [String]]) -> SchemaRegistry {
        var copy = self
        for kind in Self.scriptSourceKinds {
            let fields = (names[kind] ?? []).flatMap { name in [
                FieldSchema(path: [name], type: .any, nullable: true, update: kind == "poll" ? .poll(seconds: 5) : .push, doc: "Value of the \(kind) source \(name)."),
                FieldSchema(path: ["\(name)-error"], type: .string, nullable: true, update: .push, doc: "Last error of \(name)."),
            ] }
            copy.providers[kind] = ProviderSchema(id: kind, feature: "script-sources", fields: fields, doc: kind == "poll" ? "Poll script sources of this config." : "Listen script sources of this config.")
        }
        return copy
    }
}

extension ConfigLoader {
    static func scriptSourceNames(_ nodes: [ExpandedNode]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for node in nodes where SchemaRegistry.scriptSourceKinds.contains(node.kdl.name) {
            guard let first = node.kdl.arguments.first, case .string(let name) = first.scalar, !name.isEmpty else { continue }
            if !(result[node.kdl.name] ?? []).contains(name) { result[node.kdl.name, default: []].append(name) }
        }
        return result
    }
}
