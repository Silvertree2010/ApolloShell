import ApolloBase

enum CSSTokenKind: Sendable, Hashable {
    case ident(String)
    case function(String)
    case atKeyword(String)
    case hash(String)
    case string(String)
    case url(String)
    case badString
    case badURL
    case number(Double)
    case percentage(Double)
    case dimension(Double, String)
    case whitespace
    case colon
    case semicolon
    case comma
    case openParen
    case closeParen
    case openBracket
    case closeBracket
    case openBrace
    case closeBrace
    case delim(Character)
}

struct CSSToken: Sendable, Hashable {
    var kind: CSSTokenKind
    var text: String
    var start: SourcePosition
    var end: SourcePosition
}

struct CSSTokenizerProblem: Sendable, Hashable {
    var message: String
    var position: SourcePosition
}

struct CSSTokenizer {
    private let chars: [Character]
    private var index = 0
    private var line = 1
    private var column = 1
    private var offset = 0
    private(set) var problems: [CSSTokenizerProblem] = []

    init(_ text: String) {
        chars = Array(text)
    }

    static func tokenize(_ text: String) -> (tokens: [CSSToken], problems: [CSSTokenizerProblem]) {
        var tokenizer = CSSTokenizer(text)
        var tokens: [CSSToken] = []
        while let token = tokenizer.next() { tokens.append(token) }
        return (tokens, tokenizer.problems)
    }

    private var position: SourcePosition { SourcePosition(offset: offset, line: line, column: column) }

    private func peek(_ distance: Int = 0) -> Character? {
        let target = index + distance
        return target < chars.count ? chars[target] : nil
    }

