import ApolloBase
import ApolloConfig

extension ShellRuntime {
    func reconcileSurface(_ node: SurfaceNode, _ ir: SurfaceIR) -> Bool {
        let old = node.instance.ir
        let changed = old != ir
        guard changed || definesChanged else { return false }
        if changed {
            node.instance.ir = ir
            reconcileSurfaceProperties(node, from: old.properties, to: ir.properties)
        }
        if let root = node.root, old.children != ir.children || definesChanged {
            reconcileParts(root.region, ir.children, rootContext(node, root))
        }
        return changed
    }

    private func reconcileSurfaceProperties(_ node: SurfaceNode, from old: [String: CompiledValue], to new: [String: CompiledValue]) {
        var cells = node.instance.properties
        var keysChanged = false
        for name in Set(old.keys).union(new.keys).sorted() {
            switch (old[name], new[name]) {
            case (nil, nil):
                continue
            case (.some, nil):
                node.propertyBindings.removeValue(forKey: name)?.cancel()
                cells[name] = nil
                keysChanged = true
                if name == "visible" {
                    node.visibleProperty = true
                    updateVisibility(node)
                }
            case (nil, .some(let after)):
                let cell = PropertyCell(.null)
                cells[name] = cell
                keysChanged = true
                node.propertyBindings[name] = bindSurfaceProperty(node, name, after, cell)
            case (.some(let before), .some(let after)):
                if let handle = node.propertyBindings[name], Self.equivalent(before, after) {
                    if before != after {
                        handle.updateSource(after)
                    }
                    continue
                }
                node.propertyBindings.removeValue(forKey: name)?.cancel()
                let cell = cells[name] ?? PropertyCell(.null)
                if cells[name] == nil {
                    cells[name] = cell
                    keysChanged = true
                }
                node.propertyBindings[name] = bindSurfaceProperty(node, name, after, cell)
            }
        }
        if keysChanged {
            node.instance.properties = cells
        }
    }

    func reconcileParts(_ region: Region, _ children: [ChildIR], _ context: BuildContext) {
        region.context = context
        let old = region.parts
        var positional: [String: TreeNode] = [:]
        for part in old {
            if let element = part as? ElementNode {
                if element.runtimeID == nil {
                    positional["e|" + element.instance.ir.key] = element
                }
            } else if let structure = part as? StructureNode {
                positional[structure.kind.tag] = structure
            }
        }
        var parts: [TreeNode] = []
        for child in children {
            let part: TreeNode?
            if case .element(let ir) = child {
                part = placeElement(ir, context, reuse: positional)
            } else if let kind = StructureNode.Kind(child) {
                if let existing = positional[kind.tag] as? StructureNode, existing.stamp != generation, !existing.isDead {
                    reconcileStructure(existing, kind, context)
                    part = existing
                } else {
                    part = makeStructure(kind, context)
                }
            } else {
                part = nil
            }
            if let part {
                part.region = region
                parts.append(part)
            }
        }
        region.parts = parts
        park(old.filter { $0.stamp != generation })
        markDirty(context.container)
    }

    func reconcileElement(_ node: ElementNode, _ ir: ElementIR, _ context: BuildContext) {
        node.stamp = generation
        node.isParked = false
        node.depth = context.depth
        node.useDepth = context.useDepth
        let old = node.instance.ir
        if old == ir && !definesChanged {
            applyScope([(node, context.scope)])
            updateActivity(node, context.active)
            return
        }
        let identity = node.instance.identity
        let scope = context.scope.adding(ContextScopeKeys.selfIdentity, .string(identity.description))
        let scopeChanged = scope != node.instance.scope
        if scopeChanged {
            node.instance.scope = scope
        }
        if old != ir {
            node.instance.ir = ir
        }
        reconcileCells(node, from: old, to: ir, scopeChanged: scopeChanged)
        if old.handlers != ir.handlers || scopeChanged {
        }
        updateActivity(node, context.active)
        if let container = node.childContainer {
            let children = ir.children
            enqueue { [weak self, weak node] in
                guard let self, let node, !node.isDead else { return }
                self.reconcileParts(container.region, children, node.childContext(container, path: identity))
            }
        }
        for name in Set(old.slots.keys).union(ir.slots.keys).sorted() {
            let body = ir.slots[name]
            if let container = node.slotContainers[name] {
                if let body {
                    enqueue { [weak self, weak node] in
                        guard let self, let node, !node.isDead else { return }
                        self.reconcileParts(container.region, body, node.childContext(container, path: identity.appending("slot:" + name)))
                    }
                } else {
                    park(container.region.parts)
                    container.region.parts.removeAll()
                    container.region.context = nil
                    node.slotContainers[name] = nil
                    node.instance.slotChildren[name] = nil
                }
            } else if let body {
                addSlot(node, name, body)
            }
        }
    }

