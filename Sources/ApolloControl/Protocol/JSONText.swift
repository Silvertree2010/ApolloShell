import Foundation
import ApolloConfig

public enum JSONText {
    public static func encode(_ value: Value) -> String {
        var output = ""
        write(value, into: &output)
        return output
    }

    public static let maxDepth = 256

    public static func decode(_ text: String) -> Value? {
        var parser = JSONParser(Array(text.utf8))
        guard let value = parser.parseValue(depth: 0) else { return nil }
        parser.skipWhitespace()
        return parser.atEnd ? value : nil
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

struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    var atEnd: Bool { index == bytes.count }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
    }

    mutating func parseValue(depth: Int) -> Value? {
        guard depth < JSONText.maxDepth else { return nil }
        skipWhitespace()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: "{"): return parseObject(depth: depth)
        case UInt8(ascii: "["): return parseArray(depth: depth)
        case UInt8(ascii: "\""): return parseString().map(Value.string)
        case UInt8(ascii: "t"): return literal("true", .bool(true))
        case UInt8(ascii: "f"): return literal("false", .bool(false))
        case UInt8(ascii: "n"): return literal("null", .null)
        default: return parseNumber()
        }
    }

    private mutating func literal(_ word: String, _ value: Value) -> Value? {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { return nil }
        index += expected.count
        return value
    }

    private mutating func parseObject(depth: Int) -> Value? {
        index += 1
        var record = Record()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .record(record)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = parseString() else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            guard let value = parseValue(depth: depth + 1) else { return nil }
            record[key] = value
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            guard bytes[index] == UInt8(ascii: "}") else { return nil }
            index += 1
            return .record(record)
        }
    }

    private mutating func parseArray(depth: Int) -> Value? {
        index += 1
        var items: [Value] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .list(items)
        }
        while true {
            guard let value = parseValue(depth: depth + 1) else { return nil }
            items.append(value)
            skipWhitespace()
            guard index < bytes.count else { return nil }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            guard bytes[index] == UInt8(ascii: "]") else { return nil }
            index += 1
            return .list(items)
        }
    }

    private mutating func parseString() -> String? {
        index += 1
        var scalars = String.UnicodeScalarView()
        var raw: [UInt8] = []
        func flush() -> Bool {
            guard !raw.isEmpty else { return true }
            guard let text = String(validating: raw, as: UTF8.self) else { return false }
            scalars.append(contentsOf: text.unicodeScalars)
            raw.removeAll(keepingCapacity: true)
            return true
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                guard flush() else { return nil }
                return String(scalars)
            case UInt8(ascii: "\\"):
                guard flush(), index < bytes.count else { return nil }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{8}")
                case UInt8(ascii: "f"): scalars.append("\u{c}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    guard let scalar = parseUnicodeEscape() else { return nil }
                    scalars.append(scalar)
                default:
                    return nil
                }
            case 0..<0x20:
                return nil
            default:
                raw.append(byte)
            }
        }
        return nil
    }

    private mutating func hex4() -> UInt32? {
        guard index + 4 <= bytes.count, let text = String(bytes: bytes[index..<index + 4], encoding: .ascii),
              let value = UInt32(text, radix: 16) else { return nil }
        index += 4
        return value
    }

    private mutating func parseUnicodeEscape() -> Unicode.Scalar? {
        guard let first = hex4() else { return nil }
        if (0xD800..<0xDC00).contains(first) {
            guard index + 2 <= bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else { return nil }
            index += 2
            guard let second = hex4(), (0xDC00..<0xE000).contains(second) else { return nil }
            return Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
        }
        guard !(0xDC00..<0xE000).contains(first) else { return nil }
        return Unicode.Scalar(first)
    }

    private mutating func parseNumber() -> Value? {
        let start = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { return nil }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, isDigit(bytes[index]) { return nil }
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { return nil }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { return nil }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        guard let text = String(bytes: bytes[start..<index], encoding: .ascii), let number = Double(text) else { return nil }
        return JSONText.finite(number)
    }

    private func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}
