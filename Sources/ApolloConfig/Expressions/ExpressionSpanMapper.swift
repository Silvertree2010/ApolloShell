import ApolloBase

struct ExpressionSpanMapper: Sendable {
    let base: SourceSpan
    let characters: [Character]
    let origin: Int

    func shifted(to origin: Int) -> ExpressionSpanMapper {
        ExpressionSpanMapper(base: base, characters: characters, origin: origin)
    }

    func span(from start: Int, to end: Int) -> SourceSpan {
        let first = min(origin + start, characters.count)
        let last = min(max(origin + end, first), characters.count)
        let startColumn = base.start.column + 1 + first
        let endColumn = base.start.column + 1 + last
        guard base.start.line == base.end.line, endColumn <= base.end.column else { return base }
        let startOffset = base.start.offset + 1 + Self.utf8Length(characters[..<first])
        let endOffset = startOffset + Self.utf8Length(characters[first..<last])
        return SourceSpan(
            file: base.file,
            start: SourcePosition(offset: startOffset, line: base.start.line, column: startColumn),
            end: SourcePosition(offset: endOffset, line: base.start.line, column: endColumn)
        )
    }

    func diagnostic(for error: ExpressionSyntaxError) -> Diagnostic {
        Diagnostic(.error, error.message, span: span(from: error.start, to: error.end), help: error.help, code: .expressionSyntax)
    }

    static func utf8Length(_ characters: ArraySlice<Character>) -> Int {
        characters.reduce(0) { $0 + $1.utf8.count }
    }
}
