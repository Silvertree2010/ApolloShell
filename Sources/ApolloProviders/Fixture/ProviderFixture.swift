import Foundation
import ApolloBase
import ApolloKDL
import ApolloConfig

public struct ProviderFixture: Sendable {
    public var values: [String: Record]
    public var vars = Record()
    public var shell = Record()
    public var toasts: [Value] = []
    public var diagnostics: [Diagnostic]

    public init(values: [String: Record] = [:], diagnostics: [Diagnostic] = []) {
        self.values = values
        self.diagnostics = diagnostics
    }

    public static func load(_ url: URL, registry: SchemaRegistry = .builtin) -> ProviderFixture {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ProviderFixture(diagnostics: [Diagnostic(.error, "cannot read fixture \(url.path)", span: .synthetic(url.path))])
        }
        return parse(text, file: url.path, registry: registry)
    }

    public static func parse(_ text: String, file: String, registry: SchemaRegistry = .builtin) -> ProviderFixture {
        let document: KDLDocument
        do {
            document = try KDLDocument.parse(text, file: file)
        } catch {
            return ProviderFixture(diagnostics: [Diagnostic(.error, error.message, span: error.span)])
        }
        var fixture = ProviderFixture()
        for root in document.nodes {
            guard root.name == "fixture" else {
                fixture.diagnostics.append(Diagnostic(.warning, "unknown node '\(root.name)' in fixture, expected 'fixture'", span: root.nameSpan))
                continue
            }
            for node in root.children ?? [] {
                if node.name == "vars" {
                    if case .record(let record) = ValueKDLMapping.value(from: node, expectedType: .record) { fixture.vars = record }
                    continue
                }
                if node.name == "toasts" {
                    if case .list(let list) = ValueKDLMapping.value(from: node, expectedType: .list) { fixture.toasts = list }
                    continue
                }
                if node.name == "shell" {
                    if case .record(let record) = ValueKDLMapping.value(from: node, expectedType: .record) { fixture.shell = record }
                    continue
                }
                guard let schema = registry.providers[node.name] else {
                    fixture.diagnostics.append(Diagnostic(.warning, "unknown provider '\(node.name)' in fixture", span: node.nameSpan))
                    continue
                }
                fixture.diagnostics += unknownFields(node, schema: schema, prefix: [])
                guard case .record(let record) = ValueKDLMapping.value(from: node, expectedType: .record) else { continue }
                fixture.values[node.name] = convertDates(record, schema: schema, prefix: [])
            }
        }
        return fixture
    }

    private static func unknownFields(_ node: KDLNode, schema: ProviderSchema, prefix: [String]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for property in node.properties {
            if classify(prefix + [property.name], schema) == .unknown {
                diagnostics.append(Diagnostic(.warning, "unknown field '\(fieldName(schema, prefix + [property.name]))' in fixture", span: property.span))
            }
        }
        for child in node.children ?? [] where child.name != "-" {
            let path = prefix + [child.name]
            switch classify(path, schema) {
            case .unknown:
                diagnostics.append(Diagnostic(.warning, "unknown field '\(fieldName(schema, path))' in fixture", span: child.nameSpan))
            case .group:
                diagnostics += unknownFields(child, schema: schema, prefix: path)
            case .field:
                break
            }
        }
        return diagnostics
    }

    private enum Kind { case field, group, unknown }

    private static func classify(_ path: [String], _ schema: ProviderSchema) -> Kind {
        if schema.fields.contains(where: { $0.path == path || (path.count > $0.path.count && Array(path.prefix($0.path.count)) == $0.path) }) {
            return .field
        }
        if schema.fields.contains(where: { $0.path.count > path.count && Array($0.path.prefix(path.count)) == path }) {
            return .group
        }
        return .unknown
    }

    private static func fieldName(_ schema: ProviderSchema, _ path: [String]) -> String {
        ([schema.id] + path).joined(separator: ".")
    }

    private static func convertDates(_ record: Record, schema: ProviderSchema, prefix: [String]) -> Record {
        var result = record
        for key in record.keys {
            let path = prefix + [key]
            guard let value = record[key] else { continue }
            if case .record(let inner) = value, schema.fields.contains(where: { $0.path.count > path.count && Array($0.path.prefix(path.count)) == path }) {
                result[key] = .record(convertDates(inner, schema: schema, prefix: path))
                continue
            }
            if let field = schema.fields.first(where: { $0.path == path }), field.type == .list || field.type == .record {
                result[key] = nestedDates(value)
                continue
            }
            if case .string(let text) = value,
               let field = schema.fields.first(where: { $0.path == path }), field.type == .value,
               let date = FixtureDate.parse(text) {
                result[key] = .date(date)
            }
        }
        return result
    }
}

extension ProviderFixture {
    static func nestedDates(_ value: Value) -> Value {
        switch value {
        case .list(let items):
            return .list(items.map(nestedDates))
        case .record(let record):
            var result = record
            for key in record.keys {
                if let inner = record[key] { result[key] = nestedDates(inner) }
            }
            return .record(result)
        case .string(let text):
            return FixtureDate.parse(text).map(Value.date) ?? value
        default:
            return value
        }
    }
}

enum FixtureDate {
    static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
