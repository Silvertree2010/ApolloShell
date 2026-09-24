import Foundation
import ApolloConfig

public enum SchemaFormat: Sendable {
    case text, json, markdown
}

public struct SchemaEntry: Sendable {
    public var kind: String
    public var name: String
    public var doc: String
    public var example: String?
    public var arguments: [ArgumentSchema]
    public var properties: [PropertySchema]
    public var fields: [FieldSchema]
    public var members: [String]
}

public enum SchemaText {
    public static func entries(_ registry: SchemaRegistry) -> [SchemaEntry] {
        var result: [SchemaEntry] = []
        for node in registry.nodes.values {
            result.append(SchemaEntry(kind: "node", name: node.name, doc: node.doc, example: node.example, arguments: node.arguments, properties: node.properties, fields: [], members: node.handlers))
        }
        for action in registry.actions.values {
            result.append(SchemaEntry(kind: "action", name: action.name, doc: action.doc, example: nil, arguments: action.arguments, properties: action.properties, fields: [], members: []))
        }
        for provider in registry.providers.values {
            let members = provider.actions.map(\.name) + provider.events.map(\.name)
            result.append(SchemaEntry(kind: "provider", name: provider.id, doc: provider.doc, example: nil, arguments: [], properties: provider.settings, fields: provider.fields, members: members))
        }
        for filter in registry.filters.values {
            result.append(SchemaEntry(kind: "filter", name: filter.name, doc: filter.doc, example: nil, arguments: filter.arguments, properties: [], fields: [], members: []))
        }
        for event in registry.events.values {
            result.append(SchemaEntry(kind: "event", name: event.name, doc: event.doc, example: nil, arguments: [], properties: [], fields: event.fields, members: []))
        }
        let order = ["node", "action", "provider", "filter", "event"]
        return result.sorted {
            if $0.kind != $1.kind { return order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
            return $0.name < $1.name
        }
    }

    public static func render(_ registry: SchemaRegistry, name: String?, format: SchemaFormat) -> [String]? {
        let all = entries(registry)
        guard let name else {
            switch format {
            case .text:
                return all.map { "\($0.kind) \($0.name): \($0.doc)" }
            case .json:
                return [JSONText.encode(.list(all.map(json)))]
            case .markdown:
                return [all.map(markdown).joined(separator: "\n\n")]
            }
        }
        let matches = all.filter { $0.name == name }
        guard !matches.isEmpty else { return nil }
        switch format {
        case .text:
            return [matches.map(text).joined(separator: "\n\n")]
        case .json:
            return [JSONText.encode(.list(matches.map(json)))]
        case .markdown:
            return [matches.map(markdown).joined(separator: "\n\n")]
        }
    }

    static func text(_ entry: SchemaEntry) -> String {
        var lines = ["\(entry.name) (\(entry.kind))", "  \(entry.doc)"]
        for argument in entry.arguments {
            lines.append("  argument \(argument.name): \(typeText(argument.type))\(argument.required ? "" : "?")\(argument.variadic ? "..." : "") - \(argument.doc)")
        }
        for property in entry.properties {
            lines.append("  property \(property.name): \(typeText(property.type))\(property.defaultValue.map { " = " + JSONText.encode($0) } ?? "") - \(property.doc)")
        }
        for field in entry.fields {
            lines.append("  field \(field.path.joined(separator: ".")): \(typeText(field.type))\(field.nullable ? "?" : "") - \(field.doc)")
        }
        if !entry.members.isEmpty {
            lines.append("  also: \(entry.members.joined(separator: ", "))")
        }
        if let example = entry.example, !example.isEmpty {
            lines.append("  example: \(example)")
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(_ entry: SchemaEntry) -> String {
        var lines = ["### `\(entry.name)` (\(entry.kind))", "", entry.doc]
        let rows = entry.arguments.map { "| argument | `\($0.name)` | \(typeText($0.type)) | \($0.doc) |" }
            + entry.properties.map { "| property | `\($0.name)` | \(typeText($0.type)) | \($0.doc) |" }
            + entry.fields.map { "| field | `\($0.path.joined(separator: "."))` | \(typeText($0.type)) | \($0.doc) |" }
        if !rows.isEmpty {
            lines += ["", "| | Name | Type | |", "| --- | --- | --- | --- |"] + rows
        }
        if let example = entry.example, !example.isEmpty {
            lines += ["", "```kdl", example, "```"]
        }
        return lines.joined(separator: "\n")
    }

    static func json(_ entry: SchemaEntry) -> Value {
        var pairs: [(String, Value)] = [
            ("kind", .string(entry.kind)),
            ("name", .string(entry.name)),
            ("doc", .string(entry.doc)),
        ]
        if let example = entry.example { pairs.append(("example", .string(example))) }
        pairs.append(("arguments", .list(entry.arguments.map { argument in
            .record(Record([("name", .string(argument.name)), ("type", .string(typeText(argument.type))), ("required", .bool(argument.required)), ("variadic", .bool(argument.variadic)), ("doc", .string(argument.doc))]))
        })))
        pairs.append(("properties", .list(entry.properties.map { property in
            .record(Record([("name", .string(property.name)), ("type", .string(typeText(property.type))), ("default", property.defaultValue ?? .null), ("doc", .string(property.doc))]))
        })))
        pairs.append(("fields", .list(entry.fields.map { field in
            .record(Record([("path", .string(field.path.joined(separator: "."))), ("type", .string(typeText(field.type))), ("nullable", .bool(field.nullable)), ("doc", .string(field.doc))]))
        })))
        pairs.append(("members", .list(entry.members.map(Value.string))))
        return .record(Record(pairs))
    }

    static func typeText(_ type: ValueType) -> String {
        switch type {
        case .any: "any"
        case .string: "string"
        case .number: "number"
        case .bool: "bool"
        case .duration: "duration"
        case .keyChord: "key-chord"
        case .path: "path"
        case .identifier: "identifier"
        case .value: "value"
        case .actions: "actions"
        case .list: "list"
        case .record: "record"
        case .enumeration(let names): names.map { "\"\($0)\"" }.joined(separator: "|")
        case .oneOf(let types): types.map(typeText).joined(separator: "|")
        }
    }
}
