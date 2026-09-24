import Foundation
import ApolloConfig

public enum ProviderListing {
    public static func lines(schemas: [ProviderSchema], read: (DependencyPath) -> Value) -> [String] {
        schemas.sorted { $0.id < $1.id }.flatMap { schema in
            schema.fields.map { field in
                let name = ([schema.id] + field.path).joined(separator: ".")
                return "\(name) = \(json(read(DependencyPath(schema.id, field.path))))"
            }
        }
    }

    public static func json(_ value: Value) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .number(let number):
            guard number.isFinite else { return "null" }
            if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
            return "\(number)"
        case .string(let text):
            return quote(text)
        case .list(let items):
            return "[" + items.map(json).joined(separator: ",") + "]"
        case .record(let record):
            return "{" + record.keys.map { "\(quote($0)):\(json(record[$0] ?? .null))" }.joined(separator: ",") + "}"
        case .date(let date):
            return quote(date.formatted(.iso8601))
        case .image(let image):
            return "{\"image\":\(quote("\(image.source):\(image.id)"))}"
        }
    }

    static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case let control where control.value < 0x20: result += String(format: "\\u%04x", control.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
