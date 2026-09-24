enum ExpressionTokenKind: Sendable, Hashable {
    case number(Double)
    case string(String)
    case name(String)
    case symbol(String)
    case end
}

struct ExpressionToken: Sendable, Hashable {
    var kind: ExpressionTokenKind
    var start: Int
    var end: Int

    var description: String {
        switch kind {
        case .number(let number): "'\(NumberText.plain(number))'"
        case .string(let text): "string '\(text)'"
        case .name(let name): "'\(name)'"
        case .symbol(let symbol): "'\(symbol)'"
        case .end: "end of expression"
        }
    }

    func isSymbol(_ symbol: String) -> Bool {
        kind == .symbol(symbol)
    }
}

struct ExpressionSyntaxError: Error, Sendable, Hashable {
    var message: String
    var help: String?
    var start: Int
    var end: Int

    init(_ message: String, help: String? = nil, start: Int, end: Int) {
        self.message = message
        self.help = help
        self.start = start
        self.end = end
    }
}
