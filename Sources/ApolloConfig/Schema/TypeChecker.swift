import ApolloKDL

enum TypeChecker {
    static func literalMatches(_ value: KDLValue, _ type: ValueType) -> Bool {
        if case .null = value.scalar { return true }
        switch type {
        case .any, .value:
            return true
        case .string, .path, .identifier:
            if case .string = value.scalar { return true }
            return false
        case .keyChord:
            if case .string(let text) = value.scalar { return KeyChord.parse(text) != nil }
            return false
        case .number:
            if case .number = value.scalar { return true }
            return false
        case .bool:
            if case .bool = value.scalar { return true }
            return false
        case .duration:
            if case .string(let text) = value.scalar { return isDuration(text) }
            return false
        case .actions, .list, .record:
            return false
        case .enumeration(let cases):
            if case .string(let text) = value.scalar { return cases.contains(text) }
            return false
        case .oneOf(let types):
            return types.contains { literalMatches(value, $0) }
        }
    }

    static func typeName(_ type: ValueType) -> String {
        switch type {
        case .any: return "any"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .duration: return "duration"
        case .keyChord: return "key-chord"
        case .path: return "path"
        case .identifier: return "id"
        case .value: return "value"
        case .actions: return "actions"
        case .list: return "list"
        case .record: return "record"
        case .enumeration(let cases): return cases.map { "\"\($0)\"" }.joined(separator: " | ")
        case .oneOf(let types): return types.map(typeName).joined(separator: " | ")
        }
    }

    private static func isDuration(_ text: String) -> Bool {
        guard text.contains("{") else {
            let digits = text.prefix { $0.isNumber }
            guard !digits.isEmpty else { return false }
            let suffix = text.dropFirst(digits.count)
            return ["ms", "s", "m", "h"].contains(String(suffix))
        }
        return true
    }
}
