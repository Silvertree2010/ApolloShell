import ApolloBase
import ApolloConfig

private struct DefaultScope: EvaluationScope {
    let shell: Record
    let persisted: [String: Value]

    func local(_ name: String) -> Value? { nil }

    func global(_ root: String, _ fields: [String]) -> Value {
        switch root {
        case "shell":
            return SignalStore.read(.record(shell), fields)
        case "var":
            guard let first = fields.first else { return .null }
            let base = persisted[first] ?? .null
            return SignalStore.read(base, Array(fields.dropFirst()))
        default:
            return .null
        }
    }
}

struct DerivedGraphAnalysis {
    var cycleMembers: Set<String> = []
    var diagnostics: [Diagnostic] = []
    var order: [String: Int] = [:]

    init(names: [String], edges: [String: [String]], spans: [String: SourceSpan]) {
        let sortedNames = names.sorted()
        var index: [String: Int] = [:]
        var lowlink: [String: Int] = [:]
        var stack: [String] = []
        var onStack: Set<String> = []
        var nextIndex = 0
        var components: [[String]] = []

        for root in sortedNames where index[root] == nil {
            index[root] = nextIndex
            lowlink[root] = nextIndex
            nextIndex += 1
            stack.append(root)
            onStack.insert(root)
            var work: [(node: String, next: Int)] = [(root, 0)]
            while let top = work.last {
                let neighbors = edges[top.node] ?? []
                if top.next < neighbors.count {
                    work[work.count - 1].next += 1
                    let neighbor = neighbors[top.next]
                    if index[neighbor] == nil {
                        index[neighbor] = nextIndex
                        lowlink[neighbor] = nextIndex
                        nextIndex += 1
                        stack.append(neighbor)
                        onStack.insert(neighbor)
                        work.append((neighbor, 0))
                    } else if onStack.contains(neighbor) {
                        lowlink[top.node] = min(lowlink[top.node]!, index[neighbor]!)
                    }
                    continue
                }
                work.removeLast()
                if let parent = work.last?.node {
                    lowlink[parent] = min(lowlink[parent]!, lowlink[top.node]!)
                }
                guard lowlink[top.node] == index[top.node] else { continue }
                var component: [String] = []
                while let member = stack.popLast() {
                    onStack.remove(member)
                    component.append(member)
                    if member == top.node { break }
                }
                components.append(component.sorted())
            }
        }

        for (position, component) in components.enumerated() {
            for member in component { order[member] = position }
            guard let first = component.first else { continue }
            let isCycle = component.count > 1 || (edges[first] ?? []).contains(first)
            guard isCycle else { continue }
            let members = Set(component)
            cycleMembers.formUnion(members)
            let chain = Self.shortestCycle(from: first, within: members, edges: edges)
            let onChain = Set(chain)
            let notes = component.filter { !onChain.contains($0) }.map {
                DiagnosticNote("'\($0)' is part of the same cycle", span: spans[$0])
            }
            diagnostics.append(Diagnostic(
                .error,
                "cyclic derived var: \(chain.joined(separator: " -> "))",
                span: spans[first],
                notes: notes
            ))
        }
    }

    private static func shortestCycle(from start: String, within members: Set<String>, edges: [String: [String]]) -> [String] {
        var parent: [String: String] = [:]
        var visited: Set<String> = [start]
        var queue: [String] = [start]
        var head = 0
        while head < queue.count {
            let node = queue[head]
            head += 1
            for neighbor in edges[node] ?? [] where members.contains(neighbor) {
                if neighbor == start {
                    var path = [node]
                    var cursor = node
                    while let previous = parent[cursor] {
                        path.append(previous)
                        cursor = previous
                    }
                    return path.reversed() + [start]
                }
                guard visited.insert(neighbor).inserted else { continue }
                parent[neighbor] = node
                queue.append(neighbor)
            }
        }
        return [start, start]
    }
}

@MainActor
public final class VarStore {
    private final class PlainSlot {
        var decl: VarDecl
        var value: Value
        var defaultValue: Value
        var transient: TransientState?
        let token: Int

        init(decl: VarDecl, value: Value, defaultValue: Value, token: Int) {
            self.decl = decl
            self.value = value
            self.defaultValue = defaultValue
            self.token = token
        }
    }

    private struct TransientState {
        var baseValue: Value
        var work: ScheduledWork
    }

    private final class DerivedSlot {
        let decl: VarDecl
        let handle: BindingHandle?
        let order: Int
        let dependencies: [String]
        let paths: Set<DependencyPath>

