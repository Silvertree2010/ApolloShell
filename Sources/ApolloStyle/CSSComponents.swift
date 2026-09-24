import ApolloBase
import ApolloShellCore

struct CSSValueError: Error, Sendable, Hashable {
    var message: String
    var assetRejection: ThemeAssetRejection?

    init(_ message: String, assetRejection: ThemeAssetRejection? = nil) {
        self.message = message
        self.assetRejection = assetRejection
    }
}

enum CSSBlockKind: Sendable, Hashable {
    case paren
    case bracket
    case brace

    var close: String {
        switch self {
        case .paren: ")"
        case .bracket: "]"
        case .brace: "}"
        }
    }
}

indirect enum CSSComponent: Sendable, Hashable {
    case token(CSSToken)
    case function(name: String, arguments: [CSSComponent], opening: CSSToken)
    case block(CSSBlockKind, contents: [CSSComponent], opening: CSSToken)

    var isWhitespace: Bool { tokenKind == .whitespace }
    var isComma: Bool { tokenKind == .comma }
    var isSemicolon: Bool { tokenKind == .semicolon }
    var isColon: Bool { tokenKind == .colon }

    var tokenKind: CSSTokenKind? {
        if case let .token(token) = self { return token.kind }
        return nil
    }

    var delimCharacter: Character? {
        if case let .delim(character)? = tokenKind { return character }
        return nil
    }

    var ident: String? {
        if case let .ident(name)? = tokenKind { return name }
        return nil
    }

    var lowercasedIdent: String? { ident?.lowercased() }

    var functionName: String? {
        if case let .function(name, _, _) = self { return name.lowercased() }
        return nil
    }

    var start: SourcePosition {
        switch self {
        case let .token(token): token.start
        case let .function(_, _, opening): opening.start
        case let .block(_, _, opening): opening.start
        }
    }

    var end: SourcePosition {
        var node = self
        while true {
            switch node {
            case let .token(token):
                return token.end
            case let .function(_, arguments, opening):
                guard let last = arguments.last else { return opening.end }
                node = last
            case let .block(_, contents, opening):
                guard let last = contents.last else { return opening.end }
                node = last
            }
        }
    }

    var text: String { CSSComponent.renderedText([self]) }

    private static func renderedText(_ components: [CSSComponent]) -> String {
        enum Piece {
            case text(String)
            case expand([CSSComponent])
        }
        var output = ""
        var stack: [Piece] = [.expand(components)]
        while let piece = stack.popLast() {
            switch piece {
            case let .text(text):
                output += text
            case let .expand(items):
                for component in items.reversed() {
                    switch component {
                    case let .token(token):
                        stack.append(.text(token.text))
                    case let .function(_, arguments, opening):
                        stack.append(.text(")"))
                        stack.append(.expand(arguments))
                        stack.append(.text(opening.text))
                    case let .block(kind, contents, opening):
                        stack.append(.text(kind.close))
                        stack.append(.expand(contents))
                        stack.append(.text(opening.text))
                    }
                }
            }
        }
        return output
    }
}

enum CSSComponentParser {
    static let maximumNestingDepth = 256

    static func parse(text: String) -> [CSSComponent] {
        parse(CSSTokenizer.tokenize(text).tokens)
    }

    static func parse(_ tokens: [CSSToken]) -> [CSSComponent] {
        StackHeadroom.run {
            var index = 0
            return list(tokens, &index, closing: nil, depth: 0)
        }
    }

    private static func list(_ tokens: [CSSToken], _ index: inout Int, closing: CSSTokenKind?, depth: Int) -> [CSSComponent] {
        var result: [CSSComponent] = []
        while index < tokens.count {
            let token = tokens[index]
            if let closing, token.kind == closing {
                index += 1
                return result
            }
            index += 1
            guard depth < maximumNestingDepth else {
                result.append(.token(token))
                continue
            }
            switch token.kind {
            case let .function(name):
                result.append(.function(name: name, arguments: list(tokens, &index, closing: .closeParen, depth: depth + 1), opening: token))
            case .openParen:
                result.append(.block(.paren, contents: list(tokens, &index, closing: .closeParen, depth: depth + 1), opening: token))
            case .openBracket:
                result.append(.block(.bracket, contents: list(tokens, &index, closing: .closeBracket, depth: depth + 1), opening: token))
            case .openBrace:
                result.append(.block(.brace, contents: list(tokens, &index, closing: .closeBrace, depth: depth + 1), opening: token))
            default:
                result.append(.token(token))
            }
        }
        return result
    }
}

enum CSSList {
    static func words(_ components: [CSSComponent]) -> [CSSComponent] {
        components.filter { !$0.isWhitespace }
    }

    static func split(_ components: [CSSComponent], by isSeparator: (CSSComponent) -> Bool) -> [[CSSComponent]] {
        var parts: [[CSSComponent]] = [[]]
        for component in components {
            if isSeparator(component) {
                parts.append([])
            } else {
                parts[parts.count - 1].append(component)
            }
        }
        return parts
    }

    static func commaSeparated(_ components: [CSSComponent]) -> [[CSSComponent]] {
        split(components, by: \.isComma).map(words)
    }

    static func trimmed(_ components: [CSSComponent]) -> [CSSComponent] {
        var result = ArraySlice(components)
        while result.first?.isWhitespace == true { result.removeFirst() }
        while result.last?.isWhitespace == true { result.removeLast() }
        return Array(result)
    }

    static func text(_ components: [CSSComponent]) -> String {
        trimmed(components).map(\.text).joined()
    }
}
