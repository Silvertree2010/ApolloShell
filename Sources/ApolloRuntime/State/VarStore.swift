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

@MainActor
public final class VarStore {
    private final class NonDerivedSlot {
        var decl: VarDecl
        var value: Value
        let defaultValue: Value
        var transient: TransientState?
        var token = 0

        init(decl: VarDecl, value: Value, defaultValue: Value) {
            self.decl = decl
            self.value = value
            self.defaultValue = defaultValue
        }
    }

    private struct TransientState {
        var baseValue: Value
        var work: ScheduledWork
    }

    private final class DerivedSlot {
        var decl: VarDecl
        var handle: BindingHandle?
        var hasCycle = false

        init(decl: VarDecl) {
            self.decl = decl
        }
    }

    private let store: SignalStore
    private let bindings: BindingEngine
    private let clock: any RuntimeClock
    private var plain: [String: NonDerivedSlot] = [:]
    private var derived: [String: DerivedSlot] = [:]
    private var nextToken = 0
    private var pendingPersistWork: ScheduledWork?
    private var pendingPersistNames: Set<String> = []

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

    public func declare(_ decls: [VarDecl], persisted: [String: Value], shell: Record) {
        flushPendingSaves()
        let previousPlain = plain
        let previousDerived = derived
        plain.removeAll()
        derived.removeAll()

        let derivedDecls = decls.filter { $0.derived != nil }
        let derivedNames = Set(derivedDecls.map(\.name))
        var edges: [String: [String]] = [:]
        for decl in derivedDecls {
            guard let compiled = decl.derived else { continue }
            let names = Set(compiled.dependencies.filter { $0.root == "var" }.compactMap { $0.fields.first }.filter { derivedNames.contains($0) })
            edges[decl.name] = Array(names)
        }
        let (cycleMembers, cycleDiagnostics, order) = detectCyclesAndOrder(Array(derivedNames), edges: edges)
        for diagnostic in cycleDiagnostics { warn(diagnostic) }

        for decl in decls {
            if let compiled = decl.derived {
                let slot = DerivedSlot(decl: decl)
                derived[decl.name] = slot
                if cycleMembers.contains(decl.name) {
                    slot.hasCycle = true
                    store.set(DependencyPath("var", [decl.name]), .null)
                    continue
                }
                let rankOrder = order[decl.name] ?? 0
                let source = BindingSource(template: compiled.template, localNames: [], span: compiled.span)
                let name = decl.name
                let handle = bindings.bind(source, scope: LocalScope(), rank: .derived(order: rankOrder), active: false) { [weak self] value in
                    self?.store.set(DependencyPath("var", [name]), value)
                }
                slot.handle = handle
            } else {
                if let prior = previousPlain[decl.name], prior.decl.type == decl.type {
                    prior.decl = decl
                    plain[decl.name] = prior
                    store.set(DependencyPath("var", [decl.name]), prior.value)
                    continue
                }
                previousPlain[decl.name]?.transient?.work.cancel()
                let (initial, defaultValue) = computeInitial(decl: decl, persisted: persisted, shell: shell)
                nextToken += 1
                let slot = NonDerivedSlot(decl: decl, value: initial, defaultValue: defaultValue)
                slot.token = nextToken
                plain[decl.name] = slot
                store.set(DependencyPath("var", [decl.name]), initial)
            }
        }

        for (name, prior) in previousPlain where plain[name] == nil {
            prior.transient?.work.cancel()
        }
        for (name, prior) in previousDerived where derived[name] == nil {
            prior.handle?.cancel()
        }
        reconcileDemand()
    }

    public func value(_ name: String) -> Value {
        if let slot = plain[name] { return slot.value }
        if let slot = derived[name] {
            if slot.hasCycle { return .null }
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
        guard matchesType(slot.decl.type, value) else {
            warn(Diagnostic(.warning, "'\(name)' expects \(slot.decl.type) but got \(value.typeName)", span: slot.decl.span))
            return false
        }
        let sanitized = SignalStore.sanitize(value)
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
        guard !pendingPersistNames.isEmpty else { return }
        pendingPersistNames.removeAll()
        onPersist?(persistSnapshot())
    }

    public func applyExternal(text: String) {
        let declarations = plain.values.map(\.decl) + derived.values.map(\.decl)
        let (values, diagnostics) = VarStateFile.read(text, file: "state", declarations: declarations)
        for diagnostic in diagnostics { warn(diagnostic) }
        for (name, value) in values {
            guard let slot = plain[name] else { continue }
            slot.transient?.work.cancel()
            slot.transient = nil
            slot.value = SignalStore.sanitize(value)
            store.set(DependencyPath("var", [name]), slot.value)
        }
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
        onPersist?(persistSnapshot())
    }

    private func persistSnapshot() -> [String: Value] {
        var result: [String: Value] = [:]
        for slot in plain.values where slot.decl.persist {
            result[slot.decl.name] = slot.transient?.baseValue ?? slot.value
        }
        return result
    }

    private func reconcileDemand() {
        guard !derived.isEmpty else { return }
        let demandedPaths = store.demandedPaths(root: "var")
        var demandedNames: Set<String> = []
        for path in demandedPaths {
            if let first = path.fields.first { demandedNames.insert(first) }
        }
        for (_, slot) in derived {
            guard let handle = slot.handle else { continue }
            let shouldBeActive = demandedNames.contains(slot.decl.name)
            if handle.isActive != shouldBeActive {
                handle.isActive = shouldBeActive
            }
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

    private func computeInitial(decl: VarDecl, persisted: [String: Value], shell: Record) -> (initial: Value, fallback: Value) {
        let scope = DefaultScope(shell: shell, persisted: persisted)
        let fallback = SignalStore.sanitize(evaluateTemplate(decl.defaultValue, scope: scope))
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

    private func detectCyclesAndOrder(_ names: [String], edges: [String: [String]]) -> (members: Set<String>, diagnostics: [Diagnostic], order: [String: Int]) {
        enum Color { case white, gray, black }
        var color: [String: Color] = Dictionary(uniqueKeysWithValues: names.map { ($0, .white) })
        var diagnostics: [Diagnostic] = []
        var cycleMembers: Set<String> = []
        var order: [String: Int] = [:]
        var nextOrder = 0

        for start in names where color[start] == .white {
            var pathStack: [String] = [start]
            var iterStack: [(node: String, index: Int)] = [(start, 0)]
            color[start] = .gray
            while let top = iterStack.last {
                let neighbors = edges[top.node] ?? []
                if top.index < neighbors.count {
                    let next = neighbors[top.index]
                    iterStack[iterStack.count - 1].index += 1
                    guard let nextColor = color[next] else { continue }
                    switch nextColor {
                    case .white:
                        color[next] = .gray
                        pathStack.append(next)
                        iterStack.append((next, 0))
                    case .gray:
                        if let cycleStart = pathStack.firstIndex(of: next) {
                            let cycle = Array(pathStack[cycleStart...])
                            for member in cycle { cycleMembers.insert(member) }
                            let chain = (cycle + [next]).joined(separator: " -> ")
                            diagnostics.append(Diagnostic(.error, "cyclic derived var: \(chain)"))
                        }
                    case .black:
                        break
                    }
                } else {
                    color[top.node] = .black
                    if !cycleMembers.contains(top.node) {
                        order[top.node] = nextOrder
                        nextOrder += 1
                    }
                    pathStack.removeLast()
                    iterStack.removeLast()
                }
            }
        }
        return (cycleMembers, diagnostics, order)
    }
}