        init(decl: VarDecl, handle: BindingHandle?, order: Int, dependencies: [String], paths: Set<DependencyPath>) {
            self.decl = decl
            self.handle = handle
            self.order = order
            self.dependencies = dependencies
            self.paths = paths
        }
    }

    private let store: SignalStore
    private let bindings: BindingEngine
    private let clock: any RuntimeClock
    private var plain: [String: PlainSlot] = [:]
    private var derived: [String: DerivedSlot] = [:]
    private var nextToken = 0
    private var pendingPersistWork: ScheduledWork?
    private var pendingPersistNames: Set<String> = []
    private var isReconciling = false
    private var reconcileAgain = false
    private var writer: StateWriter?
    private var fileValues: [String: Value] = [:]

    public var onPersist: (@MainActor ([String: Value]) -> Void)?
    public var onWarning: (@MainActor (Diagnostic) -> Void)?

    public init(store: SignalStore, bindings: BindingEngine, clock: any RuntimeClock = DispatchRuntimeClock()) {
        self.store = store
        self.bindings = bindings
        self.clock = clock
        store.addDemandObserver { [weak self] root in
            guard root == "var" else { return }
            self?.reconcileDemand()
        }
    }

    public func connect(_ writer: StateWriter) {
        self.writer = writer
        writer.setWarningHandler { [weak self] diagnostic in
            Task { @MainActor in
                self?.warn(diagnostic)
            }
        }
    }

    public func declare(_ decls: [VarDecl], persisted: [String: Value], shell: Record) {
        flushPendingSaves()
        apply(decls, persisted: persisted, shell: shell)
    }

    public func switchConfig(_ decls: [VarDecl], persisted: [String: Value], shell: Record, writer: StateWriter? = nil) {
        flushPendingSaves()
        discardAll()
        fileValues.removeAll()
        if let writer {
            connect(writer)
        }
        apply(decls, persisted: persisted, shell: shell)
    }

    public func value(_ name: String) -> Value {
        if let slot = plain[name] { return slot.value }
        if let slot = derived[name] {
            return slot.handle?.currentValue ?? .null
        }
        return .null
    }

    @discardableResult
    public func set(_ name: String, _ value: Value, for duration: Double? = nil) -> Bool {
        guard let slot = plain[name] else {
            warn(Diagnostic(.warning, "unknown var '\(name)'"))
            return false
        }
        let sanitized = SignalStore.sanitize(value)
        guard matchesType(slot.decl.type, sanitized) else {
            warn(Diagnostic(.warning, "'\(name)' expects \(slot.decl.type) but got \(value.typeName)", span: slot.decl.span))
            return false
        }
        if let duration, duration > 0 {
            let base = slot.transient?.baseValue ?? slot.value
            slot.transient?.work.cancel()
            let token = slot.token
            let work = clock.schedule(after: duration) { [weak self] in
                self?.endTransient(name, token: token)
            }
            slot.transient = TransientState(baseValue: base, work: work)
            slot.value = sanitized
            store.set(DependencyPath("var", [name]), sanitized)
        } else {
            slot.transient?.work.cancel()
            slot.transient = nil
            slot.value = sanitized
            store.set(DependencyPath("var", [name]), sanitized)
            markDirtyForPersist(name)
        }
        return true
    }

    public func reset(_ name: String) {
        guard let slot = plain[name] else {
            warn(Diagnostic(.warning, "unknown var '\(name)'"))
            return
        }
        slot.transient?.work.cancel()
        slot.transient = nil
        slot.value = slot.defaultValue
        store.set(DependencyPath("var", [name]), slot.defaultValue)
        markDirtyForPersist(name)
    }

    public func flushPendingSaves() {
        pendingPersistWork?.cancel()
        pendingPersistWork = nil
        if !pendingPersistNames.isEmpty {
            pendingPersistNames.removeAll()
            persist(persistSnapshot())
        }
        writer?.flushSync()
    }

