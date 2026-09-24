import ApolloBase
import ApolloKDL

enum ValueTemplateKDLMapping {
    static func template(from node: KDLNode, locals: Set<String>) -> Result<ValueTemplate, Diagnostic> {
        if let children = node.children, !children.isEmpty, children.allSatisfy({ $0.name == "-" }) {
            var items: [ValueTemplate] = []
            for child in children {
                switch template(from: child, locals: locals) {
                case .failure(let diagnostic):
                    return .failure(diagnostic)
                case .success(let item):
                    items.append(item)
                }
            }
            return .success(.list(items))
        }
        if node.arguments.count == 1, node.properties.isEmpty, (node.children?.isEmpty ?? true) {
            switch scalarTemplate(node.arguments[0], locals: locals) {
            case .failure(let diagnostic):
                return .failure(diagnostic)
            case .success(let compiled):
                return .success(.scalar(compiled))
            }
        }
        var fields: [ValueTemplateField] = []
        for property in node.properties {
            switch scalarTemplate(property.value, locals: locals) {
            case .failure(let diagnostic):
                return .failure(diagnostic)
            case .success(let compiled):
                fields.append(ValueTemplateField(name: property.name, value: .scalar(compiled)))
            }
        }
        for child in node.children ?? [] where child.name != "-" {
            switch template(from: child, locals: locals) {
            case .failure(let diagnostic):
                return .failure(diagnostic)
            case .success(let value):
                fields.append(ValueTemplateField(name: child.name, value: value))
            }
        }
        return .success(.record(fields))
    }

    static func scalarTemplate(_ kdlValue: KDLValue, locals: Set<String>) -> Result<CompiledValue, Diagnostic> {
        switch kdlValue.scalar {
        case .string(let text):
            return CompiledValueBuilder.compile(text, span: kdlValue.span, locals: locals)
        case .number(let number, _):
            return .success(CompiledValueBuilder.literal(number.isFinite ? .number(number) : .null, span: kdlValue.span))
        case .bool(let flag):
            return .success(CompiledValueBuilder.literal(.bool(flag), span: kdlValue.span))
        case .null:
            return .success(CompiledValueBuilder.literal(.null, span: kdlValue.span))
        }
    }
}
