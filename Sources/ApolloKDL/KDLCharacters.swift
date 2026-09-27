enum KDLCharacters {
    enum BareWord: Equatable {
        case identifier
        case number
        case invalid(String)
    }

    static func isNewline(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0C, 0x0D, 0x85, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }

    static func isUnicodeSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0B, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0E...0x1F, 0x7F, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF:
            return true
        default:
            return false
        }
    }

    static func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
        if isUnicodeSpace(scalar) || isNewline(scalar) || isDisallowed(scalar) {
            return false
        }
        switch scalar {
        case "\\", "/", "(", ")", "{", "}", ";", "[", "]", "\"", "#", "=":
            return false
        default:
            return true
        }
    }

    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    static func classify(_ word: String) -> BareWord {
        var scalars = word.unicodeScalars.makeIterator()
        guard let first = scalars.next() else {
            return .invalid("expected a value")
        }
        let second = scalars.next()
        let third = scalars.next()
        let signed = first == "+" || first == "-"
        if isDigit(first) || (signed && second.map(isDigit) == true) {
            return .number
        }
        let dotDigit = first == "." && second.map(isDigit) == true
        let signedDotDigit = signed && second == "." && third.map(isDigit) == true
        if dotDigit || signedDotDigit {
            return .invalid("'\(word)' is not a valid number: numbers need a digit before the decimal point, like 0.5")
        }
        switch word {
        case "true", "false", "null":
            return .invalid("'\(word)' is not a valid identifier in KDL v2: write #\(word) for the value or \"\(word)\" for the string (ApolloShell reads KDL v2)")
        case "inf", "-inf", "nan":
            return .invalid("'\(word)' is reserved: write #\(word) for the number or \"\(word)\" for the string")
        default:
            return .identifier
        }
    }

    static func isValidBareIdentifier(_ text: String) -> Bool {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy(isIdentifierCharacter) else {
            return false
        }
        return classify(text) == .identifier
    }
}
