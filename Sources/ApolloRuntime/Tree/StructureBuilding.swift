import ApolloBase
import ApolloConfig

extension ShellRuntime {
    func makeStructure(_ kind: StructureNode.Kind, _ context: BuildContext) -> StructureNode {
        let node = StructureNode(kind: kind, context: context)
        node.stamp = generation
        switch kind {
        case .when(let when):
            node.subject = bindStructure(node, when.condition)
        case .switchOn(let switchIR):
            node.subject = bindStructure(node, switchIR.subject)
            node.caseBindings = switchIR.cases.map { $0.values.map { bindStructure(node, $0) } }
        case .each(let each):
            node.subject = bindStructure(node, each.list)
        case .use(let use):
            node.subject = bindStructure(node, use.name)
            for name in use.arguments.keys.sorted() {
                if let compiled = use.arguments[name] {
                    node.argumentBindings[name] = bindStructure(node, compiled)
                }
            }
        case .slot:
            context.slotOwner?.register(node)
            scheduleRebuild(node)
        }
        return node
    }

    func bindStructure(_ node: StructureNode, _ compiled: CompiledValue) -> BindingHandle {
        bindings.bind(compiled, scope: node.context.scope, rank: .structure(depth: node.context.depth), active: node.outerActive) { [weak self, weak node] _ in
            guard let self, let node else { return }
            self.scheduleRebuild(node)
        }
    }

    func scheduleRebuild(_ node: StructureNode) {
        guard !node.isDead, !node.rebuildQueued else { return }
        node.rebuildQueued = true
        enqueue { [weak self, weak node] in
            guard let self, let node else { return }
            node.rebuildQueued = false
            guard !node.isDead, !node.isParked else { return }
            self.rebuild(node)
        }
    }

    private func rebuild(_ node: StructureNode) {
        var context = node.context
        context.active = node.outerActive
        switch node.kind {
        case .when(let when):
            let truthy = node.subject?.currentValue.isTruthy ?? false
            let selection = truthy ? "then" : "else"
            guard selection != node.selection else { return }
            context.path = context.path.appending(when.key).appending(selection)
            replace(node, selection: selection, bodies: [(truthy ? when.then : when.otherwise, context)])
        case .switchOn(let switchIR):
            let subject = node.subject?.currentValue ?? .null
            let index = node.caseBindings.firstIndex { group in group.contains { $0.currentValue == subject } }
            let selection = index.map { "case\($0)" } ?? "default"
            guard selection != node.selection else { return }
            context.path = context.path.appending(switchIR.key).appending(selection)
            replace(node, selection: selection, bodies: [(index.map { switchIR.cases[$0].body } ?? switchIR.otherwise, context)])
        case .each(let each):
            rebuildEach(node, each, context)
        case .use(let use):
            rebuildUse(node, use, context)
        case .slot:
            fillSlot(node)
        }
    }

    func slotContext(_ node: StructureNode) -> BuildContext {
        var context = node.context
        context.active = node.outerActive
        if case .slot(let name) = node.kind {
            context.path = context.path.appending("fill:" + name)
        }
        context.scope = node.context.slotOwner?.context.scope ?? node.context.scope
        context.slotOwner = node.context.slotOwner?.context.slotOwner
        return context
    }

    func slotContent(_ node: StructureNode) -> [ChildIR] {
        guard case .slot(let name) = node.kind, let owner = node.context.slotOwner, case .use(let use) = owner.kind else { return [] }
        return use.slots[name] ?? []
    }

    func fillSlot(_ node: StructureNode) {
        guard node.slotGeneration != generation else { return }
        node.slotGeneration = generation
        let context = slotContext(node)
        if let region = node.regions.first {
            reconcileParts(region, slotContent(node), context)
            return
        }
        let region = Region()
        node.regions = [region]
        node.selection = "slot"
        buildParts(region, slotContent(node), context)
    }

    func refreshSlots(_ owner: StructureNode, contentChanged: Bool) {
        let scope = owner.context.scope
        for slot in owner.slotNodes where !slot.isDead && slot.context.slotOwner === owner {
            if contentChanged {
                scheduleRebuild(slot)
            } else {
                for region in slot.regions {
                    region.context?.scope = scope
                    applyScope(region.parts.map { ($0, scope) })
                }
            }
        }
    }

