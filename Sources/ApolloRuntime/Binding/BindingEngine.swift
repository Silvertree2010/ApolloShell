import Synchronization
import ApolloBase
import ApolloConfig

struct BindingScope: EvaluationScope {
    let snapshot: StoreSnapshot
    let locals: LocalScope
    var event: Record? = nil

    func local(_ name: String) -> Value? {
        locals[name]
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        switch root {
        case "self":
            guard case .string(let identity)? = locals[ContextScopeKeys.selfIdentity] else { break }
            return snapshot.value("self:" + identity, fields)
        case "surface":
            guard case .string(let key)? = locals[ContextScopeKeys.surfaceKey] else { break }
            return snapshot.value("surface:" + key, fields)
        case "surfaces":
            guard case .string(let key)? = locals[ContextScopeKeys.screenKey] else { break }
            return snapshot.value("surfaces:" + key, fields)
        case "screen":
            guard case .string(let key)? = locals[ContextScopeKeys.screenKey] else { break }
            return snapshot.value("screen:" + key, fields)
        case "event":
            guard let event else { break }
            return SignalStore.read(.record(event), fields)
        default:
            break
        }
        return snapshot.value(root, fields)
    }
}

func rewrittenPath(_ path: DependencyPath, locals: LocalScope) -> DependencyPath {
    switch path.root {
    case "self":
        guard case .string(let identity)? = locals[ContextScopeKeys.selfIdentity] else { return path }
        return DependencyPath("self:" + identity, path.fields)
    case "surface":
        guard case .string(let key)? = locals[ContextScopeKeys.surfaceKey] else { return path }
        return DependencyPath("surface:" + key, path.fields)
    case "surfaces":
        guard case .string(let key)? = locals[ContextScopeKeys.screenKey] else { return path }
        return DependencyPath("surfaces:" + key, path.fields)
    case "screen":
        guard case .string(let key)? = locals[ContextScopeKeys.screenKey] else { return path }
        return DependencyPath("screen:" + key, path.fields)
    default:
        return path
    }
}

@MainActor
final class Binding {
    let id: Int
    var source: BindingSource
    var scope: LocalScope
    var rank: BindingRank
    var isActive: Bool
    var isDirty = true
    var isCancelled = false
    var storedValue: Value?
    var currentValue: Value { storedValue ?? .null }
    var subscriptions: [SubscriptionToken] = []
    let onChange: @MainActor (Value) -> Void
    var evaluationCount = 0

    init(id: Int, source: BindingSource, scope: LocalScope, rank: BindingRank, isActive: Bool, onChange: @escaping @MainActor (Value) -> Void) {
        self.id = id
        self.source = source
        self.scope = scope
        self.rank = rank
        self.isActive = isActive
        self.onChange = onChange
    }
}

@MainActor
public final class BindingHandle {
    private weak var engine: BindingEngine?
    let id: Int

    init(engine: BindingEngine, id: Int) {
        self.engine = engine
        self.id = id
    }

    public var isActive: Bool {
        get { engine?.isActive(id) ?? false }
        set { engine?.setActive(id, newValue) }
    }

    func refresh() {
        engine?.refresh(id)
    }

    public func cancel() {
        engine?.cancel(id)
    }

    public var currentValue: Value {
        engine?.currentValue(id) ?? .null
    }

    public func updateScope(_ scope: LocalScope) {
        engine?.updateScope(id, scope)
    }

    func updateSource(_ value: CompiledValue) {
        engine?.updateSource(id, value)
    }
}

final class WarningBuffer: Sendable {
    private let storage = Mutex<[Diagnostic]>([])

    func append(_ diagnostic: Diagnostic) {
        storage.withLock { $0.append(diagnostic) }
    }

    func drain() -> [Diagnostic] {
        storage.withLock { buffer in
            let drained = buffer
            buffer.removeAll()
            return drained
        }
    }
}

@MainActor
public final class BindingEngine {
    private static let maximumRounds = 8

    private let store: SignalStore
    private let evaluator: Evaluator
    private var bindings: [Int: Binding] = [:]
    private var nextID = 0
    private var dirty: Set<Int> = []
    private var arrivals: [Int] = []
    private var isFlushing = false
    private var flushEvaluator: Evaluator?
    private let warningBuffer = WarningBuffer()
    private var seenWarnings: Set<Diagnostic> = []
    private var deferring = 0
    private(set) var flushCount = 0