    private func updateActivity(_ node: TreeNode, _ active: Bool) {
        guard node.outerActive != active else { return }
        propagate([node], active: active)
    }

    private func reconcileCells(_ node: ElementNode, from old: ElementIR, to new: ElementIR, scopeChanged: Bool) {
        let instance = node.instance
        var cells = instance.properties
        var keysChanged = false
        for name in Set(old.properties.keys).union(new.properties.keys).sorted() where name != "id" {
            let before = old.properties[name]
            let after = new.properties[name]
            if name == "visible" {
                reconcileVisible(node, before, after, &cells, &keysChanged, scopeChanged: scopeChanged)
                continue
            }
            switch (before, after) {
            case (nil, nil):
                continue
            case (.some, nil):
                node.cellBindings.removeValue(forKey: name)?.cancel()
                cells[name] = nil
                keysChanged = true
            case (nil, .some(let after)):
                let cell = PropertyCell(.null)
                cells[name] = cell
                keysChanged = true
                node.cellBindings[name] = fill(cell, after, node: node)
            case (.some(let before), .some(let after)):
                if Self.equivalent(before, after) {
                    if let handle = node.cellBindings[name] {
                        if scopeChanged {
                            handle.updateScope(instance.scope)
                        }
                        if before != after {
                            handle.updateSource(after)
                        }
                    }
                    continue
                }
                node.cellBindings.removeValue(forKey: name)?.cancel()
                let cell = cells[name] ?? PropertyCell(.null)
                if cells[name] == nil {
                    cells[name] = cell
                    keysChanged = true
                }
                node.cellBindings[name] = fill(cell, after, node: node)
            }
        }
        if keysChanged {
            instance.properties = cells
        }
        var arguments = instance.arguments
        let argumentsChanged = arguments.count != new.arguments.count
        for index in 0..<max(old.arguments.count, new.arguments.count) {
            if index >= new.arguments.count {
                node.argumentBindings.removeValue(forKey: index)?.cancel()
                continue
            }
            let after = new.arguments[index]
            if index < old.arguments.count, index < arguments.count, Self.equivalent(old.arguments[index], after) {
                if let handle = node.argumentBindings[index] {
                    if scopeChanged {
                        handle.updateScope(instance.scope)
                    }
                    if old.arguments[index] != after {
                        handle.updateSource(after)
                    }
                }
                continue
            }
            node.argumentBindings.removeValue(forKey: index)?.cancel()
            if index >= arguments.count {
                arguments.append(PropertyCell(.null))
            }
            node.argumentBindings[index] = fill(arguments[index], after, node: node)
        }
        if argumentsChanged {
            instance.arguments = Array(arguments.prefix(new.arguments.count))
        }
    }

