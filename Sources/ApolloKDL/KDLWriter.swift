public enum KDLWriter {
    public static func write(_ node: KDLNode, indent: String, indentUnit: String = "    ") -> String {
        indent + render(node, indent: indent, indentUnit: indentUnit, newline: "\n")
    }

    static func render(_ node: KDLNode, indent: String, indentUnit: String, newline: String) -> String {
        var output = ""
        if let annotation = node.annotation {
            output += "(" + identifier(annotation) + ")"
        }
        output += identifier(node.name)
        for argument in node.arguments {
            output += " " + value(argument)
        }
        for property in node.properties {
            output += " " + identifier(property.name) + "=" + value(property.value)
        }
        if let children = node.children {
            if children.isEmpty {
                output += " {}"
            } else {
                let childIndent = indent + indentUnit
                output += " {" + newline
                for child in children {
                    output += childIndent + render(child, indent: childIndent, indentUnit: indentUnit, newline: newline) + newline
                }
                output += indent + "}"
            }
        }
        return output
    }

    static func identifier(_ text: String) -> String {
        KDLCharacters.isValidBareIdentifier(text) ? text : quoted(text)
    }

    static func value(_ value: KDLValue) -> String {
        var output = ""
        if let annotation = value.annotation {
            output += "(" + identifier(annotation) + ")"
        }
        switch value.scalar {
        case .string(let text):
            output += quoted(text)
        case .number(let number, let raw):
            output += Self.number(number, raw: raw)
        case .bool(let flag):
            output += flag ? "#true" : "#false"
        case .null:
            output += "#null"
        }
        return output
    }

    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            case "\u{08}":
                output += "\\b"
            case "\u{0C}":
                output += "\\f"
            default:
                if KDLCharacters.isNewline(scalar) || KDLCharacters.isDisallowed(scalar) || scalar.value == 0x0B {
                    output += "\\u{" + String(scalar.value, radix: 16) + "}"
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }

    static func number(_ number: Double, raw: String) -> String {
        if !raw.isEmpty, let parsed = KDLNumberLiteral.value(of: raw), parsed == number || (parsed.isNaN && number.isNaN) {
            return raw
        }
        if number.isNaN {
            return "#nan"
        }
        if number == .infinity {
            return "#inf"
        }
        if number == -.infinity {
            return "#-inf"
        }
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int64(number))
        }
        return "\(number)"
    }
}