    public private(set) var evaluationCount = 0
    public var onWarning: (@MainActor (Diagnostic) -> Void)?
    var freshen: (@MainActor (Set<DependencyPath>) -> Void)?

    var sharedEvaluator: Evaluator { evaluator }

    var liveBindingCount: Int { bindings.count }


    public init(store: SignalStore, evaluator: Evaluator) {
        self.store = store
        self.evaluator = evaluator
        store.onFlush = { [weak self] in
            self?.flush()
        }
    }

    @discardableResult
    public func bind(_ value: CompiledValue, scope: LocalScope, active: Bool, onChange: @escaping @MainActor (Value) -> Void) -> BindingHandle {
        bind(BindingSource(compiled: value), scope: scope, rank: .property, active: active, onChange: onChange)
    }

    @discardableResult
    func bind(_ value: CompiledValue, scope: LocalScope, rank: BindingRank, active: Bool, onChange: @escaping @MainActor (Value) -> Void) -> BindingHandle {
        bind(BindingSource(compiled: value), scope: scope, rank: rank, active: active, onChange: onChange)
    }

    func evaluateOnce(_ value: CompiledValue, scope: LocalScope, event: Record? = nil) -> Value {
        freshen?(value.dependencies)
        let adHoc = flushEvaluator == nil
        let evaluator = flushEvaluator ?? pinnedEvaluator()
        let result = evaluator.render(value.template, in: BindingScope(snapshot: store.snapshot(), locals: scope, event: event), at: value.span)
        if adHoc {
            deliverWarnings()
        }
        return result
    }

    @discardableResult
    func bind(_ source: BindingSource, scope: LocalScope, rank: BindingRank = .property, active: Bool, onChange: @escaping @MainActor (Value) -> Void) -> BindingHandle {
        nextID += 1
        let binding = Binding(id: nextID, source: source, scope: scope, rank: rank, isActive: active, onChange: onChange)
        bindings[binding.id] = binding
        if active {
            subscribe(binding)
            evaluateOrDefer(binding)
        }
        return BindingHandle(engine: self, id: binding.id)
    }

    private static func precedes(_ lhs: Binding, _ rhs: Binding) -> Bool {
        (lhs.rank, lhs.id) < (rhs.rank, rhs.id)
    }

    public func flush() {
        guard !isFlushing else { return }
        isFlushing = true
        flushCount += 1
        let outer = flushEvaluator
        flushEvaluator = pinnedEvaluator()
        var rounds = 0
        while !dirty.isEmpty {
            if rounds == Self.maximumRounds {
                report(Diagnostic(.warning, "flush did not settle within \(Self.maximumRounds) rounds", code: .flushUnsettled))
                break
            }
            rounds += 1
            var batch = dirty.compactMap { bindings[$0] }.sorted(by: Self.precedes)
            dirty.removeAll()
            arrivals.removeAll()
            var index = 0
            while index < batch.count {
                let binding = batch[index]
                index += 1
                if !binding.isCancelled && binding.isActive && binding.isDirty {
                    evaluate(binding)
                }
                guard !arrivals.isEmpty else { continue }
                let later = arrivals.compactMap { bindings[$0] }.filter { Self.precedes(binding, $0) && dirty.remove($0.id) != nil }
                arrivals.removeAll()
                guard !later.isEmpty else { continue }
                batch.append(contentsOf: later)
                batch[index...].sort(by: Self.precedes)
            }
        }
        flushEvaluator = outer
        isFlushing = false
        if !dirty.isEmpty {
            store.requestFlush()
        }
        deliverWarnings()
    }

    func refresh(_ id: Int) {
        guard let binding = bindings[id], !binding.isCancelled, !binding.isActive || binding.isDirty else { return }
        evaluate(binding)
    }

    func isActive(_ id: Int) -> Bool {
        bindings[id]?.isActive ?? false
    }

    func setActive(_ id: Int, _ active: Bool) {
        guard let binding = bindings[id], !binding.isCancelled, binding.isActive != active else { return }
        binding.isActive = active
        if active {
            subscribe(binding)
            evaluateOrDefer(binding)
        } else {
            unsubscribe(binding)
            dirty.remove(id)
            binding.isDirty = true
        }
    }