    private func replace(_ node: StructureNode, selection: String?, bodies: [([ChildIR], BuildContext)]) {
        park(node.regions.flatMap(\.parts))
        node.regions.removeAll()
        node.selection = selection
        for (children, context) in bodies {
            let region = Region()
            node.regions.append(region)
            buildParts(region, children, context)
        }
        markDirty(node.context.container)
    }

    func entryScope(_ each: EachIR, _ base: LocalScope, item: Value, index: Int) -> LocalScope {
        var scope = base.adding(each.variable, item)
        if let indexVariable = each.indexVariable {
            scope = scope.adding(indexVariable, .number(Double(index)))
        }
        return scope
    }

    func entryContext(_ each: EachIR, _ context: BuildContext, _ region: Region, key: EntryKey) -> BuildContext {
        var entry = context
        entry.scope = entryScope(each, context.scope, item: region.item, index: region.index)
        entry.path = context.path.appending(each.key).appending(key.component)
        return entry
    }

    private func rebuildEach(_ node: StructureNode, _ each: EachIR, _ context: BuildContext) {
        let value = node.subject?.currentValue ?? .null
        guard case .list(let items) = value else {
            if value != .null {
                warn(key: "each-type|\(each.list.span)", Diagnostic(.warning, "each needs a list, got \(value.typeName)", span: each.list.span))
            }
            replace(node, selection: nil, bodies: [])
            return
        }
        if items.count > RuntimeLimits.eachEntries {
            warn(key: "each-limit|\(each.list.span)", Diagnostic(.warning, "each builds at most \(RuntimeLimits.eachEntries) entries, got \(items.count)", span: each.list.span))
        }
        let old = node.regions
        var count = min(items.count, RuntimeLimits.eachEntries)
        if old.isEmpty {
            let surface = context.surface
            let left = max(RuntimeLimits.elementsPerSurface - surface.elementCount, 0)
            if left < count {
                count = left
                if !surface.budgetWarned {
                    surface.budgetWarned = true
                    warn(key: "budget|" + surface.surfaceKey, Diagnostic(.warning, "surface '\(surface.instance.id)' reached \(RuntimeLimits.elementsPerSurface) elements, further elements are not built", span: each.list.span))
                }
            }
        }
        eachPass += 1
        let pass = eachPass
        var lookup: [EntryKey: Region] = [:]
        var fresh: [Region] = []
        if eachKeyLookup == .dictionary {
            lookup.reserveCapacity(max(old.count, count))
            for region in old {
                if let key = region.entryKey {
                    lookup[key] = region
                }
            }
        }
        func find(_ key: EntryKey) -> Region? {
            switch eachKeyLookup {
            case .dictionary:
                return lookup[key]
            case .linear:
                return old.first { $0.entryKey == key } ?? fresh.first { $0.entryKey == key }
            }
        }
        var nextOrdinal: [EntryKey: Int] = [:]
        var regions: [Region] = []
        regions.reserveCapacity(count)
        for index in 0..<count {
            let item = items[index]
            var key = entryKey(each, item: item, index: index, base: context.scope)
            var found = find(key)
            if found?.stamp == pass {
                warn(key: "each-duplicate|\(each.list.span)", Diagnostic(.warning, "each has duplicate keys, later entries get a suffix", span: (each.itemKey ?? each.list).span))
                let base = key
                var ordinal = nextOrdinal[base] ?? 2
                repeat {
                    key.ordinal = ordinal
                    ordinal += 1
                    found = find(key)
                } while found?.stamp == pass
                nextOrdinal[base] = ordinal
            }
            if let region = found {
                region.stamp = pass
                let indexMatters = each.indexVariable != nil && region.index != index
                region.index = index
                if indexMatters || !(Self.identical(region.item, item) || region.item == item) {
                    region.item = item
                    let scope = entryScope(each, context.scope, item: item, index: index)
                    region.context?.scope = scope
                    applyScope(region.parts.map { ($0, scope) })
                }
                regions.append(region)
            } else {
                let region = Region()
                region.entryKey = key
                region.item = item
                region.index = index
                region.stamp = pass
                regions.append(region)
                fresh.append(region)
                if eachKeyLookup == .dictionary {
                    lookup[key] = region
                }
            }
        }
        for region in old where region.stamp != pass {
            park(region.parts)
            region.parts.removeAll()
            region.context = nil
        }
        node.regions = regions
        node.selection = nil
        for region in fresh {
            if let key = region.entryKey {
                buildParts(region, each.body, entryContext(each, context, region, key: key))
            }
        }
        markDirty(node.context.container)
    }

