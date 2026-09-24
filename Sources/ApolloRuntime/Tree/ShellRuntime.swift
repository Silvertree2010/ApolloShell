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

    public var onWarning: (@MainActor (Diagnostic) -> Void)?

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
            self?.emit(event, fields)
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

    public func apply(_ ir: ConfigIR, persisted: [String: Value], screens: [String], shell: Record) {
        teardownAll()
        warned.removeAll()
        config = ir
        self.screens = screens
        store.set(DependencyPath("shell", []), .record(shell))
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
        let preferred = screenKey ?? screens.first
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

    public func emit(_ event: String, _ fields: Record) {
        guard let config else { return }
        for (index, handler) in config.events.enumerated() where handler.event == event {
            if let when = handler.when, !bindings.evaluateOnce(when, scope: LocalScope(), event: fields).isTruthy {
                continue
            }
            actions.trigger(handler.actions, site: "on#\(index)", environment: ActionEnvironment(event: fields))
        }
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

    private func runHandlers(_ handlers: [HandlerIR], named name: String, scope: LocalScope, surface: SurfaceNode, site: String, event: Record) -> Task<Void, Never>? {
        var last: Task<Void, Never>?
        for (index, handler) in handlers.enumerated() where handler.name == name {
            if let when = handler.properties["when"], !bindings.evaluateOnce(when, scope: scope, event: event).isTruthy {
                continue
            }
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

    private func registerConfigDemand(_ ir: ConfigIR) {
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
        for token in configTokens {
            store.unsubscribe(token)
        }
        configTokens.removeAll()
        for token in awakeTokens {
            providers.unsubscribe(token)
        }
        awakeTokens.removeAll()
        config = nil
    }

    private func teardownSurface(_ node: SurfaceNode) {
        if let root = node.root {
            teardown(root.region.parts)
            root.region.parts.removeAll()
        }
        node.root = nil
        for handle in node.propertyBindings {
            handle.cancel()
        }
        node.propertyBindings.removeAll()
        resumeWaiters(node)
        store.removeRoot("surface:" + node.surfaceKey)
        store.remove(DependencyPath("surfaces:" + node.instance.screenKey, [node.instance.id]))
        surfaceNodes[node.surfaceKey] = nil
        surfaceOrder.removeAll { $0 == node.surfaceKey }
        host.surfaceRemoved(id: node.instance.id, screenKey: node.instance.screenKey)
    }

    private func targetScreens(_ surfaceIR: SurfaceIR) -> [String] {
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

    private func buildSurface(_ ir: SurfaceIR, screen: String) -> SurfaceNode {
        let instance = SurfaceInstance(id: ir.id, screenKey: screen, ir: ir, isOpen: Self.opensByDefault(ir.kind))
        let node = SurfaceNode(instance: instance)
        surfaceNodes[node.surfaceKey] = node
        surfaceOrder.append(node.surfaceKey)
        surfacesBuilt += 1
        publishSurface(node)
        let scope = node.scope
        var cells: [String: PropertyCell] = [:]
        for name in ir.properties.keys.sorted() {
            guard let compiled = ir.properties[name] else { continue }
            let cell = PropertyCell(.null)
            cells[name] = cell
            let isVisibility = name == "visible"
            let handle = bindings.bind(compiled, scope: scope, rank: isVisibility ? .structure(depth: -1) : .property, active: true) { [weak self, weak node, weak cell] value in
                cell?.update(value)
                guard isVisibility, let self, let node else { return }
                node.visibleProperty = value.isTruthy
                if node.isConfigured, self.updateVisibility(node) {
                    self.host.surfaceChanged(node.instance)
                }
            }
            node.propertyBindings.append(handle)
        }
        instance.properties = cells
        instance.isVisible = computeVisible(node)
        let root = Container { [weak instance] list in
            guard let instance, !Self.same(instance.root, list) else { return }
            instance.root = list
        }
        node.root = root
        let context = BuildContext(surface: node, scope: scope, path: node.identity, depth: 0, useDepth: 0, active: instance.isVisible, container: root)
        buildParts(root.region, ir.children, context)
        node.isConfigured = true
        return node
    }

    private func computeVisible(_ node: SurfaceNode) -> Bool {
        let hidden = node.hiddenByFullscreen && fullscreenHides(node)
        switch node.kind {
        case "panel":
            return node.visibleProperty && !hidden
        case "toast", "osd":
            return node.instance.isOpen
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
    private func updateVisibility(_ node: SurfaceNode) -> Bool {
        guard node.isConfigured else { return false }
        let visible = computeVisible(node)
        guard visible != node.instance.isVisible else { return false }
        node.instance.isVisible = visible
        withSession {
            propagate(node.root?.region.parts ?? [], active: visible)
        }
        return true
    }

    private func publishSurface(_ node: SurfaceNode) {
        let instance = node.instance
        store.set(DependencyPath("surface:" + node.surfaceKey, []), .record(Record([
            ("id", .string(instance.id)),
            ("open", .bool(instance.isOpen)),
            ("opening", .bool(false)),
            ("closing", .bool(node.isClosing)),
        ])))
        store.set(DependencyPath("surfaces:" + instance.screenKey, [instance.id, "open"]), .bool(instance.isOpen))
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
        body()
        var head = 0
        while head < queue.count {
            let work = queue[head]
            head += 1
            work()
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
        for child in children {
            switch child {
            case .element(let ir):
                if let node = makeElement(ir, context) {
                    region.parts.append(node)
                }
            case .each(let each):
                region.parts.append(makeStructure(.each(each), context))
            case .when(let when):
                region.parts.append(makeStructure(.when(when), context))
            case .switchOn(let switchIR):
                region.parts.append(makeStructure(.switchOn(switchIR), context))
            case .dynamicUse(let use):
                region.parts.append(makeStructure(.use(use), context))
            }
        }
        markDirty(context.container)
    }

    private func makeElement(_ ir: ElementIR, _ context: BuildContext) -> ElementNode? {
        let surface = context.surface
        guard context.depth < RuntimeLimits.elementDepth else {
            warn(key: "depth|\(ir.span)", Diagnostic(.warning, "elements nested deeper than \(RuntimeLimits.elementDepth) levels are not built", span: ir.span))
            return nil
        }
        guard surface.elementCount < RuntimeLimits.elementsPerSurface else {
            warn(key: "budget|" + surface.surfaceKey, Diagnostic(.warning, "surface '\(surface.instance.id)' reached \(RuntimeLimits.elementsPerSurface) elements, further elements are not built", span: ir.span))
            return nil
        }
        var identity = context.path.appending(ir.key)
        var runtimeID: String?
        if let template = ir.idTemplate, let text = Self.idText(bindings.evaluateOnce(template, scope: context.scope)) {
            if surface.ids[text] == nil {
                runtimeID = text
                identity = surface.identity.appending("#" + text)
            } else {
                warn(key: "duplicate-id|\(template.span)|\(text)", Diagnostic(.warning, "duplicate id '\(text)' in surface '\(surface.instance.id)', the later element loses it", span: template.span))
            }
        }
        let scope = context.scope.adding(ContextScopeKeys.selfIdentity, .string(identity.description))
        let instance = ElementInstance(identity: identity, kind: ir.kind, ir: ir, scope: scope)
        let node = ElementNode(instance: instance, surface: surface, runtimeID: runtimeID, outerActive: context.active)
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
            node.visibleBinding = bindings.bind(visible, scope: scope, rank: .structure(depth: context.depth), active: context.active) { [weak self, weak node, weak cell] value in
                cell?.update(value)
                guard let self, let node else { return }
                self.setSelfVisible(node, value.isTruthy)
            }
        }
        for name in ir.properties.keys.sorted() where name != "visible" {
            guard let compiled = ir.properties[name] else { continue }
            if name == "id" {
                cells[name] = PropertyCell(runtimeID.map { .string($0) } ?? .null)
                continue
            }
            cells[name] = makeCell(compiled, scope: scope, node: node)
        }
        instance.properties = cells
        instance.arguments = ir.arguments.map { makeCell($0, scope: scope, node: node) }

        for handler in ir.handlers {
            guard let when = handler.properties["when"], !when.dependencies.isEmpty else { continue }
            node.demandTokens.append(store.demand(Set(when.dependencies.map { rewrittenPath($0, locals: scope) })))
        }
        let selfRoot = "self:" + identity.description
        instance.onPseudoChange = { [weak self] state in
            self?.publishPseudo(selfRoot, state)
        }

        let childContainer = Container { [weak instance] list in
            guard let instance, !Self.same(instance.children, list) else { return }
            instance.children = list
        }
        node.childContainer = childContainer
        let childContext = BuildContext(surface: surface, scope: scope, path: identity, depth: context.depth + 1, useDepth: context.useDepth, active: node.innerActive, container: childContainer)
        scheduleBuild(node, ir.children, childContext)
        for name in ir.slots.keys.sorted() {
            let slotContainer = Container { [weak instance] list in
                guard let instance else { return }
                if let existing = instance.slotChildren[name], Self.same(existing, list) { return }
                instance.slotChildren[name] = list
            }
            node.slotContainers[name] = slotContainer
            let slotContext = BuildContext(surface: surface, scope: scope, path: identity.appending("slot:" + name), depth: context.depth + 1, useDepth: context.useDepth, active: node.innerActive, container: slotContainer)
            scheduleBuild(node, ir.slots[name] ?? [], slotContext)
        }
        node.isConfigured = true
        return node
    }

    private func scheduleBuild(_ node: ElementNode, _ children: [ChildIR], _ context: BuildContext) {
        guard !children.isEmpty else { return }
        enqueue { [weak self, weak node] in
            guard let self, let node, !node.isDead else { return }
            var current = context
            current.active = node.innerActive
            self.buildParts(context.container.region, children, current)
        }
    }

    private func makeCell(_ compiled: CompiledValue, scope: LocalScope, node: ElementNode) -> PropertyCell {
        if BindingSource(compiled: compiled).isLiteral {
            return PropertyCell(bindings.evaluateOnce(compiled, scope: scope))
        }
        let cell = PropertyCell(.null)
        let handle = bindings.bind(compiled, scope: scope, rank: .property, active: node.innerActive) { [weak cell] value in
            cell?.update(value)
        }
        node.propertyBindings.append(handle)
        return cell
    }

    private func publishPseudo(_ root: String, _ state: PseudoState) {
        store.set(DependencyPath(root, ["hover"]), .bool(state.contains(.hover)))
        store.set(DependencyPath(root, ["pressed"]), .bool(state.contains(.active)))
        store.set(DependencyPath(root, ["focused"]), .bool(state.contains(.focus)))
    }

    private func setSelfVisible(_ node: ElementNode, _ visible: Bool) {
        guard node.selfVisible != visible else { return }
        node.selfVisible = visible
        guard node.isConfigured, propagating == 0, !node.isDead else { return }
        withSession {
            let inner = node.innerActive
            propagating += 1
            for handle in node.propertyBindings {
                handle.isActive = inner
            }
            propagating -= 1
            propagate(node.childParts, active: inner)
        }
    }

    private func propagate(_ parts: [TreeNode], active: Bool) {
        propagating += 1
        defer { propagating -= 1 }
        var stack = parts.map { ($0, active) }
        while let (node, active) = stack.popLast() {
            guard !node.isDead else { continue }
            if let element = node as? ElementNode {
                element.outerActive = active
                element.visibleBinding?.isActive = active
                let inner = element.innerActive
                for handle in element.propertyBindings {
                    handle.isActive = inner
                }
                for part in element.childParts {
                    stack.append((part, inner))
                }
            } else if let structure = node as? StructureNode {
                structure.outerActive = active
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

    func teardown(_ parts: [TreeNode]) {
        var stack = parts
        while let node = stack.popLast() {
            guard !node.isDead else { continue }
            node.isDead = true
            if let element = node as? ElementNode {
                element.visibleBinding?.cancel()
                for handle in element.propertyBindings {
                    handle.cancel()
                }
                for token in element.demandTokens {
                    store.unsubscribe(token)
                }
                element.demandTokens.removeAll()
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
                stack.append(contentsOf: element.childParts)
                element.childContainer?.region.parts.removeAll()
                element.childContainer = nil
                for container in element.slotContainers.values {
                    container.region.parts.removeAll()
                }
                element.slotContainers.removeAll()
            } else if let structure = node as? StructureNode {
                for handle in structure.allBindings {
                    handle.cancel()
                }
                for region in structure.regions {
                    stack.append(contentsOf: region.parts)
                }
                structure.regions.removeAll()
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