    public func applyExternal(text: String) {
        writer?.acknowledgeExternal(text)
        let declarations = plain.keys.sorted().compactMap { plain[$0]?.decl }
        let (values, diagnostics) = VarStateFile.read(text, file: writer?.file.path ?? "state", declarations: declarations)
        var needsBackup = diagnostics.contains { $0.kind == .stateFileUnreadable || $0.kind == .valueDiscarded }
        for diagnostic in diagnostics { warn(diagnostic) }
        for name in values.keys.sorted() {
            guard let slot = plain[name], let raw = values[name] else { continue }
            let value = SignalStore.sanitize(raw)
            guard fileValues[name] != value else { continue }
            fileValues[name] = value
            guard matchesType(slot.decl.type, value) else {
                warn(Diagnostic(.warning, "'\(name)' in state file has the wrong type, keeping the current value", span: slot.decl.span, kind: .valueDiscarded))
                needsBackup = true
                continue
            }
            slot.transient?.work.cancel()
            slot.transient = nil
            slot.value = value
            store.set(DependencyPath("var", [name]), value)
        }
        if needsBackup {
            writer?.preserveUnreadable(text)
        }
    }

    private func apply(_ decls: [VarDecl], persisted: [String: Value], shell: Record) {
        let wasReconciling = isReconciling
        isReconciling = true
        for (name, value) in persisted {
            fileValues[name] = SignalStore.sanitize(value)
        }
        let previousPlain = plain
        let previousDerived = derived
        plain.removeAll()
        derived.removeAll()

        var derivedDecls: [String: VarDecl] = [:]
        var sources: [String: BindingSource] = [:]
        for decl in decls {
            guard let compiled = decl.derived else { continue }
            derivedDecls[decl.name] = decl
            sources[decl.name] = BindingSource(template: compiled.template, localNames: [], span: compiled.span)
        }
        var edges: [String: [String]] = [:]
        for (name, source) in sources {
            let names = Set(source.dependencies.filter { $0.root == "var" }.compactMap(\.fields.first))
            edges[name] = names.filter { derivedDecls[$0] != nil }.sorted()
        }
        let analysis = DerivedGraphAnalysis(names: Array(derivedDecls.keys), edges: edges, spans: derivedDecls.mapValues(\.span))
        for diagnostic in analysis.diagnostics { warn(diagnostic) }

        for decl in decls {
            if let source = sources[decl.name], derived[decl.name] == nil, plain[decl.name] == nil {
                let path = DependencyPath("var", [decl.name])
                var handle: BindingHandle?
                if analysis.cycleMembers.contains(decl.name) {
                    store.set(path, .null)
                } else {
                    handle = bindings.bind(source, scope: LocalScope(), rank: .derived(order: analysis.order[decl.name] ?? 0), active: false) { [weak self] value in
                        self?.store.set(path, value)
                    }
                }
                derived[decl.name] = DerivedSlot(
                    decl: decl,
                    handle: handle,
                    order: analysis.order[decl.name] ?? 0,
                    dependencies: edges[decl.name] ?? [],
                    paths: source.dependencies.filter { $0.root == "var" }
                )
            } else if decl.derived == nil, derived[decl.name] == nil, plain[decl.name] == nil {
                if let prior = previousPlain[decl.name], prior.decl.type == decl.type {
                    prior.decl = decl
                    prior.defaultValue = computeDefault(decl: decl, persisted: persisted, shell: shell)
                    plain[decl.name] = prior
                    store.set(DependencyPath("var", [decl.name]), prior.value)
                    continue
                }
                previousPlain[decl.name]?.transient?.work.cancel()
                let (initial, defaultValue) = computeInitial(decl: decl, persisted: persisted, shell: shell)
                nextToken += 1
                plain[decl.name] = PlainSlot(decl: decl, value: initial, defaultValue: defaultValue, token: nextToken)
                store.set(DependencyPath("var", [decl.name]), initial)
            }
        }

        for (name, prior) in previousPlain where plain[name] !== prior {
            prior.transient?.work.cancel()
        }
        for prior in previousDerived.values {
            prior.handle?.cancel()
        }
        let removed = Set(previousPlain.keys).union(previousDerived.keys).filter { plain[$0] == nil && derived[$0] == nil }
        for name in removed.sorted() {
            pendingPersistNames.remove(name)
            store.remove(DependencyPath("var", [name]))
        }
        isReconciling = wasReconciling
        reconcileDemand()
    }

    private func discardAll() {
        let wasReconciling = isReconciling
        isReconciling = true
        pendingPersistWork?.cancel()
        pendingPersistWork = nil
        pendingPersistNames.removeAll()
        let names = Set(plain.keys).union(derived.keys)
        for slot in plain.values {
            slot.transient?.work.cancel()
        }
        for slot in derived.values {
            slot.handle?.cancel()
        }
        plain.removeAll()
        derived.removeAll()
        for name in names.sorted() {
            store.remove(DependencyPath("var", [name]))
        }
        isReconciling = wasReconciling
    }

