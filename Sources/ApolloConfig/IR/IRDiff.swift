import ApolloBase

public enum IRDiff {
    public static func surfaces(old: ConfigIR, new: ConfigIR) -> SurfaceChange {
        StackHeadroom.run {
            var oldByID: [String: SurfaceIR] = [:]
            for surface in old.surfaces where oldByID[surface.id] == nil {
                oldByID[surface.id] = surface
            }
            let newIDs = Set(new.surfaces.map(\.id))
            var change = SurfaceChange()
            for surface in new.surfaces {
                guard let previous = oldByID[surface.id] else {
                    change.added.append(surface)
                    continue
                }
                if previous == surface || previous.withoutSpans == surface.withoutSpans {
                    change.unchanged.append(surface.id)
                } else {
                    change.changed.append(surface)
                }
            }
            change.removed = old.surfaces.map(\.id).filter { !newIDs.contains($0) }
            return change
        }
    }
}

private let noSpan = SourceSpan.synthetic("")

private extension Dictionary where Value == CompiledValue {
    var withoutSpans: [Key: CompiledValue] {
        mapValues(\.withoutSpans)
    }
}

private extension CompiledValue {
    var withoutSpans: CompiledValue {
        CompiledValue(template: template.withoutSpans, dependencies: dependencies, span: noSpan)
    }
}

private extension StringTemplate {
    var withoutSpans: StringTemplate {
        switch self {
        case .literal:
            return self
        case .whole(let expr):
            return .whole(expr.withoutSpans)
        case .parts(let parts):
            return .parts(parts.map { part in
                guard case .expression(let expr) = part else { return part }
                return .expression(expr.withoutSpans)
            })
        }
    }
}

private extension Expr {
    var withoutSpans: Expr {
        switch self {
        case .literal:
            return self
        case .list(let items):
            return .list(items.map(\.withoutSpans))
        case .path(let root, let members):
            return .path(root: root, members: members.map(\.withoutSpans))
        case .access(let base, let members):
            return .access(base.withoutSpans, members.map(\.withoutSpans))
        case .unary(let op, let operand):
            return .unary(op, operand.withoutSpans)
        case .binary(let op, let lhs, let rhs):
            return .binary(op, lhs.withoutSpans, rhs.withoutSpans)
        case .conditional(let condition, let then, let otherwise):
            return .conditional(condition.withoutSpans, then.withoutSpans, otherwise.withoutSpans)
        case .coalesce(let lhs, let rhs):
            return .coalesce(lhs.withoutSpans, rhs.withoutSpans)
        case .pipe(let input, let call):
            return .pipe(input.withoutSpans, FilterCall(name: call.name, arguments: call.arguments.map(\.withoutSpans), span: noSpan))
        }
    }
}

private extension PathMember {
    var withoutSpans: PathMember {
        guard case .index(let expr) = self else { return self }
        return .index(expr.withoutSpans)
    }
}

private extension ValueTemplate {
    var withoutSpans: ValueTemplate {
        switch self {
        case .scalar(let compiled):
            return .scalar(compiled.withoutSpans)
        case .list(let items):
            return .list(items.map(\.withoutSpans))
        case .record(let fields):
            return .record(fields.map { ValueTemplateField(name: $0.name, value: $0.value.withoutSpans) })
        }
    }
}

private extension ActionIR {
    var withoutSpans: ActionIR {
        switch self {
        case .call(let call):
            return .call(ActionCallIR(name: call.name, arguments: call.arguments.map(\.withoutSpans), properties: call.properties.withoutSpans, children: call.children.map(\.withoutSpans), span: noSpan))
        case .when(let condition, let then, let otherwise):
            return .when(condition: condition.withoutSpans, then: then.map(\.withoutSpans), otherwise: otherwise.map(\.withoutSpans))
        case .switchOn(let subject, let cases, let otherwise):
            return .switchOn(subject: subject.withoutSpans, cases: cases.map { ActionCaseIR(values: $0.values.map(\.withoutSpans), body: $0.body.map(\.withoutSpans)) }, otherwise: otherwise.map(\.withoutSpans))
        case .each(let variable, let index, let list, let body):
            return .each(variable: variable, index: index, list: list.withoutSpans, body: body.map(\.withoutSpans))
        case .repeatBlock(let count, let body):
            return .repeatBlock(count: count.withoutSpans, body: body.map(\.withoutSpans))
        }
    }
}

