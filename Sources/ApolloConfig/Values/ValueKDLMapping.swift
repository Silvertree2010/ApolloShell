import Foundation
import ApolloKDL

public enum ValueKDLMapping {
    public static func value(from node: KDLNode) -> Value {
        nodeValue(node)
    }

    public static func node(named name: String, value: Value) -> KDLNode {
        kdlNode(named: name, for: value)
    }

    static func nodeValue(_ node: KDLNode) -> Value {
        if let children = node.children, !children.isEmpty, children.allSatisfy({ $0.name == "-" }) {
            return .list(children.map { nodeValue($0) })
        }
        if node.arguments.count == 1, node.properties.isEmpty, (node.children?.isEmpty ?? true) {
            return scalarValue(node.arguments[0].scalar)
        }
        var record = Record()
        for property in node.properties {
            record[property.name] = scalarValue(property.value.scalar)
        }
        for child in node.children ?? [] where child.name != "-" {
            record[child.name] = nodeValue(child)
        }
        return .record(record)
    }

    static func scalarValue(_ scalar: KDLScalar) -> Value {
        switch scalar {
        case .string(let text):
            return .string(text)
        case .number(let number, _):
            return number.isFinite ? .number(number) : .null
        case .bool(let flag):
            return .bool(flag)
        case .null:
            return .null
        }
    }

    static func kdlNode(named name: String, for value: Value) -> KDLNode {
        switch value {
        case .list(let items):
            return KDLNode(name: name, children: items.map { kdlNode(named: "-", for: $0) })
        case .record(let record):
            var properties: [KDLProperty] = []
            var children: [KDLNode] = []
            for key in record.keys {
                guard let field = record[key] else { continue }
                switch field {
                case .list, .record:
                    children.append(kdlNode(named: key, for: field))
                default:
                    properties.append(KDLProperty(name: key, value: scalarKDLValue(field)))
                }
            }
            return KDLNode(name: name, properties: properties, children: children.isEmpty ? nil : children)
        default:
            return KDLNode(name: name, arguments: [scalarKDLValue(value)])
        }
    }

    static func scalarKDLValue(_ value: Value) -> KDLValue {
        switch value {
        case .null:
            return KDLValue(.null)
        case .bool(let flag):
            return KDLValue(.bool(flag))
        case .number(let number):
            guard number.isFinite else { return KDLValue(.null) }
            return KDLValue(.number(number, raw: NumberText.plain(number)))
        case .string(let text):
            return KDLValue(.string(text))
        case .date(let date):
            return KDLValue(.string(date.formatted(.iso8601)))
        case .image, .list, .record:
            return KDLValue(.null)
        }
    }
}
