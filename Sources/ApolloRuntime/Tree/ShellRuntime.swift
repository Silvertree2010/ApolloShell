import Foundation
import ApolloBase
import ApolloConfig
import ApolloStyle

@MainActor
public final class ShellRuntime: SurfaceControlling {
    private let registry: SchemaRegistry
    private let evaluator: Evaluator
    let store: SignalStore
    let bindings: BindingEngine
    private let vars: VarStore
    private let providers: ProviderHost
    private let actions: ActionDispatcher
    private let host: any SurfaceHosting

    private(set) var config: ConfigIR?
    private var screens: [String] = []
    var surfaceNodes: [String: SurfaceNode] = [:]
    private var surfaceOrder: [String] = []
    var elements: [Identity: ElementNode] = [:]
    private var configTokens: [SubscriptionToken] = []
    private var awakeTokens: [SubscriptionToken] = []
    private var inSession = false
    private var queue: [@MainActor () -> Void] = []
    private var dirtyContainers: [ObjectIdentifier: Container] = [:]
    private var propagating = 0
    private var warned: Set<String> = []
    private var surfacesBuilt = 0
    private var elementsBuilt = 0
    private var pendingTeardown: [TreeNode] = []
    var generation = 0
    var eachPass = 0
    var reloading = false
    var definesChanged = false

    public var onWarning: (@MainActor (Diagnostic) -> Void)?
    public var onDiagnostics: (@MainActor ([Diagnostic]) -> Void)?
    public var onConfigApplied: (@MainActor (_ old: ConfigIR?, _ new: ConfigIR) -> Void)?
    public var preferredScreen: (@MainActor () -> String?)?

    enum EachKeyLookup {
        case dictionary
        case linear
    }

    var eachKeyLookup = EachKeyLookup.dictionary

    public init(registry: SchemaRegistry, evaluator: Evaluator, store: SignalStore, bindings: BindingEngine, vars: VarStore, providers: ProviderHost, actions: ActionDispatcher, host: any SurfaceHosting) {
        self.registry = registry
        self.evaluator = evaluator
        self.store = store
        self.bindings = bindings
        self.vars = vars
        self.providers = providers
        self.actions = actions
        self.host = host
        actions.surfaces = self
        providers.onEvent = { [weak self] event, fields in
            _ = self?.emit(event, fields)
        }
    }

    public var stats: RuntimeStats {
        RuntimeStats(
            surfacesBuilt: surfacesBuilt,
            elementsBuilt: elementsBuilt,
            bindingsEvaluated: bindings.evaluationCount,
            providersRunning: providers.runningProviderCount
        )
    }

    public func surface(_ id: String, screenKey: String) -> SurfaceInstance? {
        surfaceNodes[id + "@" + screenKey]?.instance
    }

    public func element(_ identity: Identity) -> ElementInstance? {
        elements[identity]?.instance
    }

    @discardableResult
    public func applyLoaded(_ result: ConfigLoadResult, persisted: [String: Value], screens: [String], shell: Record, writer: StateWriter? = nil) -> Bool {
        onDiagnostics?(result.diagnostics)
        guard let ir = result.ir else {
            let errors = result.diagnostics.filter { $0.severity == .error }.count
            emit("config.failed", Record([("errors", .number(Double(errors)))]))
            return false
        }
        let old = config
        apply(ir, persisted: persisted, screens: screens, shell: shell, writer: writer)
        onConfigApplied?(old, ir)
        let warnings = result.diagnostics.filter { $0.severity == .warning }.count
        emit("config.loaded", Record([("warnings", .number(Double(warnings)))]))
        return true
    }

    public func apply(_ ir: ConfigIR, persisted: [String: Value], screens: [String], shell: Record, writer: StateWriter? = nil) {
        if let old = config {
            reload(from: old, to: ir, persisted: persisted, screens: screens, shell: shell, writer: writer)
            return
        }
        teardownAll()
        warned.removeAll()
        config = ir
        self.screens = screens
        store.set(DependencyPath("shell", []), .record(shell))
        if let writer {
            vars.connect(writer)
        }
        vars.declare(ir.vars, persisted: persisted, shell: shell)
        registerConfigDemand(ir)
        var added: [SurfaceNode] = []
        withSession {
            for surfaceIR in ir.surfaces {
                for screen in targetScreens(surfaceIR) {
                    added.append(buildSurface(surfaceIR, screen: screen))
                }
            }
        }
        for node in added {
            host.surfaceAdded(node.instance)
        }
    }