private extension HandlerIR {
    var withoutSpans: HandlerIR {
        HandlerIR(name: name, properties: properties.withoutSpans, actions: actions.map(\.withoutSpans), span: noSpan)
    }
}

private extension KeyHandlerIR {
    var withoutSpans: KeyHandlerIR {
        KeyHandlerIR(chord: chord, actions: actions.map(\.withoutSpans))
    }
}

private extension MenuItemIR {
    var withoutSpans: MenuItemIR {
        switch self {
        case .item(let title, let properties, let actions):
            return .item(title: title.withoutSpans, properties: properties.withoutSpans, actions: actions.map(\.withoutSpans))
        case .separator:
            return self
        case .section(let title):
            return .section(title.withoutSpans)
        case .submenu(let title, let items):
            return .submenu(title: title.withoutSpans, items: items.map(\.withoutSpans))
        case .source(let kind, let properties):
            return .source(kind: kind, properties: properties.withoutSpans)
        case .each(let variable, let index, let list, let key, let body):
            return .each(variable: variable, index: index, list: list.withoutSpans, key: key?.withoutSpans, body: body.map(\.withoutSpans))
        case .when(let condition, let then, let otherwise):
            return .when(condition: condition.withoutSpans, then: then.map(\.withoutSpans), otherwise: otherwise.map(\.withoutSpans))
        }
    }
}

private extension ChildIR {
    var withoutSpans: ChildIR {
        switch self {
        case .element(let element):
            return .element(ElementIR(
                kind: element.kind,
                key: element.key,
                arguments: element.arguments.map(\.withoutSpans),
                properties: element.properties.withoutSpans,
                handlers: element.handlers.map(\.withoutSpans),
                keyHandlers: element.keyHandlers.map(\.withoutSpans),
                accessibilityActions: element.accessibilityActions.map { AccessibilityActionIR(title: $0.title.withoutSpans, actions: $0.actions.map(\.withoutSpans)) },
                menu: element.menu.map { MenuIR(properties: $0.properties.withoutSpans, items: $0.items.map(\.withoutSpans)) },
                slots: element.slots.mapValues { $0.map(\.withoutSpans) },
                children: element.children.map(\.withoutSpans),
                span: noSpan
            ))
        case .each(let each):
            return .each(EachIR(key: each.key, variable: each.variable, indexVariable: each.indexVariable, list: each.list.withoutSpans, itemKey: each.itemKey?.withoutSpans, body: each.body.map(\.withoutSpans)))
        case .when(let when):
            return .when(WhenIR(key: when.key, condition: when.condition.withoutSpans, then: when.then.map(\.withoutSpans), otherwise: when.otherwise.map(\.withoutSpans)))
        case .switchOn(let choice):
            return .switchOn(SwitchIR(key: choice.key, subject: choice.subject.withoutSpans, cases: choice.cases.map { SwitchCaseIR(values: $0.values.map(\.withoutSpans), body: $0.body.map(\.withoutSpans)) }, otherwise: choice.otherwise.map(\.withoutSpans)))
        case .dynamicUse(let use):
            return .dynamicUse(DynamicUseIR(key: use.key, name: use.name.withoutSpans, arguments: use.arguments.withoutSpans, slots: use.slots.mapValues { $0.map(\.withoutSpans) }))
        case .slot:
            return self
        }
    }
}

private extension SurfaceIR {
    var withoutSpans: SurfaceIR {
        SurfaceIR(kind: kind, id: id, properties: properties.withoutSpans, handlers: handlers.map(\.withoutSpans), keyHandlers: keyHandlers.map(\.withoutSpans), children: children.map(\.withoutSpans), span: noSpan)
    }
}
