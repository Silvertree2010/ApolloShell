import Foundation
import ApolloConfig

public enum JSONText {
    public static func encode(_ value: Value) -> String {
        var output = ""
        write(value, into: &output)
        return output
    }

    public static func decode(_ text: String) -> Value? {
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
            return finite(number.doubleValue)
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

    public static func finite(_ number: Double) -> Value {
        number.isFinite ? .number(number) : .null
    }

    static func write(_ value: Value, into output: inout String) {
        switch value {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .number(let number):
            output += numberText(number)
        case .string(let text):
            writeString(text, into: &output)
        case .list(let items):
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 { output += "," }
                write(item, into: &output)
            }
            output += "]"
        case .record(let record):
            writeObject(record.keys.map { ($0, record[$0] ?? .null) }, into: &output)
        case .date(let date):
            writeString(dateText(date), into: &output)
        case .image(let image):
            writeObject([("source", .string(image.source)), ("id", .string(image.id))], into: &output)
        }
    }

    static func writeObject(_ pairs: [(String, Value)], into output: inout String) {
        output += "{"
        for (index, pair) in pairs.enumerated() {
            if index > 0 { output += "," }
            writeString(pair.0, into: &output)
            output += ":"
            write(pair.1, into: &output)
        }
        output += "}"
    }

    static func numberText(_ number: Double) -> String {
        guard number.isFinite else { return "null" }
        if number == number.rounded(), abs(number) < 9_007_199_254_740_992 {
            return String(Int64(number))
        }
        return "\(number)"
    }

    static func dateText(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!))
    }

    static func writeString(_ text: String, into output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case _ where scalar.value < 0x20:
                output += String(format: "\\u%04x", scalar.value)
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }
}