    private mutating func advance() {
        let character = chars[index]
        index += 1
        offset += character.utf8.count
        if character.isNewline {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    mutating func next() -> CSSToken? {
        guard let character = peek() else { return nil }
        let start = position
        let startIndex = index
        let kind = consume(character, start: start)
        return CSSToken(kind: kind, text: String(chars[startIndex..<index]), start: start, end: position)
    }

    private mutating func consume(_ character: Character, start: SourcePosition) -> CSSTokenKind {
        if character == "/", peek(1) == "*" {
            consumeComment(start: start)
            return .whitespace
        }
        if character.isWhitespace {
            while let next = peek(), next.isWhitespace { advance() }
            return .whitespace
        }
        if character == "\"" || character == "'" { return consumeString(quote: character, start: start) }
        switch character {
        case "(": advance(); return .openParen
        case ")": advance(); return .closeParen
        case "[": advance(); return .openBracket
        case "]": advance(); return .closeBracket
        case "{": advance(); return .openBrace
        case "}": advance(); return .closeBrace
        case ":": advance(); return .colon
        case ";": advance(); return .semicolon
        case ",": advance(); return .comma
        default: break
        }
        if character == "#" {
            if let next = peek(1), isNameCharacter(next) || startsEscape(1) {
                advance()
                return .hash(consumeName())
            }
            advance()
            return .delim("#")
        }
        if character == "+" || character == "." {
            if startsNumber(0) { return consumeNumeric() }
            advance()
            return .delim(character)
        }
        if character == "-" {
            if startsNumber(0) { return consumeNumeric() }
            if startsIdentifier(0) { return consumeIdentLike() }
            advance()
            return .delim("-")
        }
        if character == "@" {
            if startsIdentifier(1) {
                advance()
                return .atKeyword(consumeName())
            }
            advance()
            return .delim("@")
        }
        if character == "\\" {
            if startsEscape(0) { return consumeIdentLike() }
            advance()
            return .delim("\\")
        }
        if isDigit(character) { return consumeNumeric() }
        if isNameStart(character) { return consumeIdentLike() }
        advance()
        return .delim(character)
    }

    private func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    private func isNameStart(_ character: Character) -> Bool {
        character == "_" || !character.isASCII || ("a"..."z").contains(character) || ("A"..."Z").contains(character)
    }

    private func isNameCharacter(_ character: Character) -> Bool {
        isNameStart(character) || isDigit(character) || character == "-"
    }

    private func startsEscape(_ distance: Int) -> Bool {
        guard peek(distance) == "\\", let next = peek(distance + 1) else { return false }
        return !next.isNewline
    }

    private func startsIdentifier(_ distance: Int) -> Bool {
        guard let first = peek(distance) else { return false }
        if first == "-" {
            guard let second = peek(distance + 1) else { return false }
            return second == "-" || isNameStart(second) || startsEscape(distance + 1)
        }
        if first == "\\" { return startsEscape(distance) }
        return isNameStart(first)
    }

    private func startsNumber(_ distance: Int) -> Bool {
        guard let first = peek(distance) else { return false }
        if first == "+" || first == "-" {
            guard let second = peek(distance + 1) else { return false }
            if isDigit(second) { return true }
            return second == "." && peek(distance + 2).map(isDigit) == true
        }
        if first == "." { return peek(distance + 1).map(isDigit) == true }
        return isDigit(first)
    }

    private mutating func consumeNumeric() -> CSSTokenKind {
        var representation = ""
        if let sign = peek(), sign == "+" || sign == "-" {
            representation.append(sign)
            advance()
        }
        while let digit = peek(), isDigit(digit) {
            representation.append(digit)
            advance()
        }
        if peek() == ".", let next = peek(1), isDigit(next) {
            representation.append(".")
            advance()
            while let digit = peek(), isDigit(digit) {
                representation.append(digit)
                advance()
            }
        }
        if let marker = peek(), marker == "e" || marker == "E" {
            if let next = peek(1), isDigit(next) {
                representation.append("e")
                advance()
                while let digit = peek(), isDigit(digit) {
                    representation.append(digit)
                    advance()
                }
            } else if let sign = peek(1), sign == "+" || sign == "-", let next = peek(2), isDigit(next) {
                representation.append("e")
                representation.append(sign)
                advance()
                advance()
                while let digit = peek(), isDigit(digit) {
                    representation.append(digit)
                    advance()
                }
            }
        }
        var value = Double(representation) ?? 0
        if !value.isFinite {
            problems.append(CSSTokenizerProblem(message: "number out of range", position: position))
            value = 0
        }
        if startsIdentifier(0) { return .dimension(value, consumeName().lowercased()) }
        if peek() == "%" {
            advance()
            return .percentage(value)
        }
        return .number(value)
    }

    private mutating func consumeName() -> String {
        var name = ""
        while let character = peek() {
            if isNameCharacter(character) {
                name.append(character)
                advance()
            } else if startsEscape(0) {
                name.append(consumeEscape())
            } else {
                break
            }
        }
        return name
    }

    private mutating func consumeEscape() -> Character {
        advance()
        var hex = ""
        while hex.count < 6, let character = peek(), character.isHexDigit {
            hex.append(character)
            advance()
        }
        if hex.isEmpty {
            let character = chars[index]
            advance()
            return character
        }
        if let character = peek(), character.isWhitespace { advance() }
        guard let code = UInt32(hex, radix: 16), code != 0, let scalar = Unicode.Scalar(code) else { return "\u{FFFD}" }
        return Character(scalar)
    }

    private mutating func consumeIdentLike() -> CSSTokenKind {
        let name = consumeName()
        guard peek() == "(" else { return .ident(name) }
        advance()
        if name.lowercased() == "url" {
            var look = 0
            while let character = peek(look), character.isWhitespace { look += 1 }
            if let character = peek(look), character == "\"" || character == "'" { return .function(name) }
            return consumeURL()
        }
        return .function(name)
    }

    private mutating func consumeURL() -> CSSTokenKind {
        let start = position
        while let character = peek(), character.isWhitespace { advance() }
        var value = ""
        while let character = peek() {
            if character == ")" {
                advance()
                return .url(value)
            }
            if character.isWhitespace {
                while let space = peek(), space.isWhitespace { advance() }
                if peek() == ")" {
                    advance()
                    return .url(value)
                }
                if peek() == nil { break }
                skipBadURL()
                return .badURL
            }
            if character == "\"" || character == "'" || character == "(" {
                skipBadURL()
                return .badURL
            }
            if character == "\\" {
                if startsEscape(0) {
                    value.append(consumeEscape())
                    continue
                }
                skipBadURL()
                return .badURL
            }
            value.append(character)
            advance()
        }
        problems.append(CSSTokenizerProblem(message: "unterminated url()", position: start))
        return .url(value)
    }

    private mutating func skipBadURL() {
        while let character = peek() {
            advance()
            if character == ")" { return }
        }
    }

    private mutating func consumeString(quote: Character, start: SourcePosition) -> CSSTokenKind {
        advance()
        var value = ""
        while let character = peek() {
            if character == quote {
                advance()
                return .string(value)
            }
            if character.isNewline {
                problems.append(CSSTokenizerProblem(message: "unterminated string", position: start))
                return .badString
            }
            if character == "\\" {
                guard let next = peek(1) else {
                    advance()
                    break
                }
                if next.isNewline {
                    advance()
                    advance()
                    continue
                }
                value.append(consumeEscape())
                continue
            }
            value.append(character)
            advance()
        }
        problems.append(CSSTokenizerProblem(message: "unterminated string", position: start))
        return .string(value)
    }

    private mutating func consumeComment(start: SourcePosition) {
        advance()
        advance()
        while let character = peek() {
            if character == "*", peek(1) == "/" {
                advance()
                advance()
                return
            }
            advance()
        }
        problems.append(CSSTokenizerProblem(message: "unterminated comment", position: start))
    }
}
