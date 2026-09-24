import Testing
import Foundation
import Synchronization
import ApolloBase
@testable import ApolloConfig

@Suite("Evaluator mit festgehaltenem Kontext")
struct EvaluatorPinningTests {
    final class Clock: Sendable {
        private let state = Mutex<Double>(0)

        func tick() -> Date {
            state.withLock { seconds in
                seconds += 3_600
                return Date(timeIntervalSince1970: seconds)
            }
        }
    }

    static func base(clock: Clock, sink: WarningSink) -> Evaluator {
        Evaluator(
            filters: .builtin,
            context: {
                var context = FilterHarness.context
                context.now = clock.tick()
                return context
            },
            warn: { sink.add($0) }
        )
    }

    static let scope = TestScope(locals: ["t": .date(Date(timeIntervalSince1970: 0)), "s": .string("x")])

    @Test("Der Kontext wird einmal gelesen und gilt für alle Auswertungen")
    func contextIsReadOnce() throws {
        let base = Self.base(clock: Clock(), sink: WarningSink())
        let pinned = base.pinningContext(warn: { _ in })
        let template = try ExpressionParser.parseTemplate("{t | relative}", span: .synthetic("test")).get()
        let first = pinned.render(template, in: Self.scope)
        let second = pinned.render(template, in: Self.scope)
        #expect(first == .string("1 h ago"))
        #expect(second == first)
        #expect(base.render(template, in: Self.scope) != base.render(template, in: Self.scope))
    }

    @Test("Warnungen gehen an die neue Closure, einmal je Stelle über Kopien hinweg")
    func warningsAreRedirectedAndGated() throws {
        let original = WarningSink()
        let redirected = WarningSink()
        let base = Self.base(clock: Clock(), sink: original)
        let expr = try EvaluationHarness.expression("s | round")
        _ = base.pinningContext(warn: { redirected.add($0) }).evaluate(expr, in: Self.scope, at: .synthetic("site"))
        _ = base.pinningContext(warn: { redirected.add($0) }).evaluate(expr, in: Self.scope, at: .synthetic("site"))
        #expect(redirected.diagnostics.count == 1)
        #expect(original.diagnostics.isEmpty)
    }
}