    private func reconcileVisible(_ node: ElementNode, _ before: CompiledValue?, _ after: CompiledValue?, _ cells: inout [String: PropertyCell], _ keysChanged: inout Bool, scopeChanged: Bool) {
        switch (before, after) {
        case (nil, nil):
            return
        case (.some, nil):
            node.visibleBinding?.cancel()
            node.visibleBinding = nil
            cells["visible"] = nil
            keysChanged = true
            setSelfVisible(node, true)
        case (nil, .some(let after)):
            let cell = PropertyCell(.null)
            cells["visible"] = cell
            keysChanged = true
            node.visibleBinding = bindVisible(node, after, cell)
        case (.some(let before), .some(let after)):
            if let handle = node.visibleBinding, Self.equivalent(before, after) {
                if scopeChanged {
                    handle.updateScope(node.instance.scope)
                }
                if before != after {
                    handle.updateSource(after)
                }
                return
            }
            node.visibleBinding?.cancel()
            let cell = cells["visible"] ?? PropertyCell(.null)
            if cells["visible"] == nil {
                cells["visible"] = cell
                keysChanged = true
            }
            node.visibleBinding = bindVisible(node, after, cell)
        }
    }

    func reconcileStructure(_ node: StructureNode, _ kind: StructureNode.Kind, _ context: BuildContext) {
        node.stamp = generation
        node.isParked = false
        let old = node.kind
        if old == kind && !definesChanged {
            applyScope([(node, context.scope)])
            node.context = context
            updateActivity(node, context.active)
            return
        }
        let scopeChanged = node.context.scope != context.scope
        node.context = context
        node.kind = kind
        updateActivity(node, context.active)
        switch (old, kind) {
        case (.when(let before), .when(let after)):
            node.subject = rebind(node, node.subject, before.condition, after.condition, scopeChanged: scopeChanged).handle
            if let selection = node.selection, let region = node.regions.first {
                var inner = context
                inner.path = context.path.appending(after.key).appending(selection)
                reconcileLater(node, region, selection == "then" ? after.then : after.otherwise, inner)
            }
        case (.switchOn(let before), .switchOn(let after)):
            var replaced = false
            let subject = rebind(node, node.subject, before.subject, after.subject, scopeChanged: scopeChanged)
            node.subject = subject.handle
            replaced = subject.replaced
            if Self.equivalentCases(before.cases, after.cases) {
                for (group, handles) in zip(after.cases, node.caseBindings) {
                    for (value, handle) in zip(group.values, handles) {
                        if scopeChanged {
                            handle.updateScope(context.scope)
                        }
                        handle.updateSource(value)
                    }
                }
            } else {
                for handle in node.caseBindings.flatMap({ $0 }) {
                    handle.cancel()
                }
                node.caseBindings = after.cases.map { $0.values.map { bindStructure(node, $0) } }
                replaced = true
            }
            if let selection = node.selection, let region = node.regions.first {
                var body: [ChildIR]?
                if selection == "default" {
                    body = after.otherwise
                } else if let index = Int(selection.dropFirst(4)), index < after.cases.count {
                    body = after.cases[index].body
                }
                if let body {
                    var inner = context
                    inner.path = context.path.appending(after.key).appending(selection)
                    reconcileLater(node, region, body, inner)
                } else {
                    park(region.parts)
                    node.regions.removeAll()
                    node.selection = nil
                    markDirty(context.container)
                    if !replaced {
                        scheduleRebuild(node)
                    }
                }
            }
        case (.each(let before), .each(let after)):
            let list = rebind(node, node.subject, before.list, after.list, scopeChanged: scopeChanged)
            node.subject = list.handle
            for region in node.regions {
                guard let key = region.entryKey else { continue }
                reconcileLater(node, region, after.body, entryContext(after, context, region, key: key))
            }
            let sameKeys = before.variable == after.variable && before.indexVariable == after.indexVariable && Self.equivalent(before.itemKey, after.itemKey)
            if !list.replaced && !sameKeys {
                scheduleRebuild(node)
            }
        case (.use(let before), .use(let after)):
            let name = rebind(node, node.subject, before.name, after.name, scopeChanged: scopeChanged)
            node.subject = name.handle
            var argumentReplaced = false
            for parameter in Set(before.arguments.keys).union(after.arguments.keys).sorted() {
                switch (before.arguments[parameter], after.arguments[parameter]) {
                case (.some(let old), .some(let new)):
                    let result = rebind(node, node.argumentBindings[parameter], old, new, scopeChanged: scopeChanged)
                    node.argumentBindings[parameter] = result.handle
                    argumentReplaced = argumentReplaced || result.replaced
                case (.some, nil):
                    node.argumentBindings.removeValue(forKey: parameter)?.cancel()
                case (nil, .some(let new)):
                    node.argumentBindings[parameter] = bindStructure(node, new)
                    argumentReplaced = true
                case (nil, nil):
                    break
                }
            }
            if let selection = node.selection, let region = node.regions.first {
                if let define = config?.defines[String(selection.dropFirst(4))] {
                    node.define = define
                    var inner = context
                    inner.scope = useScope(node, after, define, context.scope)
                    inner.useDepth = context.useDepth + 1
                    inner.path = context.path.appending(after.key).appending(selection)
                    reconcileLater(node, region, Self.fillSlots(define.body, after.slots), inner)
                } else if !name.replaced {
                    scheduleRebuild(node)
                }
            }
        default:
            break
        }
    }

