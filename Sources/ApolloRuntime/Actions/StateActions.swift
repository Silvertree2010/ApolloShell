import ApolloBase
import ApolloConfig

@MainActor
struct StateActions {
    static let names: Set<String> = ["set", "toggle-var", "reset", "list.insert", "list.remove", "list.move", "list.move-to", "list.swap", "list.update"]

    let vars: VarStore

    func perform(_ call: ResolvedActionCall) throws {
        switch call.name {
        case "set": try set(call)
        case "toggle-var": try toggle(call)
        case "reset": vars.reset(try writable(call, 0))
        case "list.insert": try insert(call)
        case "list.remove": try remove(call)
        case "list.move": try move(call)
        case "list.move-to": try moveTo(call)
        case "list.swap": try swap(call)
        case "list.update": try update(call)
        default: throw ActionFailure("unknown action '\(call.name)'")
        }
    }

    private func set(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        let value: Value
        if call.arguments.count > 1 {
            value = call.arguments[1]
        } else if !call.children.isEmpty {
            value = .list(call.children)
        } else {
            value = call.properties["value"] ?? .null
        }
        var duration: Double?
        if let raw = call.properties["for"], raw != .null {
            guard let seconds = RuntimeDuration.seconds(raw), seconds >= 0 else {
                throw ActionFailure("set for= needs a duration like \"500ms\"")
            }
            duration = seconds
        }
        guard let entry = try optionalKey(call.properties["in"], "in") else {
            vars.set(name, value, for: duration)
            return
        }
        let current = vars.value(name)
        let updated: Value
        if let field = try optionalText(call.properties["field"], "field") {
            updated = try ListOperations.apply(.update(at: entry, fields: Record([(field, value)])), to: current, span: call.span).get()
        } else {
            guard case .list(var items) = current else {
                throw ActionFailure("set in= needs a list var, '\(name)' is \(current.typeName)")
            }
            let index = try Self.index(of: entry, in: items)
            items[index] = value
            updated = .list(items)
        }
        vars.set(name, updated, for: duration)
    }

    private func toggle(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        guard case .bool(let flag) = vars.value(name) else {
            throw ActionFailure("toggle-var needs a bool var, '\(name)' is \(vars.value(name).typeName)")
        }
        vars.set(name, .bool(!flag))
    }

    private func insert(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        let items = call.properties["value"].map { [$0] } ?? call.children
        guard !items.isEmpty else {
            throw ActionFailure("list.insert needs value= or children")
        }
        let at = try optionalIndex(call.properties["at"], "at")
        let idFrom = try optionalText(call.properties["id-from"], "id-from")
        let locator = try locator(call)
        var value = vars.value(name)
        for (offset, item) in items.enumerated() {
            value = try ListOperations.apply(.insert(item: item, at: at.map { $0 + offset }, idFrom: idFrom), to: value, locator: locator, span: call.span).get()
        }
        vars.set(name, value)
    }

    private func remove(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        let key = try entryKey(call, primary: "at")
        try apply(name, .remove(at: key), call)
    }

    private func move(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        let from = try entryKey(call, primary: "from")
        guard let to = try optionalIndex(call.properties["to"], "to") else {
            throw ActionFailure("list.move needs to=")
        }
        try apply(name, .move(from: from, to: to), call)
    }

    private func update(_ call: ResolvedActionCall) throws {
        let name = try writable(call, 0)
        let key = try entryKey(call, primary: "at")
        var fields = Record()
        for child in call.children {
            guard case .record(let record) = child else {
                throw ActionFailure("list.update needs record children, got \(child.typeName)")
            }
            for field in record.keys {
                fields[field] = record[field]
            }
        }
        try apply(name, .update(at: key, fields: fields), call)
    }

    private func moveTo(_ call: ResolvedActionCall) throws {
        let source = try writable(call, 0)
        let destination = try writable(call, 1)
        guard let from = try optionalIndex(call.properties["from"], "from"), let to = try optionalIndex(call.properties["to"], "to") else {
            throw ActionFailure("list.move-to needs from= and to=")
        }
        let locator = try locator(call)
        if source == destination {
            try apply(source, .move(from: .index(from), to: to), call)
            return
        }
        let result = try ListOperations.moveTo(from: vars.value(source), at: .index(from), to: vars.value(destination), index: to, locator: locator, span: call.span).get()
        try commit([(source, result.source), (destination, result.destination)])
    }

