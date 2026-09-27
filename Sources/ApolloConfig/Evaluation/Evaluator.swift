import ApolloBase

public protocol EvaluationScope: Sendable {
    func local(_ name: String) -> Value?
    func global(_ root: String, _ fields: [String]) -> Value
}

public struct Evaluator: Sendable {
    let filters: FilterTable
    let context: @Sendable () -> FilterContext
    let warn: @Sendable (Diagnostic) -> Void
    let gate: WarningGate
    let missingField: (@Sendable (String, SourceSpan?) -> Void)?

    public init(
        filters: FilterTable,
        context: @escaping @Sendable () -> FilterContext,
        warn: @escaping @Sendable (Diagnostic) -> Void,
        missingField: (@Sendable (String, SourceSpan?) -> Void)? = nil
    ) {
        self.filters = filters
        self.context = context
        self.warn = warn
        self.gate = WarningGate()
        self.missingField = missingField
    }

    private init(filters: FilterTable, context: @escaping @Sendable () -> FilterContext, warn: @escaping @Sendable (Diagnostic) -> Void, gate: WarningGate, missingField: (@Sendable (String, SourceSpan?) -> Void)?) {
        self.filters = filters
        self.context = context
        self.warn = warn
        self.gate = gate
        self.missingField = missingField
    }

    public func pinningContext(warn: @escaping @Sendable (Diagnostic) -> Void) -> Evaluator {
        let pinned = context()
        return Evaluator(filters: filters, context: { pinned }, warn: warn, gate: gate, missingField: missingField)
    }

    public func evaluate(_ expr: Expr, in scope: any EvaluationScope) -> Value {
        if case .literal(let constant) = expr { return constant }
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: scope, span: nil).value(expr)
        }
    }

    public func evaluate(_ expr: Expr, in scope: any EvaluationScope, at span: SourceSpan) -> Value {
        if case .literal(let constant) = expr { return constant }
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: scope, span: span).value(expr)
        }
    }

    public func render(_ template: StringTemplate, in scope: any EvaluationScope) -> Value {
        if let constant = template.literalValue { return constant }
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: scope, span: nil).render(template)
        }
    }

    public func render(_ template: StringTemplate, in scope: any EvaluationScope, at span: SourceSpan) -> Value {
        if let constant = template.literalValue { return constant }
        return StackHeadroom.run(minimum: ExpressionLimits.headroomMinimum, stackSize: ExpressionLimits.headroomStackSize) {
            EvaluationRun(evaluator: self, scope: scope, span: span).render(template)
        }
    }

    func report(_ message: String, span: SourceSpan?) {
        let diagnostic = Diagnostic(.warning, message, span: span)
        if gate.admit(diagnostic) {
            warn(diagnostic)
        }
    }
}

extension StringTemplate {
    public var literalValue: Value? {
        switch self {
        case .literal(let text): .string(text)
        case .whole(.literal(let value)): value
        default: nil
        }
    }
}
