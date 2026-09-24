import ApolloBase

public enum ExpressionParser {
    public static func parseExpression(_ source: String, span: SourceSpan) -> Result<Expr, Diagnostic> {
        let characters = Array(source)
        return parse(characters, mapper: ExpressionSpanMapper(base: span, characters: characters, origin: 0))
    }

    static func parse(_ characters: [Character], mapper: ExpressionSpanMapper) -> Result<Expr, Diagnostic> {
        StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            do throws(ExpressionSyntaxError) {
                let tokens = try ExpressionLexer.scan(characters)
                var grammar = ExpressionGrammar(tokens: tokens, mapper: mapper)
                return .success(try grammar.parseAll())
            } catch {
                return .failure(mapper.diagnostic(for: error))
            }
        }
    }
}

enum ExpressionLimits {
    static let headroomMinimum = 1 << 20
    static let headroomStackSize = 8 << 20
}