    private func reconcileLater(_ node: StructureNode, _ region: Region, _ body: [ChildIR], _ context: BuildContext) {
        enqueue { [weak self, weak node] in
            guard let self, let node, !node.isDead, !node.isParked, node.regions.contains(where: { $0 === region }) else { return }
            self.reconcileParts(region, body, context)
        }
    }

    private func rebind(_ node: StructureNode, _ handle: BindingHandle?, _ before: CompiledValue, _ after: CompiledValue, scopeChanged: Bool) -> (handle: BindingHandle, replaced: Bool) {
        if let handle, Self.equivalent(before, after) {
            if scopeChanged {
                handle.updateScope(node.context.scope)
            }
            if before != after {
                handle.updateSource(after)
            }
            return (handle, false)
        }
        handle?.cancel()
        return (bindStructure(node, after), true)
    }

    static func equivalent(_ lhs: CompiledValue?, _ rhs: CompiledValue?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let lhs), .some(let rhs)): equivalent(lhs, rhs)
        default: false
        }
    }

    static func equivalent(_ lhs: CompiledValue, _ rhs: CompiledValue) -> Bool {
        if lhs == rhs {
            return true
        }
        return lhs.dependencies == rhs.dependencies && SpanFree.template(lhs.template) == SpanFree.template(rhs.template)
    }

    static func equivalentCases(_ lhs: [SwitchCaseIR], _ rhs: [SwitchCaseIR]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            guard left.values.count == right.values.count else { return false }
            for (a, b) in zip(left.values, right.values) where !equivalent(a, b) {
                return false
            }
        }
        return true
    }
}

enum SpanFree {
    static let blank = SourceSpan.synthetic()

    static func template(_ template: StringTemplate) -> StringTemplate {
        switch template {
        case .literal:
            return template
        case .whole(let expr):
            return .whole(self.expr(expr))
        case .parts(let parts):
            return .parts(parts.map { part in
                switch part {
                case .text: part
                case .expression(let expr): .expression(self.expr(expr))
                }
            })
        }
    }

    static func expr(_ expr: Expr) -> Expr {
        switch expr {
        case .literal:
            return expr
        case .list(let items):
            return .list(items.map(self.expr))
        case .path(let root, let members):
            return .path(root: root, members: members.map(member))
        case .access(let base, let members):
            return .access(self.expr(base), members.map(member))
        case .unary(let op, let operand):
            return .unary(op, self.expr(operand))
        case .binary(let op, let lhs, let rhs):
            return .binary(op, self.expr(lhs), self.expr(rhs))
        case .conditional(let condition, let then, let otherwise):
            return .conditional(self.expr(condition), self.expr(then), self.expr(otherwise))
        case .coalesce(let lhs, let rhs):
            return .coalesce(self.expr(lhs), self.expr(rhs))
        case .pipe(let base, let filter):
            return .pipe(self.expr(base), FilterCall(name: filter.name, arguments: filter.arguments.map(self.expr), span: blank))
        }
    }

    static func member(_ member: PathMember) -> PathMember {
        switch member {
        case .field: member
        case .index(let expr): .index(self.expr(expr))
        }
    }
}