    private func swap(_ call: ResolvedActionCall) throws {
        let first = try writable(call, 0)
        let second = try writable(call, 2)
        guard call.arguments.count > 3, let a = Self.key(call.arguments[1]), let b = Self.key(call.arguments[3]) else {
            throw ActionFailure("list.swap needs two lists and two positions")
        }
        let locator = try locator(call)
        if first == second {
            let value = try ListOperations.swap(vars.value(first), a, b, locator: locator, span: call.span).get()
            vars.set(first, value)
            return
        }
        let result = try ListOperations.swap(vars.value(first), a, vars.value(second), b, locator: locator, span: call.span).get()
        try commit([(first, result.a), (second, result.b)])
    }

    private func apply(_ name: String, _ operation: ListOperation, _ call: ResolvedActionCall) throws {
        let value = try ListOperations.apply(operation, to: vars.value(name), locator: try locator(call), span: call.span).get()
        vars.set(name, value)
    }

    private func commit(_ writes: [(String, Value)]) throws {
        let previous = writes.map { (name: $0.0, value: vars.value($0.0)) }
        for (name, value) in writes where !vars.set(name, value) {
            for prior in previous {
                vars.set(prior.name, prior.value)
            }
            throw ActionFailure("could not write '\(name)', nothing changed")
        }
    }

    private func writable(_ call: ResolvedActionCall, _ index: Int) throws -> String {
        guard index < call.arguments.count, case .string(let name) = call.arguments[index], !name.isEmpty else {
            throw ActionFailure("\(call.name) needs the name of a var")
        }
        if vars.isDerived(name) {
            throw ActionFailure("'\(name)' is derived and cannot be set")
        }
        guard vars.isDeclared(name) else {
            throw ActionFailure("unknown var '\(name)'")
        }
        return name
    }

    private func locator(_ call: ResolvedActionCall) throws -> ListLocator {
        ListLocator(entry: try optionalKey(call.properties["in"], "in"), field: try optionalText(call.properties["field"], "field"))
    }

    private func entryKey(_ call: ResolvedActionCall, primary: String) throws -> ListKey {
        if let raw = call.properties[primary], raw != .null {
            guard let index = try optionalIndex(raw, primary) else { throw ActionFailure("\(call.name) needs \(primary)=") }
            return .index(index)
        }
        if let key = try optionalKey(call.properties["key"], "key") {
            return key
        }
        throw ActionFailure("\(call.name) needs \(primary)= or key=")
    }

    private func optionalIndex(_ value: Value?, _ label: String) throws -> Int? {
        guard let value, value != .null else { return nil }
        guard case .number(let number) = value, number.isFinite, number == number.rounded(), abs(number) < 1e9 else {
            throw ActionFailure("\(label)= needs a whole number, got \(value.typeName)")
        }
        return Int(number)
    }

    private func optionalKey(_ value: Value?, _ label: String) throws -> ListKey? {
        guard let value, value != .null else { return nil }
        guard let key = Self.key(value) else {
            throw ActionFailure("\(label)= needs a position or a key, got \(value.typeName)")
        }
        return key
    }

    private func optionalText(_ value: Value?, _ label: String) throws -> String? {
        guard let value, value != .null else { return nil }
        guard case .string(let text) = value else {
            throw ActionFailure("\(label)= needs a string, got \(value.typeName)")
        }
        return text
    }

    static func key(_ value: Value) -> ListKey? {
        switch value {
        case .number(let number) where number.isFinite && number == number.rounded() && abs(number) < 1e9:
            return .index(Int(number))
        case .string(let text):
            return .entry(text)
        default:
            return nil
        }
    }

    static func index(of key: ListKey, in items: [Value]) throws -> Int {
        switch key {
        case .index(let index):
            guard index >= 0, index < items.count else {
                throw ActionFailure("list index \(index) out of range (0...\(items.count))")
            }
            return index
        case .entry(let id):
            let found = items.firstIndex { item in
                if case .record(let record) = item, case .string(let recordID)? = record["id"] { return recordID == id }
                if case .string(let text) = item { return text == id }
                return false
            }
            guard let found else { throw ActionFailure("no list entry with key \"\(id)\"") }
            return found
        }
    }
}
