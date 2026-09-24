import ApolloBase

struct ScopeBox: @unchecked Sendable {
    let scope: any EvaluationScope

    init(_ scope: any EvaluationScope) {
        self.scope = scope
    }
}

public protocol EvaluationScope {
    func local(_ name: String) -> Value?
    func global(_ root: String, _ fields: [String]) -> Value
}

public struct Evaluator: Sendable {
    let filters: FilterTable
    let context: @Sendable () -> FilterContext
    let warn: @Sendable (Diagnostic) -> Void
    let gate: WarningGate

    public init(filters: FilterTable, context: @escaping @Sendable () -> FilterContext, warn: @escaping @Sendable (Diagnostic) -> Void) {
        self.filters = filters
        self.context = context
        self.warn = warn
        self.gate = WarningGate()
    }

    public func evaluate(_ expr: Expr, in scope: any EvaluationScope) -> Value {
        let box = ScopeBox(scope)
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: box.scope, span: nil).value(expr)
        }
    }

    public func evaluate(_ expr: Expr, in scope: any EvaluationScope, at span: SourceSpan) -> Value {
        let box = ScopeBox(scope)
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: box.scope, span: span).value(expr)
        }
    }

    public func render(_ template: StringTemplate, in scope: any EvaluationScope) -> Value {
        let box = ScopeBox(scope)
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: box.scope, span: nil).render(template)
        }
    }

    public func render(_ template: StringTemplate, in scope: any EvaluationScope, at span: SourceSpan) -> Value {
        let box = ScopeBox(scope)
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: box.scope, span: span).render(template)
        }
    }

    func report(_ message: String, span: SourceSpan?) {
        let diagnostic = Diagnostic(.warning, message, span: span)
        if gate.admit(diagnostic) {
            warn(diagnostic)
        }
    }
}
