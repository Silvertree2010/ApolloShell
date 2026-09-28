import ApolloBase
import Synchronization

public struct CompiledValue: Sendable, Hashable {
    public var template: StringTemplate {
        didSet { roots = PathRootsCache() }
    }
    public var dependencies: Set<DependencyPath> {
        didSet { roots = PathRootsCache() }
    }
    public var span: SourceSpan
    private var roots = PathRootsCache()

    public init(template: StringTemplate, dependencies: Set<DependencyPath>, span: SourceSpan) {
        self.template = template
        self.dependencies = dependencies
        self.span = span
    }

    public var isConstant: Bool {
        dependencies.isEmpty
    }

    public var pathRoots: Set<String> {
        roots.value { template.pathRoots }
    }

    public var localRoots: Set<String> {
        roots.locals {
            let globalRoots = Set(dependencies.map(\.root))
            return pathRoots.subtracting(globalRoots)
        }
    }

    public static func == (lhs: CompiledValue, rhs: CompiledValue) -> Bool {
        lhs.template == rhs.template && lhs.dependencies == rhs.dependencies && lhs.span == rhs.span
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(template)
        hasher.combine(dependencies)
        hasher.combine(span)
    }
}

private final class PathRootsCache: Sendable {
    private let stored = Mutex<Set<String>?>(nil)
    private let storedLocals = Mutex<Set<String>?>(nil)

    func value(_ compute: () -> Set<String>) -> Set<String> {
        if let cached = stored.withLock({ $0 }) { return cached }
        let computed = compute()
        stored.withLock { $0 = computed }
        return computed
    }

    func locals(_ compute: () -> Set<String>) -> Set<String> {
        if let cached = storedLocals.withLock({ $0 }) { return cached }
        let computed = compute()
        storedLocals.withLock { $0 = computed }
        return computed
    }
}

public indirect enum ValueTemplate: Sendable, Hashable {
    case scalar(CompiledValue)
    case list([ValueTemplate])
    case record([ValueTemplateField])
}

public struct ValueTemplateField: Sendable, Hashable {
    public var name: String
    public var value: ValueTemplate

    public init(name: String, value: ValueTemplate) {
        self.name = name
        self.value = value
    }
}

extension ValueTemplate {
    var dependencies: Set<DependencyPath> {
        switch self {
        case .scalar(let compiled):
            return compiled.dependencies
        case .list(let items):
            return items.reduce(into: Set<DependencyPath>()) { $0.formUnion($1.dependencies) }
        case .record(let fields):
            return fields.reduce(into: Set<DependencyPath>()) { $0.formUnion($1.value.dependencies) }
        }
    }

    var isConstant: Bool {
        dependencies.isEmpty
    }

    public func evaluate(with evaluator: Evaluator, scope: any EvaluationScope) -> Value {
        switch self {
        case .scalar(let compiled):
            return evaluator.render(compiled.template, in: scope, at: compiled.span)
        case .list(let items):
            return .list(items.map { $0.evaluate(with: evaluator, scope: scope) })
        case .record(let fields):
            var record = Record()
            for field in fields {
                record[field.name] = field.value.evaluate(with: evaluator, scope: scope)
            }
            return .record(record)
        }
    }
}

enum CompiledValueBuilder {
    static func compile(_ text: String, span: SourceSpan, locals: Set<String>) -> Result<CompiledValue, Diagnostic> {
        switch ExpressionParser.parseTemplate(text, span: span) {
        case .failure(let diagnostic):
            return .failure(diagnostic)
        case .success(let template):
            return .success(CompiledValue(template: template, dependencies: template.dependencies(locals: locals), span: span))
        }
    }

    static func literal(_ value: Value, span: SourceSpan) -> CompiledValue {
        CompiledValue(template: .whole(.literal(value)), dependencies: [], span: span)
    }
}
