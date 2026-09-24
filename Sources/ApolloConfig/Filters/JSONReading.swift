import Foundation

enum JSONValue {
    static func parse(_ text: String) -> Value? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return value(from: object)
    }

    static func value(from object: Any) -> Value? {
        switch object {
        case is NSNull:
            return .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            return double.isFinite ? .number(double) : nil
        case let text as String:
            return .string(text)
        case let array as [Any]:
            return .list(array.map { value(from: $0) ?? .null })
        case let dictionary as [String: Any]:
            let pairs = dictionary.keys.sorted().map { key in (key, dictionary[key].flatMap { value(from: $0) } ?? .null) }
            return .record(Record(pairs))
        default:
            return nil
        }
    }
}
