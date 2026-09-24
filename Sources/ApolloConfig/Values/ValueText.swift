import Foundation

extension Value {
    var stringified: String {
        switch self {
        case .null, .image: ""
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): NumberText.plain(number)
        case .string(let text): text
        case .list, .record: jsonText
        case .date(let date): date.formatted(.iso8601)
        }
    }

    var jsonText: String {
        switch self {
        case .null, .image: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): NumberText.plain(number)
        case .string(let text): JSONText.quoted(text)
        case .date(let date): JSONText.quoted(date.formatted(.iso8601))
        case .list(let items): "[" + items.map(\.jsonText).joined(separator: ",") + "]"
        case .record(let record):
            "{" + record.keys.map { key in JSONText.quoted(key) + ":" + (record[key] ?? .null).jsonText }.joined(separator: ",") + "}"
        }
    }
}

enum JSONText {
    static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