    private func endTransient(_ name: String, token: Int) {
        guard let slot = plain[name], slot.token == token, let transient = slot.transient else { return }
        slot.transient = nil
        slot.value = transient.baseValue
        store.set(DependencyPath("var", [name]), transient.baseValue)
    }

    private func markDirtyForPersist(_ name: String) {
        guard let slot = plain[name], slot.decl.persist else { return }
        pendingPersistNames.insert(name)
        if pendingPersistWork == nil {
            pendingPersistWork = clock.schedule(after: 0.5) { [weak self] in
                self?.firePersist()
            }
        }
    }

    private func firePersist() {
        pendingPersistWork = nil
        guard !pendingPersistNames.isEmpty else { return }
        pendingPersistNames.removeAll()
        persist(persistSnapshot())
    }

    private func persist(_ snapshot: [String: Value]) {
        fileValues.merge(snapshot) { $1 }
        onPersist?(snapshot)
        writer?.enqueue(snapshot)
    }

    private func persistSnapshot() -> [String: Value] {
        var result: [String: Value] = [:]
        for slot in plain.values where slot.decl.persist {
            result[slot.decl.name] = slot.transient?.baseValue ?? slot.value
        }
        return result
    }

    private func reconcileDemand() {
        if isReconciling {
            reconcileAgain = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            reconcileAgain = false
            reconcilePass()
        } while reconcileAgain
    }

    private func reconcilePass() {
        let live = derived.values.filter { $0.handle != nil }.sorted { ($0.order, $0.decl.name) < ($1.order, $1.decl.name) }
        guard !live.isEmpty else { return }
        var internalDemand: [DependencyPath: Int] = [:]
        for slot in live where slot.handle?.isActive == true {
            for path in slot.paths {
                internalDemand[path, default: 0] += 1
            }
        }
        var pending: [String] = []
        for path in store.demandedPaths(root: "var") {
            guard let name = path.fields.first, derived[name]?.handle != nil else { continue }
            if store.demandCount(path) > internalDemand[path, default: 0] {
                pending.append(name)
            }
        }
        var needed: Set<String> = []
        while let name = pending.popLast() {
            guard let slot = derived[name], slot.handle != nil, needed.insert(name).inserted else { continue }
            pending.append(contentsOf: slot.dependencies)
        }
        for slot in live.reversed() where slot.handle?.isActive == true && !needed.contains(slot.decl.name) {
            slot.handle?.isActive = false
        }
        for slot in live where slot.handle?.isActive == false && needed.contains(slot.decl.name) {
            slot.handle?.isActive = true
        }
    }

    private func evaluateTemplate(_ template: ValueTemplate, scope: any EvaluationScope) -> Value {
        switch template {
        case .scalar(let compiled):
            return bindings.sharedEvaluator.render(compiled.template, in: scope, at: compiled.span)
        case .list(let items):
            return .list(items.map { evaluateTemplate($0, scope: scope) })
        case .record(let fields):
            var record = Record()
            for field in fields {
                record[field.name] = evaluateTemplate(field.value, scope: scope)
            }
            return .record(record)
        }
    }

    private func computeDefault(decl: VarDecl, persisted: [String: Value], shell: Record) -> Value {
        let scope = DefaultScope(shell: shell, persisted: persisted)
        return SignalStore.sanitize(evaluateTemplate(decl.defaultValue, scope: scope))
    }

    private func computeInitial(decl: VarDecl, persisted: [String: Value], shell: Record) -> (initial: Value, fallback: Value) {
        let fallback = computeDefault(decl: decl, persisted: persisted, shell: shell)
        guard let saved = persisted[decl.name] else { return (fallback, fallback) }
        let sanitizedSaved = SignalStore.sanitize(saved)
        if matchesType(decl.type, sanitizedSaved) { return (sanitizedSaved, fallback) }
        warn(Diagnostic(.warning, "'\(decl.name)' in state file has the wrong type, using the default", span: decl.span))
        return (fallback, fallback)
    }

    private func matchesType(_ type: ValueType, _ value: Value) -> Bool {
        switch type {
        case .any: return true
        case .string: if case .string = value { return true }; return false
        case .number: if case .number = value { return true }; return false
        case .bool: if case .bool = value { return true }; return false
        case .list: if case .list = value { return true }; return false
        case .record: if case .record = value { return true }; return false
        case .enumeration(let options):
            if case .string(let text) = value { return options.contains(text) }
            return false
        default: return true
        }
    }

    private func warn(_ diagnostic: Diagnostic) {
        onWarning?(diagnostic)
    }
}
