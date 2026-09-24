import Synchronization
import ApolloBase
import ApolloConfig

struct BindingScope: EvaluationScope {
    let snapshot: StoreSnapshot
    let locals: LocalScope

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

    public func cancel() {
        engine?.cancel(id)
    }

    public var currentValue: Value {
        engine?.currentValue(id) ?? .null
    }

    public func updateScope(_ scope: LocalScope) {
        engine?.updateScope(id, scope)
    }
}

@MainActor
public final class BindingEngine {
    private let store: SignalStore
    private let evaluator: Evaluator
    private var bindings: [Int: Binding] = [:]
    private var nextID = 0
    private var dirty: Set<Int> = []
    private var isFlushing = false
    private let warningBuffer = Mutex<[Diagnostic]>([])
    private var seenWarnings: Set<Diagnostic> = []

    public private(set) var evaluationCount = 0
    public var onWarning: (@MainActor (Diagnostic) -> Void)?

    public init(store: SignalStore, evaluator: Evaluator) {
        self.store = store
        self.evaluator = evaluator
    }

    @discardableResult
    func bind(_ source: BindingSource, scope: LocalScope, rank: BindingRank = .property, active: Bool, onChange: @escaping @MainActor (Value) -> Void) -> BindingHandle {
        nextID += 1
        let binding = Binding(id: nextID, source: source, scope: scope, rank: rank, isActive: active, onChange: onChange)
        bindings[binding.id] = binding
        if active {
            subscribe(binding)
        }
        evaluate(binding, snapshot: store.snapshot())
        return BindingHandle(engine: self, id: binding.id)
    }

    public func flush() {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        var rounds = 0
        while !dirty.isEmpty {
            rounds += 1
            if rounds > 8 {
                report(Diagnostic(.warning, "flush did not settle within 8 rounds"))
                break
            }
            let batch = dirty.sorted { bindings[$0]!.rank < bindings[$1]!.rank }
            dirty.removeAll()
            let snapshot = store.snapshot()
            for id in batch {
                guard let binding = bindings[id], !binding.isCancelled, binding.isActive else { continue }
                evaluate(binding, snapshot: snapshot)
            }
        }
        deliverWarnings()
    }

    func isActive(_ id: Int) -> Bool {
        bindings[id]?.isActive ?? false
    }

    func setActive(_ id: Int, _ active: Bool) {
        guard let binding = bindings[id], !binding.isCancelled, binding.isActive != active else { return }
        binding.isActive = active
        if active {
            subscribe(binding)
            evaluate(binding, snapshot: store.snapshot())
        } else {
            unsubscribe(binding)
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
        let changed = binding.source.localNames.contains { name in binding.scope[name] != scope[name] }
        binding.scope = scope
        if changed {
            markDirty(id)
        }
    }

    private func subscribe(_ binding: Binding) {
        guard binding.subscriptions.isEmpty, !binding.source.isConstant else { return }
        for path in binding.source.dependencies {
            let rewritten = rewrittenPath(path, locals: binding.scope)
            let id = binding.id
            let token = store.subscribe(rewritten) { [weak self] in
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

    private func markDirty(_ id: Int) {
        guard let binding = bindings[id], !binding.isCancelled else { return }
        binding.isDirty = true
        dirty.insert(id)
    }

    private func evaluate(_ binding: Binding, snapshot: StoreSnapshot) {
        binding.isDirty = false
        let scope = BindingScope(snapshot: snapshot, locals: binding.scope)
        let result = evaluator.render(binding.source.template, in: scope, at: binding.source.span)
        binding.evaluationCount += 1
        evaluationCount += 1
        guard binding.storedValue == nil || result != binding.storedValue else { return }
        binding.storedValue = result
        if binding.isActive {
            binding.onChange(result)
        }
    }

    private func report(_ diagnostic: Diagnostic) {
        warningBuffer.withLock { $0.append(diagnostic) }
    }

    private func deliverWarnings() {
        let pending = warningBuffer.withLock { buffer -> [Diagnostic] in
            let result = buffer
            buffer.removeAll()
            return result
        }
        for diagnostic in pending where seenWarnings.insert(diagnostic).inserted {
            onWarning?(diagnostic)
        }
    }
}
