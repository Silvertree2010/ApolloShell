struct KDLStringScanner {
    enum Piece {
        case literal(Unicode.Scalar)
        case escaped(Unicode.Scalar)
    }

    let source: KDLSource
    var index: Int

    static func isRawStart(_ source: KDLSource, at offset: Int) -> Bool {
        var cursor = offset
        guard source.byte(at: cursor) == UInt8(ascii: "#") else { return false }
        while source.byte(at: cursor) == UInt8(ascii: "#") {
            cursor += 1
        }
        return source.byte(at: cursor) == UInt8(ascii: "\"")
    }

    mutating func scanQuoted() throws(KDLSyntaxError) -> String {
        if source.hasPrefix("\"\"\"", at: index) {
            return try scanMultiLine(open: index, hashes: 0)
        }
        return try scanSingleLine()
    }

    mutating func scanRaw() throws(KDLSyntaxError) -> String {
        let open = index
        var hashes = 0
        while source.byte(at: index) == UInt8(ascii: "#") {
            hashes += 1
            index += 1
        }
        if source.hasPrefix("\"\"\"", at: index) {
            return try scanMultiLine(open: open, hashes: hashes)
        }
        index += 1
        var result = String.UnicodeScalarView()
        while true {
            guard let decoded = source.decoded(at: index) else {
                throw KDLSyntaxError(message: "this raw string is never closed", start: open, end: open + hashes + 1)
            }
            if decoded.scalar == "\"", closes(at: index + 1, hashes: hashes) {
                index += 1 + hashes
                return String(result)
            }
            if KDLCharacters.isNewline(decoded.scalar) {
                throw KDLSyntaxError(message: "a raw string cannot contain a line break; use a multi-line raw string #\"\"\" … \"\"\"#", start: index, end: index + decoded.length)
            }
            result.append(decoded.scalar)
            index += decoded.length
        }
    }

    func closes(at offset: Int, hashes: Int) -> Bool {
        for step in 0..<hashes where source.byte(at: offset + step) != UInt8(ascii: "#") {
            return false
        }
        return true
    }

    mutating func scanSingleLine() throws(KDLSyntaxError) -> String {
        let open = index
        index += 1
        var result = String.UnicodeScalarView()
        while true {
            guard let decoded = source.decoded(at: index) else {
                throw KDLSyntaxError(message: "this string is never closed", start: open, end: open + 1)
            }
            if decoded.scalar == "\"" {
                index += 1
                return String(result)
            }
            if KDLCharacters.isNewline(decoded.scalar) {
                throw KDLSyntaxError(message: "a quoted string cannot contain a line break; write \\n or use a multi-line string \"\"\"", start: index, end: index + decoded.length)
            }
            if decoded.scalar == "\\" {
                if let escaped = try scanEscape() {
                    result.append(escaped)
                }
                continue
            }
            result.append(decoded.scalar)
            index += decoded.length
        }
    }

    mutating func scanEscape() throws(KDLSyntaxError) -> Unicode.Scalar? {
        let start = index
        index += 1
        guard let decoded = source.decoded(at: index) else {
            throw KDLSyntaxError(message: "the file ends inside an escape", start: start, end: start + 1)
        }
        if KDLCharacters.isUnicodeSpace(decoded.scalar) || KDLCharacters.isNewline(decoded.scalar) {
            skipEscapedWhitespace()
            return nil
        }
        index += decoded.length
        switch decoded.scalar {
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        case "\\":
            return "\\"
        case "\"":
            return "\""
        case "b":
            return "\u{08}"
        case "f":
            return "\u{0C}"
        case "s":
            return " "
        case "u":
            return try scanUnicodeEscape(start: start)
        default:
            throw KDLSyntaxError(message: "'\\\(Character(decoded.scalar))' is not a valid escape", start: start, end: index)
        }
    }

    mutating func skipEscapedWhitespace() {
        while let decoded = source.decoded(at: index),
              KDLCharacters.isUnicodeSpace(decoded.scalar) || KDLCharacters.isNewline(decoded.scalar) {
            index += decoded.length
        }
    }

    mutating func scanUnicodeEscape(start: Int) throws(KDLSyntaxError) -> Unicode.Scalar {
        let invalid = KDLSyntaxError(message: "a unicode escape is written \\u{…} with 1 to 6 hex digits", start: start, end: index)
        guard source.byte(at: index) == UInt8(ascii: "{") else { throw invalid }
        index += 1
        var value: UInt32 = 0
        var digits = 0
        while let byte = source.byte(at: index), let digit = Self.hexValue(byte) {
            guard digits < 6 else { throw invalid }
            value = value * 16 + UInt32(digit)
            digits += 1
            index += 1
        }
        guard digits > 0, source.byte(at: index) == UInt8(ascii: "}") else { throw invalid }
        index += 1
        guard let scalar = Unicode.Scalar(value) else {
            throw KDLSyntaxError(message: "U+\(String(value, radix: 16, uppercase: true)) is not a Unicode scalar value", start: start, end: index)
        }
        return scalar
    }

    static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return Int(byte - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return Int(byte - UInt8(ascii: "A")) + 10
        default:
            return nil
        }
    }

    mutating func scanMultiLine(open: Int, hashes: Int) throws(KDLSyntaxError) -> String {
        index += 3
        guard let firstBreak = source.newlineLength(at: index) else {
            throw KDLSyntaxError(message: "a multi-line string needs a line break right after the opening \"\"\"", start: open, end: index)
        }
        index += firstBreak
        var lines: [[Piece]] = [[]]
        var lineOffsets = [index]
        while true {
            guard let decoded = source.decoded(at: index) else {
                throw KDLSyntaxError(message: "this multi-line string is never closed", start: open, end: open + hashes + 3)
            }
            if decoded.scalar == "\"", source.hasPrefix("\"\"\"", at: index), closes(at: index + 3, hashes: hashes) {
                let closing = index
                index += 3 + hashes
                return try dedent(lines, lineOffsets: lineOffsets, closing: closing)
            }
            if let length = source.newlineLength(at: index) {
                index += length
                lines.append([])
                lineOffsets.append(index)
                continue
            }
            if hashes == 0, decoded.scalar == "\\" {
                if let escaped = try scanEscape() {
                    lines[lines.count - 1].append(.escaped(escaped))
                }
                continue
            }
            lines[lines.count - 1].append(.literal(decoded.scalar))
            index += decoded.length
        }
    }

    func dedent(_ lines: [[Piece]], lineOffsets: [Int], closing: Int) throws(KDLSyntaxError) -> String {
        var prefix: [Unicode.Scalar] = []
        for piece in lines[lines.count - 1] {
            guard case .literal(let scalar) = piece, KDLCharacters.isUnicodeSpace(scalar) else {
                throw KDLSyntaxError(message: "the closing \"\"\" of a multi-line string must stand on its own line, after whitespace only", start: lineOffsets[lines.count - 1], end: closing + 3)
            }
            prefix.append(scalar)
        }
        var output = String.UnicodeScalarView()
        for lineIndex in 0..<(lines.count - 1) {
            let line = lines[lineIndex]
            if lineIndex > 0 {
                output.append("\n")
            }
            if line.allSatisfy(Self.isLiteralSpace) {
                continue
            }
            guard line.count >= prefix.count, zip(line, prefix).allSatisfy({ Self.matches($0.0, $0.1) }) else {
                throw KDLSyntaxError(message: "every line of a multi-line string must start with the same whitespace as the line of the closing \"\"\"", start: lineOffsets[lineIndex], end: lineOffsets[lineIndex] + 1)
            }
            for piece in line.dropFirst(prefix.count) {
                switch piece {
                case .literal(let scalar), .escaped(let scalar):
                    output.append(scalar)
                }
            }
        }
        return String(output)
    }

    static func isLiteralSpace(_ piece: Piece) -> Bool {
        if case .literal(let scalar) = piece {
            return KDLCharacters.isUnicodeSpace(scalar)
        }
        return false
    }

    static func matches(_ piece: Piece, _ expected: Unicode.Scalar) -> Bool {
        if case .literal(let scalar) = piece {
            return scalar == expected
        }
        return false
    }
}
