import ApolloBase

struct ExpressionGrammar {
    static let maximumNesting = 32

    static let binaryLevels: [[String: BinaryOperator]] = [
        ["||": .or],
        ["&&": .and],
        ["==": .equal, "!=": .notEqual],
        ["<": .less, "<=": .lessOrEqual, ">": .greater, ">=": .greaterOrEqual],
        ["+": .add, "-": .subtract],
        ["*": .multiply, "/": .divide, "%": .remainder],
    ]

    let tokens: [ExpressionToken]
    let mapper: ExpressionSpanMapper
    var position = 0
    var nesting = 0
    var sawPipe = false

    init(tokens: [ExpressionToken], mapper: ExpressionSpanMapper) {
        self.tokens = tokens
        self.mapper = mapper
    }

    var current: ExpressionToken { tokens[position] }

    @discardableResult
    mutating func advance() -> ExpressionToken {
        let token = tokens[position]
        if position < tokens.count - 1 {
            position += 1
        }
        return token
    }

    mutating func match(_ symbol: String) -> Bool {
        guard current.isSymbol(symbol) else { return false }
        advance()
        return true
    }

    mutating func expect(_ symbol: String, _ message: String) throws(ExpressionSyntaxError) {
        guard match(symbol) else {
            throw ExpressionSyntaxError("\(message), found \(current.description)", start: current.start, end: current.end)
        }
    }

    mutating func enterNesting(_ token: ExpressionToken) throws(ExpressionSyntaxError) {
        nesting += 1
        guard nesting <= Self.maximumNesting else {
            throw ExpressionSyntaxError(
                "expression is nested too deeply",
                help: "use at most \(Self.maximumNesting) levels of parentheses, lists, indexes, conditionals and prefix operators",
                start: token.start,
                end: token.end
            )
        }
    }

    mutating func parseAll() throws(ExpressionSyntaxError) -> Expr {
        let expr = try parseExpression()
        guard case .end = current.kind else {
            throw ExpressionSyntaxError(
                "unexpected \(current.description)",
                help: sawPipe ? "filter arguments are simple values; wrap a computed argument in parentheses" : nil,
                start: current.start,
                end: current.end
            )
        }
        return expr
    }

    mutating func parseExpression() throws(ExpressionSyntaxError) -> Expr {
        var expr = try parseConditional()
        while match("|") {
            sawPipe = true
            let nameToken = current
            guard case .name(let name) = nameToken.kind else {
                throw ExpressionSyntaxError(
                    "expected a filter name after '|', found \(nameToken.description)",
                    start: nameToken.start,
                    end: nameToken.end
                )
            }
            advance()
            var arguments: [Expr] = []
            while startsPrimary(current) {
                arguments.append(try parsePostfix())
            }
            let call = FilterCall(name: name, arguments: arguments, span: mapper.span(from: nameToken.start, to: nameToken.end))
            expr = .pipe(expr, call)
        }
        return expr
    }

    func startsPrimary(_ token: ExpressionToken) -> Bool {
        switch token.kind {
        case .number, .string, .name: true
        case .symbol(let symbol): symbol == "(" || symbol == "["
        case .end: false
        }
    }

    mutating func parseConditional() throws(ExpressionSyntaxError) -> Expr {
        let condition = try parseCoalesce()
        let questionMark = current
        guard match("?") else { return condition }
        try enterNesting(questionMark)
        let then = try parseConditional()
        try expect(":", "expected ':' after the '?' branch")
        let otherwise = try parseConditional()
        nesting -= 1
        return .conditional(condition, then, otherwise)
    }

    mutating func parseCoalesce() throws(ExpressionSyntaxError) -> Expr {
        var expr = try parseBinary(level: 0)
        while match("??") {
            expr = .coalesce(expr, try parseBinary(level: 0))
        }
        return expr
    }

    mutating func parseBinary(level: Int) throws(ExpressionSyntaxError) -> Expr {
        guard level < Self.binaryLevels.count else { return try parseUnary() }
        var expr = try parseBinary(level: level + 1)
        while case .symbol(let symbol) = current.kind, let op = Self.binaryLevels[level][symbol] {
            advance()
            expr = .binary(op, expr, try parseBinary(level: level + 1))
        }
        return expr
    }

    mutating func parseUnary() throws(ExpressionSyntaxError) -> Expr {
        let token = current
        let op: UnaryOperator
        if token.isSymbol("!") {
            op = .not
        } else if token.isSymbol("-") {
            op = .negate
        } else {
            return try parsePostfix()
        }
        advance()
        try enterNesting(token)
        let operand = try parseUnary()
        nesting -= 1
        return .unary(op, operand)
    }

    mutating func parsePostfix() throws(ExpressionSyntaxError) -> Expr {
        let base = try parsePrimary()
        var members: [PathMember] = []
        while true {
            if match(".") {
                let token = current
                guard case .name(let field) = token.kind else {
                    var help: String?
                    if case .number = token.kind {
                        help = "use [0] to take an element of a list"
                    }
                    throw ExpressionSyntaxError(
                        "expected a field name after '.', found \(token.description)",
                        help: help,
                        start: token.start,
                        end: token.end
                    )
                }
                advance()
                members.append(.field(field))
            } else if current.isSymbol("[") {
                let open = advance()
                try enterNesting(open)
                let index = try parseExpression()
                try expect("]", "expected ']' after the index")
                nesting -= 1
                members.append(.index(index))
            } else {
                break
            }
        }
        guard !members.isEmpty else { return base }
        if case .path(let root, let existing) = base {
            return .path(root: root, members: existing + members)
        }
        return .access(base, members)
    }

    mutating func parsePrimary() throws(ExpressionSyntaxError) -> Expr {
        let token = current
        switch token.kind {
        case .number(let number):
            advance()
            return .literal(.number(number))
        case .string(let text):
            advance()
            return .literal(.string(text))
        case .name(let name):
            advance()
            switch name {
            case "true": return .literal(.bool(true))
            case "false": return .literal(.bool(false))
            case "null": return .literal(.null)
            default: return .path(root: name, members: [])
            }
        case .symbol("("):
            advance()
            try enterNesting(token)
            let inner = try parseExpression()
            try expect(")", "expected ')'")
            nesting -= 1
            return inner
        case .symbol("["):
            advance()
            try enterNesting(token)
            var items: [Expr] = []
            if !match("]") {
                repeat {
                    items.append(try parseExpression())
                } while match(",")
                try expect("]", "expected ',' or ']' in the list")
            }
            nesting -= 1
            return .list(items)
        default:
            throw ExpressionSyntaxError("expected an expression, found \(token.description)", start: token.start, end: token.end)
        }
    }
}
