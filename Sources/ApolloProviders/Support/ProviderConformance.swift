import ApolloConfig

public enum ProviderConformance {
    public static func problems(schema: ProviderSchema, root: Value, strictNullability: Bool) -> [String] {
        schema.fields.compactMap { field in
            problem(field: field, root: root, strictNullability: strictNullability, provider: schema.id)
        }
    }

    public static func problem(field: FieldSchema, root: Value, strictNullability: Bool, provider: String) -> String? {
        let name = ([provider] + field.path).joined(separator: ".")
        guard let value = lookup(root, field.path) else { return "\(name) is missing" }
        if value == .null {
            return field.nullable || !strictNullability ? nil : "\(name) is null but not nullable"
        }
        return matches(value, field.type) ? nil : "\(name) has type \(value.typeName), expected \(field.type)"
    }

    public static func lookup(_ value: Value, _ path: [String]) -> Value? {
        guard let first = path.first else { return value }
        guard case .record(let record) = value, let next = record[first] else { return nil }
        return lookup(next, Array(path.dropFirst()))
    }

    public static func matches(_ value: Value, _ type: ValueType) -> Bool {
        switch (type, value) {
        case (.any, _), (.value, _): true
        case (.number, .number), (.duration, .number): true
        case (.bool, .bool): true
        case (.string, .string), (.identifier, .string), (.path, .string), (.keyChord, .string): true
        case (.list, .list): true
        case (.record, .record): true
        case (.enumeration(let cases), .string(let text)): cases.contains(text)
        default: false
        }
    }
}