    private func reload(from old: ConfigIR, to ir: ConfigIR, persisted: [String: Value], screens: [String], shell: Record, writer: StateWriter?) {
        warned.removeAll()
        let diff = IRDiff.surfaces(old: old, new: ir)
        let changedIDs = Set(diff.changed.map(\.id))
        var added: [SurfaceNode] = []
        var replaced: [SurfaceNode] = []
        var changed: [SurfaceNode] = []
        var removed: [(id: String, screenKey: String)] = []
        bindings.deferEvaluation {
            self.screens = screens
            if store.value(DependencyPath("shell", [])) != .record(shell) {
                store.set(DependencyPath("shell", []), .record(shell))
            }
            if old.id != ir.id {
                vars.switchConfig(ir.vars, persisted: persisted, shell: shell, writer: writer)
            } else {
                vars.declare(ir.vars, persisted: persisted, shell: shell)
            }
            config = ir
            if old.events != ir.events || old.binds != ir.binds {
                let staleConfig = configTokens
                let staleAwake = awakeTokens
                configTokens.removeAll()
                awakeTokens.removeAll()
                registerConfigDemand(ir)
                staleConfig.forEach(store.unsubscribe)
                staleAwake.forEach(providers.unsubscribe)
            }
            definesChanged = old.defines != ir.defines
            reloading = true
            withSession {
                var desired: [(key: String, ir: SurfaceIR, screen: String)] = []
                for surfaceIR in ir.surfaces {
                    for screen in targetScreens(surfaceIR) {
                        desired.append((surfaceIR.id + "@" + screen, surfaceIR, screen))
                    }
                }
                let wanted = Set(desired.map(\.key))
                for key in surfaceOrder where !wanted.contains(key) {
                    if let node = surfaceNodes[key] {
                        removed.append((node.instance.id, node.instance.screenKey))
                        teardownSurface(node, notify: false)
                    }
                }
                for entry in desired {
                    if let node = surfaceNodes[entry.key] {
                        if node.kind != entry.ir.kind {
                            teardownSurface(node, notify: false)
                            replaced.append(buildSurface(entry.ir, screen: entry.screen))
                        } else if reconcileSurface(node, entry.ir), changedIDs.contains(entry.ir.id) {
                            changed.append(node)
                        }
                    } else {
                        added.append(buildSurface(entry.ir, screen: entry.screen))
                    }
                }
                surfaceOrder = desired.map(\.key).filter { surfaceNodes[$0] != nil }
            }
            reloading = false
            definesChanged = false
        }
        for entry in removed where surfaceNodes[entry.id + "@" + entry.screenKey] == nil {
            host.surfaceRemoved(id: entry.id, screenKey: entry.screenKey)
        }
        for node in replaced where surfaceNodes[node.surfaceKey] === node {
            host.surfaceReplaced(node.instance)
        }
        for node in added where surfaceNodes[node.surfaceKey] === node {
            host.surfaceAdded(node.instance)
        }
        for node in changed where surfaceNodes[node.surfaceKey] === node {
            host.surfaceChanged(node.instance)
        }
    }

    public func setScreens(_ screenKeys: [String]) {
        screens = screenKeys
        guard let config else { return }
        var desired: [(key: String, ir: SurfaceIR, screen: String)] = []
        for surfaceIR in config.surfaces {
            for screen in targetScreens(surfaceIR) {
                desired.append((surfaceIR.id + "@" + screen, surfaceIR, screen))
            }
        }
        let wanted = Set(desired.map(\.key))
        for key in surfaceOrder where !wanted.contains(key) {
            if let node = surfaceNodes[key] {
                teardownSurface(node)
            }
        }
        var added: [SurfaceNode] = []
        withSession {
            for entry in desired where surfaceNodes[entry.key] == nil {
                added.append(buildSurface(entry.ir, screen: entry.screen))
            }
        }
        surfaceOrder = desired.map(\.key).filter { surfaceNodes[$0] != nil }
        for node in added {
            host.surfaceAdded(node.instance)
        }
    }

    public func open(_ surfaceID: String, screenKey: String?) {
        let candidates = nodes(for: surfaceID)
        guard !candidates.isEmpty else {
            warn(key: "unknown-surface|" + surfaceID, Diagnostic(.warning, "unknown surface '\(surfaceID)'"))
            return
        }
        let preferred = screenKey ?? preferredScreen?() ?? screens.first
        let target = candidates.first { $0.instance.screenKey == preferred } ?? candidates[0]
        guard !target.instance.isOpen else { return }
        if let group = groupName(target) {
            for key in surfaceOrder {
                guard let other = surfaceNodes[key], other.instance.id != surfaceID, groupName(other) == group else { continue }
                closeNode(other)
            }
        }
        target.instance.isOpen = true
        target.isClosing = false
        resumeWaiters(target)
        publishSurface(target)
        updateVisibility(target)
        host.surfaceChanged(target.instance)
        runSurfaceHandlers(target, "on-open")
    }

