import ApolloBase
import ApolloConfig

extension ShellRuntime {
    func makeStructure(_ kind: StructureNode.Kind, _ context: BuildContext) -> StructureNode {
        let node = StructureNode(kind: kind, context: context)
        let rank = BindingRank.structure(depth: context.depth)
        let changed: @MainActor (Value) -> Void = { [weak self, weak node] _ in
            guard let self, let node else { return }
            self.scheduleRebuild(node)
        }
        func bind(_ compiled: CompiledValue) -> BindingHandle {
            bindings.bind(compiled, scope: context.scope, rank: rank, active: context.active, onChange: changed)
        }
        switch kind {
        case .when(let when):
            node.subject = bind(when.condition)
        case .switchOn(let switchIR):
            node.subject = bind(switchIR.subject)
            node.caseBindings = switchIR.cases.map { $0.values.map(bind) }
        case .each(let each):
            node.subject = bind(each.list)
        case .use(let use):
            node.subject = bind(use.name)
            for name in use.arguments.keys.sorted() {
                if let compiled = use.arguments[name] {
                    node.argumentBindings[name] = bind(compiled)
                }
            }
        }
        return node
    }

    func scheduleRebuild(_ node: StructureNode) {
        guard !node.isDead, !node.rebuildQueued else { return }
        node.rebuildQueued = true
        enqueue { [weak self, weak node] in
            guard let self, let node else { return }
            node.rebuildQueued = false
            guard !node.isDead else { return }
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
        }
    }

    private func replace(_ node: StructureNode, selection: String?, bodies: [([ChildIR], BuildContext)]) {
        teardown(node.regions.flatMap(\.parts))
        node.regions.removeAll()
        node.selection = selection
        for (children, context) in bodies {
            let region = Region()
            node.regions.append(region)
            buildParts(region, children, context)
        }
        markDirty(node.context.container)
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
        var bodies: [([ChildIR], BuildContext)] = []
        var seen: [String: Int] = [:]
        for index in 0..<min(items.count, RuntimeLimits.eachEntries) {
            let item = items[index]
            var scope = context.scope.adding(each.variable, item)
            if let indexVariable = each.indexVariable {
                scope = scope.adding(indexVariable, .number(Double(index)))
            }
            var component = entryKey(each, item: item, index: index, scope: scope)
            if let count = seen[component] {
                seen[component] = count + 1
                warn(key: "each-duplicate|\(each.list.span)", Diagnostic(.warning, "each has duplicate keys, later entries get a suffix", span: (each.itemKey ?? each.list).span))
                component += "#\(count + 1)"
            } else {
                seen[component] = 1
            }
            var entry = context
            entry.scope = scope
            entry.path = context.path.appending(each.key).appending(component)
            bodies.append((each.body, entry))
        }
        replace(node, selection: nil, bodies: bodies)
    }

    private func entryKey(_ each: EachIR, item: Value, index: Int, scope: LocalScope) -> String {
        let key: Value
        if let itemKey = each.itemKey {
            key = bindings.evaluateOnce(itemKey, scope: scope)
            if key == .null {
                warn(key: "each-null-key|\(itemKey.span)", Diagnostic(.warning, "each key is null, using the position instead", span: itemKey.span))
                return "i:\(index)"
            }
        } else if case .record(let record) = item, let id = record["id"], id != .null {
            key = id
        } else {
            return "i:\(index)"
        }
        return "k:\(key.typeName):\(Self.keyText(key))"
    }

    private static func keyText(_ value: Value) -> String {
        switch value {
        case .string(let text): text
        case .number(let number): number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .bool(let flag): flag ? "true" : "false"
        default: String(describing: value)
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
        var scope = context.scope
        for parameter in define.parameters {
            if let handle = node.argumentBindings[parameter.name] {
                scope = scope.adding(parameter.name, handle.currentValue)
            } else if let defaultValue = parameter.defaultValue {
                scope = scope.adding(parameter.name, TemplateValues.evaluate(defaultValue) { bindings.evaluateOnce($0, scope: context.scope) })
            } else {
                warn(key: "use-missing|\(use.name.span)|\(name)|\(parameter.name)", Diagnostic(.warning, "block '\(name)' needs parameter '\(parameter.name)'", span: use.name.span))
                scope = scope.adding(parameter.name, .null)
            }
        }
        if !use.slots.isEmpty {
            warn(key: "use-slots|\(use.name.span)", Diagnostic(.warning, "slot content of a runtime use is not supported yet", span: use.name.span))
        }
        var body = context
        body.scope = scope
        body.useDepth = context.useDepth + 1
        body.path = context.path.appending(use.key).appending("use:" + name)
        replace(node, selection: "use:" + name, bodies: [(define.body, body)])
    }
}