    func cancel(_ id: Int) {
        guard let binding = bindings[id] else { return }
        binding.isCancelled = true
        unsubscribe(binding)
        dirty.remove(id)
        bindings.removeValue(forKey: id)
    }

    func currentValue(_ id: Int) -> Value {
        bindings[id]?.currentValue ?? .null
    }

    func updateScope(_ id: Int, _ scope: LocalScope) {
        guard let binding = bindings[id], !binding.isCancelled else { return }
        let localsChanged = binding.source.localNames.contains { name in binding.scope[name] != scope[name] }
        let oldPaths = subscriptionPaths(binding.source, binding.scope)
        binding.scope = scope
        let pathsChanged = oldPaths != subscriptionPaths(binding.source, scope)
        if pathsChanged && binding.isActive {
            unsubscribe(binding)
            subscribe(binding)
        }
        if localsChanged || pathsChanged {
            markDirty(id)
        }
    }

    func updateSource(_ id: Int, _ value: CompiledValue) {
        bindings[id]?.source = BindingSource(compiled: value)
    }

    func deferEvaluation(_ body: () -> Void) {
        deferring += 1
        body()
        deferring -= 1
        if deferring == 0 {
            flush()
        }
    }

    private func subscriptionPaths(_ source: BindingSource, _ scope: LocalScope) -> Set<DependencyPath> {
        Set(source.dependencies.map { rewrittenPath($0, locals: scope) })
    }

    private func subscribe(_ binding: Binding) {
        guard binding.subscriptions.isEmpty, !binding.source.isConstant else { return }
        let id = binding.id
        for path in subscriptionPaths(binding.source, binding.scope) {
            let token = store.subscribe(path) { [weak self] in
                self?.markDirty(id)
            }
            binding.subscriptions.append(token)
        }
    }

    private func unsubscribe(_ binding: Binding) {
        for token in binding.subscriptions {
            store.unsubscribe(token)
        }
        binding.subscriptions.removeAll()
    }

    public func invalidateAll() {
        for id in bindings.keys { markDirty(id) }
    }

    private func markDirty(_ id: Int) {
        guard let binding = bindings[id], !binding.isCancelled else { return }
        binding.isDirty = true
        guard binding.isActive else { return }
        if isFlushing {
            if dirty.insert(id).inserted { arrivals.append(id) }
        } else {
            dirty.insert(id)
            store.requestFlush()
        }
    }

    private func evaluateOrDefer(_ binding: Binding) {
        if deferring > 0 {
            binding.isDirty = true
            if dirty.insert(binding.id).inserted && isFlushing { arrivals.append(binding.id) }
        } else {
            evaluate(binding)
        }
    }

    private func evaluate(_ binding: Binding) {
        dirty.remove(binding.id)
        binding.isDirty = false
        let adHoc = flushEvaluator == nil
        let result = render(binding, with: flushEvaluator ?? pinnedEvaluator())
        binding.evaluationCount += 1
        evaluationCount += 1
        if binding.storedValue == nil || result != binding.storedValue {
            binding.storedValue = result
            binding.onChange(result)
        }
        if adHoc {
            deliverWarnings()
        }
    }

    private func render(_ binding: Binding, with evaluator: Evaluator) -> Value {
        let scope = BindingScope(snapshot: store.snapshot(), locals: binding.scope)
        return evaluator.render(binding.source.template, in: scope, at: binding.source.span)
    }

    func batch(_ body: () -> Void) {
        guard flushEvaluator == nil else {
            body()
            return
        }
        flushEvaluator = pinnedEvaluator()
        body()
        flushEvaluator = nil
        deliverWarnings()
    }

    private func pinnedEvaluator() -> Evaluator {
        let buffer = warningBuffer
        return evaluator.pinningContext(warn: { buffer.append($0) })
    }

    private func report(_ diagnostic: Diagnostic) {
        warningBuffer.append(diagnostic)
    }

    private func deliverWarnings() {
        for diagnostic in warningBuffer.drain() {
            guard seenWarnings.count < RuntimeLimits.rememberedWarnings, seenWarnings.insert(diagnostic).inserted else { continue }
            onWarning?(diagnostic)
        }
    }

    func forgetWarnings() {
        seenWarnings.removeAll()
        evaluator.forgetWarnings()
    }
}