    public func close(_ surfaceID: String) {
        let candidates = nodes(for: surfaceID)
        guard !candidates.isEmpty else {
            warn(key: "unknown-surface|" + surfaceID, Diagnostic(.warning, "unknown surface '\(surfaceID)'"))
            return
        }
        for node in candidates {
            closeNode(node)
        }
    }

    public func close(_ surfaceID: String, screenKey: String) {
        guard let node = surfaceNodes[surfaceID + "@" + screenKey] else { return }
        closeNode(node)
    }

    public func closeAndWait(_ surfaceID: String) async {
        let targets = nodes(for: surfaceID).filter { $0.instance.isOpen }
        close(surfaceID)
        for target in targets where target.isClosing {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let waiter = CloseWaiter(continuation)
                target.closeWaiters.append(waiter)
                waiter.work = actions.clock.schedule(after: RuntimeLimits.closeFeedbackTimeout) { [weak self, weak waiter] in
                    guard let waiter, !waiter.resumed else { return }
                    self?.warn(key: "close-feedback|" + surfaceID, Diagnostic(.warning, "surface '\(surfaceID)' did not report the end of closing"))
                    waiter.resume()
                }
            }
        }
    }

    public func toggle(_ surfaceID: String) {
        if nodes(for: surfaceID).contains(where: { $0.instance.isOpen }) {
            close(surfaceID)
        } else {
            open(surfaceID, screenKey: nil)
        }
    }

    public func closeGroup(_ group: String) {
        for key in surfaceOrder {
            guard let node = surfaceNodes[key], groupName(node) == group else { continue }
            closeNode(node)
        }
    }

    public func surfaceDidFinishClosing(id: String, screenKey: String) {
        guard let node = surfaceNodes[id + "@" + screenKey] else { return }
        node.isClosing = false
        publishSurface(node)
        resumeWaiters(node)
        runSurfaceHandlers(node, "on-closed")
    }

    public func setHiddenByFullscreen(_ hidden: Bool, screenKey: String) {
        for key in surfaceOrder {
            guard let node = surfaceNodes[key], node.instance.screenKey == screenKey, node.hiddenByFullscreen != hidden else { continue }
            node.hiddenByFullscreen = hidden
            if updateVisibility(node) {
                host.surfaceChanged(node.instance)
            }
        }
    }

    @discardableResult
    public func emit(_ event: String, _ fields: Record) -> [Task<Void, Never>] {
        guard let config else { return [] }
        var tasks: [Task<Void, Never>] = []
        for (index, handler) in config.events.enumerated() where handler.event == event {
            if let when = handler.when, !bindings.evaluateOnce(when, scope: LocalScope(), event: fields).isTruthy {
                continue
            }
            if let task = actions.trigger(handler.actions, site: "on#\(index)", environment: ActionEnvironment(event: fields)) {
                tasks.append(task)
            }
        }
        return tasks
    }

    @discardableResult
    public func triggerBind(_ id: String, event: Record) -> Task<Void, Never>? {
        guard let bind = config?.binds.first(where: { $0.id == id }) else {
            warn(key: "unknown-bind|" + id, Diagnostic(.warning, "no bind '\(id)'"))
            return nil
        }
        if let when = bind.when, !bindings.evaluateOnce(when, scope: LocalScope(), event: event).isTruthy {
            return nil
        }
        return actions.trigger(bind.actions, site: "bind#" + id, environment: ActionEnvironment(event: event))
    }

    @discardableResult
    public func trigger(_ handler: String, on identity: Identity, event: Record) -> Task<Void, Never>? {
        if identity.components.count == 1, let node = surfaceNodes[identity.components[0]] {
            return runHandlers(node.instance.ir.handlers, named: handler, scope: node.scope, surface: node, site: identity.description, event: event)
        }
        guard let element = elements[identity], !element.isDead else {
            warn(key: "unknown-element|" + identity.description, Diagnostic(.warning, "no element '\(identity.description)' for \(handler)"))
            return nil
        }
        return runHandlers(element.instance.ir.handlers, named: handler, scope: element.instance.scope, surface: element.surface, site: identity.description, event: event)
    }

    @discardableResult
    public func run(_ list: [ActionIR], on identity: Identity, site: String, event: Record, locals: [String: Value] = [:]) -> Task<Void, Never>? {
        guard let (scope, surface) = context(of: identity) else { return nil }
        let environment = ActionEnvironment(scope: Self.extend(scope, locals), surfaceID: surface.instance.id, screenKey: surface.instance.screenKey, event: event)
        return actions.trigger(list, site: "\(identity.description)#\(site)", environment: environment)
    }

    public func evaluate(_ value: CompiledValue, on identity: Identity, locals: [String: Value] = [:], event: Record? = nil) -> Value {
        let scope = context(of: identity)?.0 ?? LocalScope()
        return bindings.evaluateOnce(value, scope: Self.extend(scope, locals), event: event)
    }

    public func bindChords() -> [(id: String, chord: String)] {
        (config?.binds ?? []).compactMap { bind in
            guard case .string(let chord) = bindings.evaluateOnce(bind.chord, scope: LocalScope()), !chord.isEmpty else { return nil }
            return (bind.id, chord)
        }
    }

    private func context(of identity: Identity) -> (LocalScope, SurfaceNode)? {
        if identity.components.count == 1, let node = surfaceNodes[identity.components[0]] {
            return (node.scope, node)
        }
        guard let element = elements[identity], !element.isDead else { return nil }
        return (element.instance.scope, element.surface)
    }

    private static func extend(_ scope: LocalScope, _ locals: [String: Value]) -> LocalScope {
        locals.keys.sorted().reduce(scope) { $0.adding($1, locals[$1] ?? .null) }
    }

    private func runHandlers(_ handlers: [HandlerIR], named name: String, scope: LocalScope, surface: SurfaceNode, site: String, event: Record) -> Task<Void, Never>? {
        var last: Task<Void, Never>?
        for (index, handler) in handlers.enumerated() where handler.name == name {
            let environment = ActionEnvironment(scope: scope, surfaceID: surface.instance.id, screenKey: surface.instance.screenKey, event: event)
            if let task = actions.trigger(handler.actions, site: "\(site)#\(name)#\(index)", environment: environment) {
                last = task
            }
        }
        return last
    }

    private func runSurfaceHandlers(_ node: SurfaceNode, _ name: String) {
        guard node.instance.ir.handlers.contains(where: { $0.name == name }) else { return }
        _ = runHandlers(node.instance.ir.handlers, named: name, scope: node.scope, surface: node, site: node.identity.description, event: Record())
    }

    func warn(key: String, _ diagnostic: Diagnostic) {
        guard warned.insert(key).inserted else { return }
        onWarning?(diagnostic)
    }

    private func nodes(for surfaceID: String) -> [SurfaceNode] {
        surfaceOrder.compactMap { surfaceNodes[$0] }.filter { $0.instance.id == surfaceID }
    }

    private func groupName(_ node: SurfaceNode) -> String? {
        if case .string(let group) = node.instance.property("group"), !group.isEmpty {
            return group
        }
        return nil
    }

    private func closeNode(_ node: SurfaceNode) {
        guard node.instance.isOpen else { return }
        node.instance.isOpen = false
        node.isClosing = true
        publishSurface(node)
        updateVisibility(node)
        host.surfaceChanged(node.instance)
        runSurfaceHandlers(node, "on-close")
    }

    private func resumeWaiters(_ node: SurfaceNode) {
        let waiters = node.closeWaiters
        node.closeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func registerConfigDemand(_ ir: ConfigIR) {
        for handler in ir.events {
            if let when = handler.when, !when.dependencies.isEmpty {
                configTokens.append(store.demand(when.dependencies))
            }
            if let dot = handler.event.firstIndex(of: ".") {
                awakeTokens.append(providers.keepAwake(String(handler.event[..<dot])))
            }
        }
        for bind in ir.binds {
            if let when = bind.when, !when.dependencies.isEmpty {
                configTokens.append(store.demand(when.dependencies))
            }
        }
    }

    private func teardownAll() {
        for key in surfaceOrder {
            if let node = surfaceNodes[key] {
                teardownSurface(node)
            }
        }
        releaseConfigDemand()
        config = nil
    }

    private func releaseConfigDemand() {
        for token in configTokens {
            store.unsubscribe(token)
        }
        configTokens.removeAll()
        for token in awakeTokens {
            providers.unsubscribe(token)
        }
        awakeTokens.removeAll()
    }

    func teardownSurface(_ node: SurfaceNode, notify: Bool = true) {
        if let root = node.root {
            teardown(root.region.parts)
            root.region.parts.removeAll()
            root.region.context = nil
        }
        node.root = nil
        for handle in node.propertyBindings.values {
            handle.cancel()
        }
        node.propertyBindings.removeAll()
        resumeWaiters(node)
        store.removeRoot("surface:" + node.surfaceKey)
        store.remove(DependencyPath("surfaces:" + node.instance.screenKey, [node.instance.id]))
        surfaceNodes[node.surfaceKey] = nil
        surfaceOrder.removeAll { $0 == node.surfaceKey }
        if notify {
            host.surfaceRemoved(id: node.instance.id, screenKey: node.instance.screenKey)
        }
    }

    func targetScreens(_ surfaceIR: SurfaceIR) -> [String] {
        guard let main = screens.first else { return [] }
        var choice = surfaceIR.kind == "panel" ? "all" : "pointer"
        if let compiled = surfaceIR.properties["screen"], case .string(let text) = bindings.evaluateOnce(compiled, scope: LocalScope()), !text.isEmpty {
            choice = text
        }
        switch choice {
        case "all", "pointer":
            return screens
        case "main":
            return [main]
        default:
            return screens.contains(choice) ? [choice] : [main]
        }
    }

    private static func opensByDefault(_ kind: String) -> Bool {
        kind == "panel" || kind == "overlay"
    }

    func buildSurface(_ ir: SurfaceIR, screen: String) -> SurfaceNode {
        let instance = SurfaceInstance(id: ir.id, screenKey: screen, ir: ir, isOpen: Self.opensByDefault(ir.kind))
        let node = SurfaceNode(instance: instance)
        surfaceNodes[node.surfaceKey] = node
        surfaceOrder.append(node.surfaceKey)
        surfacesBuilt += 1
        publishSurface(node)
        var cells: [String: PropertyCell] = [:]
        for name in ir.properties.keys.sorted() {
            guard let compiled = ir.properties[name] else { continue }
            let cell = PropertyCell(.null)
            cells[name] = cell
            node.propertyBindings[name] = bindSurfaceProperty(node, name, compiled, cell)
        }
        instance.properties = cells
        instance.isVisible = computeVisible(node)
        let root = Container { [weak instance] list in
            guard let instance, !Self.same(instance.root, list) else { return }
            instance.root = list
        }
        node.root = root
        buildParts(root.region, surfaceChildren(ir), rootContext(node, root))
        node.isConfigured = true
        return node
    }

    func rootContext(_ node: SurfaceNode, _ root: Container) -> BuildContext {
        BuildContext(surface: node, scope: node.scope, path: node.identity, depth: 0, useDepth: 0, active: node.instance.isVisible, container: root)
    }

    func bindSurfaceProperty(_ node: SurfaceNode, _ name: String, _ compiled: CompiledValue, _ cell: PropertyCell) -> BindingHandle {
        let isVisibility = name == "visible"
        return bindings.bind(compiled, scope: node.scope, rank: isVisibility ? .structure(depth: -1) : .property, active: true) { [weak self, weak node, weak cell] value in
            cell?.update(value)
            guard isVisibility, let self, let node else { return }
            node.visibleProperty = value.isTruthy
            if node.isConfigured, self.updateVisibility(node) {
                self.host.surfaceChanged(node.instance)
            }
        }
    }

    private func computeVisible(_ node: SurfaceNode) -> Bool {
        let hidden = node.hiddenByFullscreen && fullscreenHides(node)
        switch node.kind {
        case "panel":
            return node.visibleProperty && !hidden
        case "toast", "osd":
            return node.instance.isOpen && !hidden
        default:
            return node.instance.isOpen && node.visibleProperty && !hidden
        }
    }

    private func fullscreenHides(_ node: SurfaceNode) -> Bool {
        switch node.instance.property("fullscreen") {
        case .string("hide"): true
        case .string("show"): false
        default: node.kind == "panel"
        }
    }

    @discardableResult
    func updateVisibility(_ node: SurfaceNode) -> Bool {
        guard node.isConfigured else { return false }
        let visible = computeVisible(node)
        guard visible != node.instance.isVisible else { return false }
        node.instance.isVisible = visible
        withSession {
            propagate(node.root?.region.parts ?? [], active: visible)
        }
        return true
    }

    public func setToasts(_ surfaceID: String, screenKey: String, _ toasts: [Value]) {
        guard let node = surfaceNodes[surfaceID + "@" + screenKey], node.kind == "toast", node.toasts != toasts else { return }
        node.toasts = toasts
        publishSurface(node)
    }

    func surfaceChildren(_ ir: SurfaceIR) -> [ChildIR] {
        guard ir.kind == "toast" else { return ir.children }
        return [.each(EachIR(key: "toast-stack", variable: "toast", list: Self.toastList, itemKey: Self.toastKey, body: ir.children))]
    }

    private static let toastList = compiledInternal("{surface.toasts}")
    private static let toastKey = compiledInternal("{toast.id}", locals: ["toast"])

    private static func compiledInternal(_ text: String, locals: Set<String> = []) -> CompiledValue {
        let span = SourceSpan.synthetic("<toast>")
        guard case .success(let template) = ExpressionParser.parseTemplate(text, span: span) else {
            return CompiledValue(template: .literal(""), dependencies: [], span: span)
        }
        return CompiledValue(template: template, dependencies: template.dependencies(locals: locals), span: span)
    }

    private func publishSurface(_ node: SurfaceNode) {
        let instance = node.instance
        var fields: [(String, Value)] = [
            ("id", .string(instance.id)),
            ("open", .bool(instance.isOpen)),
            ("opening", .bool(false)),
            ("closing", .bool(node.isClosing)),
        ]
        if node.kind == "toast" { fields.append(("toasts", .list(node.toasts))) }
        store.set(DependencyPath("surface:" + node.surfaceKey, []), .record(Record(fields)))
        store.set(DependencyPath("surfaces:" + instance.screenKey, [instance.id, "open"]), .bool(instance.isOpen))
        let entry = DependencyPath("surfaces:" + instance.screenKey, [instance.id])
        if case .record(var record) = store.value(entry), record["width"] == nil || record["height"] == nil {
            for field in ["width", "height"] where record[field] == nil {
                record[field] = .null
            }
            store.set(entry, .record(record))
        }
    }

    static func same(_ lhs: [ElementInstance], _ rhs: [ElementInstance]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for index in lhs.indices where lhs[index] !== rhs[index] {
            return false
        }
        return true
    }

    func withSession(_ body: () -> Void) {
        if inSession {
            body()
            return
        }
        inSession = true
        generation += 1
        body()
        var head = 0
        while true {
            while head < queue.count {
                let work = queue[head]
                head += 1
                work()
            }
            guard !pendingTeardown.isEmpty else { break }
            let pending = pendingTeardown
            pendingTeardown.removeAll()
            teardown(pending.filter(\.isParked))
        }
        queue.removeAll()
        inSession = false
        let containers = dirtyContainers.values
        dirtyContainers.removeAll()
        for container in containers {
            container.refresh()
        }
    }

    func enqueue(_ work: @escaping @MainActor () -> Void) {
        if inSession {
            queue.append(work)
        } else {
            withSession {
                queue.append(work)
            }
        }
    }

    func markDirty(_ container: Container) {
        dirtyContainers[ObjectIdentifier(container)] = container
    }

    func buildParts(_ region: Region, _ children: [ChildIR], _ context: BuildContext) {
        region.context = context
        for child in children {
            let part: TreeNode?
            if case .element(let ir) = child {
                part = placeElement(ir, context, reuse: nil)
            } else if let kind = StructureNode.Kind(child) {
                part = makeStructure(kind, context)
            } else {
                part = nil
            }
            if let part {
                part.region = region
                region.parts.append(part)
            }
        }
        markDirty(context.container)
    }

    func placeElement(_ ir: ElementIR, _ context: BuildContext, reuse positional: [String: TreeNode]?) -> ElementNode? {
        let surface = context.surface
        guard context.depth < RuntimeLimits.elementDepth else {
            warn(key: "depth|\(ir.span)", Diagnostic(.warning, "elements nested deeper than \(RuntimeLimits.elementDepth) levels are not built", span: ir.span))
            return nil
        }
        var runtimeID: String?
        if let template = ir.idTemplate, let text = Self.idText(bindings.evaluateOnce(template, scope: context.scope)) {
            if let existing = surface.ids[text], !existing.isDead {
                if existing.stamp != generation, reloading || existing.isParked {
                    if existing.instance.kind == ir.kind {
                        adopt(existing)
                        reconcileElement(existing, ir, context)
                        return existing
                    }
                    surface.ids[text] = nil
                    runtimeID = text
                } else {
                    warn(key: "duplicate-id|\(template.span)|\(text)", Diagnostic(.warning, "duplicate id '\(text)' in surface '\(surface.instance.id)', the later element loses it", span: template.span))
                }
            } else {
                runtimeID = text
            }
        }
        if runtimeID == nil, let existing = positional?["e|" + ir.key] as? ElementNode, existing.runtimeID == nil, existing.stamp != generation, !existing.isDead, existing.instance.kind == ir.kind {
            reconcileElement(existing, ir, context)
            return existing
        }
        return buildElement(ir, context, runtimeID: runtimeID)
    }

    private func buildElement(_ ir: ElementIR, _ context: BuildContext, runtimeID: String?) -> ElementNode? {
        let surface = context.surface
        guard surface.elementCount < RuntimeLimits.elementsPerSurface else {
            if !surface.budgetWarned {
                surface.budgetWarned = true
                warn(key: "budget|" + surface.surfaceKey, Diagnostic(.warning, "surface '\(surface.instance.id)' reached \(RuntimeLimits.elementsPerSurface) elements, further elements are not built", span: ir.span))
            }
            return nil
        }
        let identity = runtimeID.map { surface.identity.appending("#" + $0) } ?? context.path.appending(ir.key)
        let scope = context.scope.adding(ContextScopeKeys.selfIdentity, .string(identity.description))
        let instance = ElementInstance(identity: identity, kind: ir.kind, ir: ir, scope: scope)
        instance.entryKey = context.entryKey
        let node = ElementNode(instance: instance, surface: surface, runtimeID: runtimeID, context: context)
        node.stamp = generation
        if let runtimeID {
            surface.ids[runtimeID] = node
        }
        elements[identity] = node
        surface.elementCount += 1
        elementsBuilt += 1

        var cells: [String: PropertyCell] = [:]
        if let visible = ir.properties["visible"] {
            let cell = PropertyCell(.null)
            cells["visible"] = cell
            node.visibleBinding = bindVisible(node, visible, cell)
        }
        for name in ir.properties.keys.sorted() where name != "visible" {
            guard let compiled = ir.properties[name] else { continue }
            if name == "id" {
                cells[name] = PropertyCell(runtimeID.map { .string($0) } ?? .null)
                continue
            }
            let cell = PropertyCell(.null)
            cells[name] = cell
            node.cellBindings[name] = fill(cell, compiled, node: node)
        }
        instance.properties = cells
        var arguments: [PropertyCell] = []
        for (index, compiled) in ir.arguments.enumerated() {
            let cell = PropertyCell(.null)
            arguments.append(cell)
            node.argumentBindings[index] = fill(cell, compiled, node: node)
        }
        instance.arguments = arguments

        let selfRoot = "self:" + identity.description
        instance.onPseudoChange = { [weak self] state in
            self?.publishPseudo(selfRoot, state)
        }

        let childContainer = makeChildContainer(instance)
        node.childContainer = childContainer
        let childContext = node.childContext(childContainer, path: identity)
        childContainer.region.context = childContext
        scheduleBuild(node, ir.children, childContext)
        for name in ir.slots.keys.sorted() {
            addSlot(node, name, ir.slots[name] ?? [])
        }
        node.isConfigured = true
        return node
    }

    func makeChildContainer(_ instance: ElementInstance) -> Container {
        Container { [weak instance] list in
            guard let instance, !Self.same(instance.children, list) else { return }
            instance.children = list
        }
    }

    func addSlot(_ node: ElementNode, _ name: String, _ children: [ChildIR]) {
        let slotContainer = Container { [weak instance = node.instance] list in
            guard let instance else { return }
            if let existing = instance.slotChildren[name], Self.same(existing, list) { return }
            instance.slotChildren[name] = list
        }
        node.slotContainers[name] = slotContainer
        let slotContext = node.childContext(slotContainer, path: node.instance.identity.appending("slot:" + name))
        slotContainer.region.context = slotContext
        scheduleBuild(node, children, slotContext)
    }

    func bindVisible(_ node: ElementNode, _ compiled: CompiledValue, _ cell: PropertyCell) -> BindingHandle {
        bindings.bind(compiled, scope: node.instance.scope, rank: .structure(depth: node.depth), active: node.outerActive) { [weak self, weak node, weak cell] value in
            cell?.update(value)
            guard let self, let node else { return }
            self.setSelfVisible(node, value.isTruthy)
        }
    }

    func fill(_ cell: PropertyCell, _ compiled: CompiledValue, node: ElementNode) -> BindingHandle? {
        if BindingSource(compiled: compiled).isLiteral {
            cell.update(bindings.evaluateOnce(compiled, scope: node.instance.scope))
            return nil
        }
        return bindings.bind(compiled, scope: node.instance.scope, rank: .property, active: node.innerActive) { [weak cell] value in
            cell?.update(value)
        }
    }

    private func scheduleBuild(_ node: ElementNode, _ children: [ChildIR], _ context: BuildContext) {
        guard !children.isEmpty else { return }
        enqueue { [weak self, weak node] in
            guard let self, let node, !node.isDead else { return }
            var current = context
            current.active = node.innerActive
            current.scope = node.instance.scope
            self.buildParts(context.container.region, children, current)
        }
    }

    private func publishPseudo(_ root: String, _ state: PseudoState) {
        store.set(DependencyPath(root, ["hover"]), .bool(state.contains(.hover)))
        store.set(DependencyPath(root, ["pressed"]), .bool(state.contains(.active)))
        store.set(DependencyPath(root, ["focused"]), .bool(state.contains(.focus)))
    }

    func setSelfVisible(_ node: ElementNode, _ visible: Bool) {
        guard node.selfVisible != visible else { return }
        node.selfVisible = visible
        guard node.isConfigured, propagating == 0, !node.isDead else { return }
        withSession {
            let inner = node.innerActive
            propagating += 1
            for handle in node.innerBindings {
                handle.isActive = inner
            }
            propagating -= 1
            propagate(node.childParts, active: inner)
        }
    }

    func propagate(_ parts: [TreeNode], active: Bool) {
        propagating += 1
        defer { propagating -= 1 }
        var stack = parts.map { ($0, active) }
        while let (node, active) = stack.popLast() {
            guard !node.isDead else { continue }
            if let element = node as? ElementNode {
                element.outerActive = active
                element.visibleBinding?.isActive = active
                let inner = element.innerActive
                for handle in element.innerBindings {
                    handle.isActive = inner
                }
                for part in element.childParts {
                    stack.append((part, inner))
                }
            } else if let structure = node as? StructureNode {
                structure.outerActive = active
                structure.context.active = active
                for handle in structure.allBindings {
                    handle.isActive = active
                }
                for region in structure.regions {
                    for part in region.parts {
                        stack.append((part, active))
                    }
                }
            }
        }
    }

    func park(_ parts: [TreeNode]) {
        guard let first = parts.first else { return }
        guard inSession else {
            teardown(parts)
            return
        }
        for part in parts {
            part.isParked = true
        }
        pendingTeardown.append(contentsOf: parts)
        guard let surface = first.surfaceNode, !surface.ids.isEmpty else { return }
        var stack = parts
        while let node = stack.popLast() {
            if let element = node as? ElementNode, element.runtimeID != nil {
                element.isParked = true
            }
            for region in node.innerRegions {
                stack.append(contentsOf: region.parts)
            }
        }
    }

    func adopt(_ node: ElementNode) {
        node.stamp = generation
        node.isParked = false
        if let region = node.region, let position = region.parts.firstIndex(where: { $0 === node }) {
            region.parts.remove(at: position)
            if let container = region.context?.container {
                markDirty(container)
            }
        }
        guard !node.surface.ids.isEmpty else { return }
        var stack = node.childParts
        while let part = stack.popLast() {
            part.isParked = false
            for region in part.innerRegions {
                stack.append(contentsOf: region.parts)
            }
        }
    }

    func applyScope(_ start: [(TreeNode, LocalScope)]) {
        var stack = start
        while let (part, scope) = stack.popLast() {
            guard !part.isDead else { continue }
            if let element = part as? ElementNode {
                let own = scope.adding(ContextScopeKeys.selfIdentity, .string(element.instance.identity.description))
                guard own != element.instance.scope else { continue }
                element.instance.scope = own
                for handle in element.allBindings {
                    handle.updateScope(own)
                }
                for region in element.childRegions {
                    region.context?.scope = own
                    for child in region.parts {
                        stack.append((child, own))
                    }
                }
            } else if let structure = part as? StructureNode {
                guard structure.context.scope != scope else { continue }
                structure.context.scope = scope
                for handle in structure.allBindings {
                    handle.updateScope(scope)
                }
                for region in structure.regions {
                    let inner = regionScope(structure, region)
                    region.context?.scope = inner
                    for child in region.parts {
                        stack.append((child, inner))
                    }
                }
                for slot in structure.slotNodes where !slot.isDead && slot.context.slotOwner === structure {
                    for region in slot.regions {
                        region.context?.scope = scope
                        for child in region.parts {
                            stack.append((child, scope))
                        }
                    }
                }
            }
        }
    }

    func teardown(_ parts: [TreeNode]) {
        var stack = parts
        while let node = stack.popLast() {
            guard !node.isDead else { continue }
            node.isDead = true
            node.isParked = false
            if let element = node as? ElementNode {
                for handle in element.allBindings {
                    handle.cancel()
                }
                element.visibleBinding = nil
                element.cellBindings.removeAll()
                element.argumentBindings.removeAll()
                element.instance.onPseudoChange = nil
                let identity = element.instance.identity
                store.removeRoot("self:" + identity.description)
                if let id = element.runtimeID, element.surface.ids[id] === element {
                    element.surface.ids[id] = nil
                }
                if elements[identity] === element {
                    elements[identity] = nil
                }
                element.surface.elementCount -= 1
                for region in element.childRegions {
                    stack.append(contentsOf: region.parts)
                    region.parts.removeAll()
                    region.context = nil
                }
                element.childContainer = nil
                element.slotContainers.removeAll()
            } else if let structure = node as? StructureNode {
                for handle in structure.allBindings {
                    handle.cancel()
                }
                for region in structure.regions {
                    stack.append(contentsOf: region.parts)
                    region.parts.removeAll()
                    region.context = nil
                }
                structure.regions.removeAll()
                structure.slotNodes.removeAll()
            }
        }
    }

    nonisolated static func identical(_ lhs: Value, _ rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.number(let left), .number(let right)):
            return left.bitPattern == right.bitPattern
        case (.string(let left), .string(let right)):
            return sameBytes(left, right)
        case (.record(let left), .record(let right)):
            return sameBytes(left, right)
        case (.list(let left), .list(let right)):
            return left.count == right.count && left.withUnsafeBufferPointer { a in right.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress } }
        default:
            return false
        }
    }

    private nonisolated static func sameBytes<T>(_ lhs: T, _ rhs: T) -> Bool {
        withUnsafeBytes(of: lhs) { left in
            withUnsafeBytes(of: rhs) { right in
                left.elementsEqual(right)
            }
        }
    }

    static func idText(_ value: Value) -> String? {
        switch value {
        case .string(let text) where !text.isEmpty: text
        case .number(let number) where number.isFinite && number == number.rounded() && abs(number) < 1e15: String(Int(number))
        default: nil
        }
    }
}
