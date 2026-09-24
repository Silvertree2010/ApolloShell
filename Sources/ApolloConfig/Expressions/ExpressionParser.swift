import ApolloBase
import Foundation

public enum ExpressionParser {
    public static func parseExpression(_ source: String, span: SourceSpan) -> Result<Expr, Diagnostic> {
        let characters = Array(source)
        return parse(characters, mapper: ExpressionSpanMapper(base: span, characters: characters, origin: 0))
    }

    static func parse(_ characters: [Character], mapper: ExpressionSpanMapper) -> Result<Expr, Diagnostic> {
        ExpressionRecursionGuard.run {
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

private final class ExpressionRecursionGuardBox<ReturnValue>: @unchecked Sendable {
    var value: ReturnValue?
}

enum ExpressionRecursionGuard {
    static func run<ReturnValue: Sendable>(_ body: @escaping @Sendable () -> ReturnValue) -> ReturnValue {
        let box = ExpressionRecursionGuardBox<ReturnValue>()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.value = body()
            semaphore.signal()
        }
        thread.stackSize = 8 << 20
        thread.start()
        semaphore.wait()
        return box.value!
    }
}
