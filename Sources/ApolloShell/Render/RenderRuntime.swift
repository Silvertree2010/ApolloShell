import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime

@MainActor
protocol RenderRuntime: AnyObject {
    @discardableResult
    func trigger(_ handler: String, on identity: Identity, event: Record) -> Task<Void, Never>?
    @discardableResult
    func run(_ actions: [ActionIR], on identity: Identity, site: String, event: Record, locals: [String: Value]) -> Task<Void, Never>?
    func evaluate(_ value: CompiledValue, on identity: Identity, locals: [String: Value]) -> Value
    func variable(_ name: String) -> Value
    func setVariable(_ name: String, _ value: Value)
    func bindChords() -> [(id: String, chord: String)]
    @discardableResult
    func perform(_ action: String, _ arguments: [String], on identity: Identity) -> Task<Void, Never>?
}

extension RenderRuntime {
    @discardableResult
    func perform(_ action: String, _ arguments: [String], on identity: Identity) -> Task<Void, Never>? {
        let span = SourceSpan.synthetic()
        let call = ActionCallIR(name: action, arguments: arguments.map { CompiledValue(template: .literal($0), dependencies: [], span: span) }, span: span)
        return run([.call(call)], on: identity, site: "menu-source:" + action, event: Record(), locals: [:])
    }
}

@MainActor
final class AssemblyRenderRuntime: RenderRuntime {
    private weak var assembly: ShellAssembly?

    init(_ assembly: ShellAssembly) {
        self.assembly = assembly
    }

    func trigger(_ handler: String, on identity: Identity, event: Record) -> Task<Void, Never>? {
        assembly?.runtime.trigger(handler, on: identity, event: event)
    }

    func run(_ actions: [ActionIR], on identity: Identity, site: String, event: Record, locals: [String: Value]) -> Task<Void, Never>? {
        assembly?.runtime.run(actions, on: identity, site: site, event: event, locals: locals)
    }

    func evaluate(_ value: CompiledValue, on identity: Identity, locals: [String: Value]) -> Value {
        assembly?.runtime.evaluate(value, on: identity, locals: locals) ?? .null
    }

    func variable(_ name: String) -> Value {
        assembly?.vars.value(name) ?? .null
    }

    func setVariable(_ name: String, _ value: Value) {
        _ = assembly?.vars.set(name, value)
    }

    func bindChords() -> [(id: String, chord: String)] {
        assembly?.runtime.bindChords() ?? []
    }
}

struct HandlerRules: Equatable {
    var debounce: Double?
    var throttle: Double?
    var step: Double?
    var cooldown: Double?
    var delay: Double?
    var accept: String?

    static func literal(_ value: CompiledValue?) -> Value? {
        guard let value else { return nil }
        if case .literal(let literal) = value.template { return .string(literal) }
        return nil
    }
}

extension RenderContext {
    func handler(_ element: ElementInstance, _ name: String) -> HandlerIR? {
        element.ir.handlers.first { $0.name == name }
    }

    func rules(_ element: ElementInstance, _ name: String) -> HandlerRules {
        guard let handler = handler(element, name) else { return HandlerRules() }
        func value(_ key: String) -> Value? {
            guard let compiled = handler.properties[key] else { return nil }
            if let runtime { return runtime.evaluate(compiled, on: element.identity, locals: [:]) }
            return HandlerRules.literal(compiled)
        }
        return HandlerRules(
            debounce: RuntimeDuration.seconds(value("debounce")),
            throttle: RuntimeDuration.seconds(value("throttle")),
            step: value("step").flatMap(StyleValues.numberValue),
            cooldown: RuntimeDuration.seconds(value("cooldown")),
            delay: RuntimeDuration.seconds(value("delay")),
            accept: value("accept")?.plainText
        )
    }

    func gate(_ element: ElementInstance, _ name: String) -> EventGate {
        let key = element.identity.description + "#" + name
        if let existing = gates[key] { return existing }
        let gate = EventGate(clock: clock)
        gates[key] = gate
        return gate
    }

    @discardableResult
    func fire(_ name: String, _ element: ElementInstance, _ event: Record = Record()) -> Bool {
        guard handler(element, name) != nil else { return false }
        let identity = element.identity
        gate(element, name).submit(event, rules: rules(element, name)) { [weak self] event in
            self?.dispatch(name, identity, event)
        }
        return true
    }

    func dispatch(_ name: String, _ identity: Identity, _ event: Record) {
        if let runtime {
            let task = runtime.trigger(name, on: identity, event: event)
            if let task { pending.append(task) }
        } else {
            trigger(name, identity, event)
        }
    }

    func settle() async {
        while !pending.isEmpty {
            let tasks = pending
            pending.removeAll()
            for task in tasks { await task.value }
        }
    }
}
