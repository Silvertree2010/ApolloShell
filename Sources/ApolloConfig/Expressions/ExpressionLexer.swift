enum ExpressionLexer {
    static let maximumTokens = 512
    static let twoCharacterSymbols: Set<String> = ["||", "&&", "==", "!=", "<=", ">=", "??"]
    static let singleCharacterSymbols: Set<Character> = ["|", "?", ":", "<", ">", "+", "-", "*", "/", "%", "!", "(", ")", "[", "]", ",", "."]

    static func scan(_ characters: [Character]) throws(ExpressionSyntaxError) -> [ExpressionToken] {
        var tokens: [ExpressionToken] = []
        var index = 0
        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
                continue
            }
            guard tokens.count < maximumTokens else {
                throw ExpressionSyntaxError(
                    "expression is too long",
                    help: "use at most \(maximumTokens) tokens; move parts into 'let' or a derived 'var'",
                    start: index,
                    end: characters.count
                )
            }
            let token = try nextToken(characters, at: index)
            tokens.append(token)
            index = token.end
        }
        tokens.append(ExpressionToken(kind: .end, start: characters.count, end: characters.count))
        return tokens
    }

    static func nextToken(_ characters: [Character], at start: Int) throws(ExpressionSyntaxError) -> ExpressionToken {
        let character = characters[start]
        if isNameStart(character) {
            var index = start + 1
            while index < characters.count {
                if isNameCharacter(characters[index]) {
                    index += 1
                } else if characters[index] == "-", index + 1 < characters.count, isNameCharacter(characters[index + 1]) {
                    index += 2
                } else {
                    break
                }
            }
            return ExpressionToken(kind: .name(String(characters[start..<index])), start: start, end: index)
        }
        if isDigit(character) {
            return try number(characters, at: start)
        }
        if character == "'" {
            return try string(characters, at: start)
        }
        if start + 1 < characters.count {
            let pair = String(characters[start...(start + 1)])
            if twoCharacterSymbols.contains(pair) {
                return ExpressionToken(kind: .symbol(pair), start: start, end: start + 2)
            }
        }
        if singleCharacterSymbols.contains(character) {
            return ExpressionToken(kind: .symbol(String(character)), start: start, end: start + 1)
        }
        throw unexpected(character, at: start)
    }

    static func number(_ characters: [Character], at start: Int) throws(ExpressionSyntaxError) -> ExpressionToken {
        var index = start
        while index < characters.count, isDigit(characters[index]) {
            index += 1
        }
        if index + 1 < characters.count, characters[index] == ".", isDigit(characters[index + 1]) {
            index += 1
            while index < characters.count, isDigit(characters[index]) {
                index += 1
            }
        }
        guard let value = Double(String(characters[start..<index])), value.isFinite else {
            throw ExpressionSyntaxError("number is too large", start: start, end: index)
        }
        return ExpressionToken(kind: .number(value), start: start, end: index)
    }

    static func string(_ characters: [Character], at start: Int) throws(ExpressionSyntaxError) -> ExpressionToken {
        var index = start + 1
        var text = ""
        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                return ExpressionToken(kind: .string(text), start: start, end: index + 1)
            }
            if character == "\\" {
                guard index + 1 < characters.count else { break }
                let escaped = characters[index + 1]
                guard escaped == "'" || escaped == "\\" else {
                    throw ExpressionSyntaxError(
                        "invalid escape '\\\(escaped)' in string",
                        help: "only \\' and \\\\ are escapes in expression strings",
                        start: index,
                        end: index + 2
                    )
                }
                text.append(escaped)
                index += 2
            } else {
                text.append(character)
                index += 1
            }
        }
        throw ExpressionSyntaxError("unterminated string", help: "close the string with a single quote", start: start, end: characters.count)
    }

    static func unexpected(_ character: Character, at start: Int) -> ExpressionSyntaxError {
        let end = start + 1
        switch character {
        case "=":
            return ExpressionSyntaxError("unexpected '='", help: "use '==' to compare values", start: start, end: end)
        case "&":
            return ExpressionSyntaxError("unexpected '&'", help: "use '&&' for 'and'", start: start, end: end)
        case "\"":
            return ExpressionSyntaxError("strings in expressions use single quotes", help: "write 'text' instead of \"text\"", start: start, end: end)
        case "{", "}":
            return ExpressionSyntaxError(
                "unexpected '\(character)'",
                help: "expressions cannot contain braces; write '{{' or '}}' outside an expression for a literal brace",
                start: start,
                end: end
            )
        default:
            let help: String? = character.isASCII && character.isUppercase ? "names are lowercase kebab-case" : nil
            return ExpressionSyntaxError("unexpected character '\(character)'", help: help, start: start, end: end)
        }
    }

    static func isNameStart(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && character >= "a" && character <= "z")
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        isNameStart(character) || isDigit(character)
    }

    static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character >= "0" && character <= "9"
    }
}
