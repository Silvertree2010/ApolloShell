import ApolloBase

extension ExpressionParser {
    public static func parseTemplate(_ text: String, span: SourceSpan) -> Result<StringTemplate, Diagnostic> {
        guard text.utf8.contains(UInt8(ascii: "{")) else { return .success(.literal(text)) }
        let characters = Array(text)
        let mapper = ExpressionSpanMapper(base: span, characters: characters, origin: 0)
        var parts: [TemplatePart] = []
        var buffer = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "{", next == "{" {
                buffer.append("{")
                index += 2
            } else if character == "}", next == "}" {
                buffer.append("}")
                index += 2
            } else if character == "}" {
                return .failure(Diagnostic(
                    .error,
                    "unmatched '}'",
                    span: mapper.span(from: index, to: index + 1),
                    help: "write '}}' for a literal brace"
                ))
            } else if character == "{" {
                let close: Int
                switch closingBrace(characters, openingAt: index) {
                case .failure(let error):
                    return .failure(mapper.diagnostic(for: error))
                case .success(let position):
                    close = position
                }
                let inner = Array(characters[(index + 1)..<close])
                guard inner.contains(where: { !$0.isWhitespace }) else {
                    return .failure(Diagnostic(
                        .error,
                        "empty expression",
                        span: mapper.span(from: index, to: close + 1),
                        help: "write '{{}}' for literal braces"
                    ))
                }
                switch parse(inner, mapper: mapper.shifted(to: index + 1)) {
                case .failure(let diagnostic):
                    return .failure(diagnostic)
                case .success(let expr):
                    if !buffer.isEmpty {
                        parts.append(.text(buffer))
                        buffer = ""
                    }
                    parts.append(.expression(expr))
                }
                index = close + 1
            } else {
                buffer.append(character)
                index += 1
            }
        }
        if !buffer.isEmpty {
            parts.append(.text(buffer))
        }
        return .success(assemble(parts))
    }

    static func closingBrace(_ characters: [Character], openingAt open: Int) -> Result<Int, ExpressionSyntaxError> {
        var index = open + 1
        var inString = false
        while index < characters.count {
            let character = characters[index]
            if inString {
                if character == "\\" {
                    index += 2
                    continue
                }
                if character == "'" {
                    inString = false
                }
            } else if character == "'" {
                inString = true
            } else if character == "}" {
                return .success(index)
            } else if character == "{" {
                return .failure(ExpressionSyntaxError(
                    "'{' inside an expression",
                    help: "expressions cannot be nested; close the first one with '}'",
                    start: index,
                    end: index + 1
                ))
            }
            index += 1
        }
        return .failure(ExpressionSyntaxError(
            "unclosed '{'",
            help: "close the expression with '}' or write '{{' for a literal brace",
            start: open,
            end: open + 1
        ))
    }

    static func assemble(_ parts: [TemplatePart]) -> StringTemplate {
        if parts.count == 1, case .expression(let expr) = parts[0] {
            return .whole(expr)
        }
        var texts: [String] = []
        for part in parts {
            guard case .text(let text) = part else { return .parts(parts) }
            texts.append(text)
        }
        return .literal(texts.joined())
    }
}