    private func entryKey(_ each: EachIR, item: Value, index: Int, base: LocalScope) -> EntryKey {
        if let itemKey = each.itemKey {
            let key = bindings.evaluateOnce(itemKey, scope: entryScope(each, base, item: item, index: index))
            if key == .null {
                warn(key: "each-null-key|\(itemKey.span)", Diagnostic(.warning, "each key is null, using the position instead", span: itemKey.span))
                return EntryKey(value: nil, index: index)
            }
            return EntryKey(value: key, index: index)
        }
        if case .record(let record) = item, let id = record["id"], id != .null {
            return EntryKey(value: id, index: index)
        }
        return EntryKey(value: nil, index: index)
    }

    func useScope(_ node: StructureNode, _ use: DynamicUseIR, _ define: DefineIR, _ base: LocalScope) -> LocalScope {
        let name = define.name
        var scope = base
        for parameter in define.parameters {
            if let handle = node.argumentBindings[parameter.name] {
                scope = scope.adding(parameter.name, handle.currentValue)
            } else if let defaultValue = parameter.defaultValue {
                scope = scope.adding(parameter.name, TemplateValues.evaluate(defaultValue) { bindings.evaluateOnce($0, scope: base) })
            } else {
                warn(key: "use-missing|\(use.name.span)|\(name)|\(parameter.name)", Diagnostic(.warning, "block '\(name)' needs parameter '\(parameter.name)'", span: use.name.span))
                scope = scope.adding(parameter.name, .null)
            }
        }
        return scope
    }

    func regionScope(_ node: StructureNode, _ region: Region) -> LocalScope {
        switch node.kind {
        case .when, .switchOn:
            return node.context.scope
        case .each(let each):
            return entryScope(each, node.context.scope, item: region.item, index: region.index)
        case .use(let use):
            guard let define = node.define else { return node.context.scope }
            return useScope(node, use, define, node.context.scope)
        case .slot:
            return node.context.slotOwner?.context.scope ?? node.context.scope
        }
    }

    private func rebuildUse(_ node: StructureNode, _ use: DynamicUseIR, _ context: BuildContext) {
        let nameValue = node.subject?.currentValue ?? .null
        guard case .string(let name) = nameValue, !name.isEmpty else {
            if nameValue != .null {
                warn(key: "use-name|\(use.name.span)", Diagnostic(.warning, "use needs a block name, got \(nameValue.typeName)", span: use.name.span))
            }
            replace(node, selection: nil, bodies: [])
            return
        }
        guard context.useDepth < ConfigLimits.useDepth else {
            warn(key: "use-depth|\(use.name.span)", Diagnostic(.warning, "runtime use nested deeper than \(ConfigLimits.useDepth) levels is not expanded", span: use.name.span))
            replace(node, selection: nil, bodies: [])
            return
        }
        guard let define = config?.defines[name] else {
            warn(key: "use-unknown|\(use.name.span)|\(name)", Diagnostic(.warning, "unknown block '\(name)'", span: use.name.span))
            replace(node, selection: nil, bodies: [])
            return
        }
        let known = Set(define.parameters.map(\.name))
        for argument in use.arguments.keys.sorted() where !known.contains(argument) {
            warn(key: "use-parameter|\(use.name.span)|\(name)|\(argument)", Diagnostic(.warning, "unknown parameter '\(argument)' for block '\(name)'", span: use.arguments[argument]?.span ?? use.name.span))
        }
        node.define = define
        let scope = useScope(node, use, define, context.scope)
        if node.selection == "use:" + name, let region = node.regions.first {
            region.context?.scope = scope
            applyScope(region.parts.map { ($0, scope) })
            return
        }
        var body = context
        body.scope = scope
        body.useDepth = context.useDepth + 1
        body.path = context.path.appending(use.key).appending("use:" + name)
        body.slotOwner = node
        replace(node, selection: "use:" + name, bodies: [(define.body, body)])
    }
}
