import ApolloBase
import ApolloKDL

struct VarStageResult: Sendable {
    var declarations: [VarDecl]
    var diagnostics: [Diagnostic]
}

enum VarStage {
    static let controlProperties: Set<String> = ["type", "persist", "from"]

    static func run(_ nodes: [ExpandedNode], registry: SchemaRegistry) -> VarStageResult {
        var declarations: [VarDecl] = []
        var diagnostics: [Diagnostic] = []
        for node in nodes where node.kdl.name == "var" {
            if let decl = declaration(for: node, diagnostics: &diagnostics) {
                declarations.append(decl)
            }
        }
        return VarStageResult(declarations: declarations, diagnostics: diagnostics)
    }

    static func declaration(for node: ExpandedNode, diagnostics: inout [Diagnostic]) -> VarDecl? {
        let kdl = node.kdl
        guard let first = kdl.arguments.first, case .string(let name) = first.scalar else {
            diagnostics.append(Diagnostic(.error, "'var' needs a name", span: kdl.span, code: .varSyntax))
            return nil
        }
        let persist = boolProperty(kdl, "persist") ?? false
        let fromProperty = kdl.property("from")
        var derived: CompiledValue?
        if let fromProperty {
            switch ValueTemplateKDLMapping.scalarTemplate(fromProperty.value, locals: []) {
            case .failure(let diagnostic):
                diagnostics.append(diagnostic)
            case .success(let compiled):
                derived = compiled
            }
        }
        if derived != nil, persist {
            diagnostics.append(Diagnostic(.error, "a derived 'var' (with 'from=') cannot persist", span: kdl.span, code: .derivedPersist))
        }
        var defaultValue: ValueTemplate
        if derived != nil {
            defaultValue = .scalar(CompiledValueBuilder.literal(.null, span: kdl.span))
        } else {
            let dataProperties = kdl.properties.filter { !controlProperties.contains($0.name) }
            let valueNode = KDLNode(
                name: kdl.name,
                arguments: kdl.arguments.count > 1 ? [kdl.arguments[1]] : [],
                properties: dataProperties,
                children: node.children.isEmpty ? nil : node.children.map { $0.reattachingChildren() }
            )
            switch ValueTemplateKDLMapping.template(from: valueNode, locals: []) {
            case .failure(let diagnostic):
                diagnostics.append(diagnostic)
                defaultValue = .scalar(CompiledValueBuilder.literal(.null, span: kdl.span))
            case .success(let template):
                defaultValue = template
            }
        }
        let type: ValueType
        if let typeProperty = kdl.property("type") {
            if case .string(let text) = typeProperty.value.scalar, let parsed = parseType(text) {
                type = parsed
            } else {
                diagnostics.append(Diagnostic(.error, "'type=' must be one of string, number, bool, list, record, any", span: typeProperty.span, code: .unknownType))
                type = .any
            }
        } else {
            type = inferredType(from: defaultValue)
        }
        if type == .list, case .record(let fields) = defaultValue, fields.isEmpty {
            defaultValue = .list([])
        }
        return VarDecl(name: name, type: type, defaultValue: defaultValue, persist: persist, derived: derived, span: kdl.span)
    }

    private static func inferredType(from defaultValue: ValueTemplate) -> ValueType {
        switch defaultValue {
        case .list:
            return .list
        case .record:
            return .record
        case .scalar(let compiled):
            guard compiled.isConstant else { return .any }
            switch compiled.template {
            case .literal:
                return .string
            case .whole(.literal(let value)):
                return valueType(value)
            default:
                return .any
            }
        }
    }

    private static func valueType(_ value: Value) -> ValueType {
        switch value {
        case .null: return .any
        case .bool: return .bool
        case .number: return .number
        case .string: return .string
        case .list: return .list
        case .record: return .record
        case .date, .image: return .any
        }
    }

    private static func parseType(_ text: String) -> ValueType? {
        switch text {
        case "string": return .string
        case "number": return .number
        case "bool": return .bool
        case "list": return .list
        case "record": return .record
        case "any": return .any
        default: return nil
        }
    }

    private static func boolProperty(_ node: KDLNode, _ name: String) -> Bool? {
        guard let property = node.property(name), case .bool(let value) = property.value.scalar else { return nil }
        return value
    }
}
