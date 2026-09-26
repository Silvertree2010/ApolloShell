import Foundation
import os
import ApolloBase
import ApolloConfig

@MainActor
public final class ActionDispatcher: ActionRuntime {
    static let maximumWait: Double = 10
    static let maximumRepeat = 100

    private let evaluator: Evaluator
    private let store: SignalStore
    let clock: any RuntimeClock
    private var implementations: [String: any ActionImplementation] = [:]
    private var runningSites: [String: Int] = [:]
    private var warnedSites: Set<String> = []
    private let warningBuffer = WarningBuffer()
    private let logger = Logger(subsystem: "ApolloShell", category: "actions")

    public let vars: VarStore
    public let providers: ProviderHost
    public weak var surfaces: (any SurfaceControlling)?
    public var onWarning: (@MainActor (Diagnostic) -> Void)?

    public init(evaluator: Evaluator, vars: VarStore, providers: ProviderHost, store: SignalStore, clock: any RuntimeClock = DispatchRuntimeClock()) {
        self.evaluator = evaluator
        self.vars = vars
        self.providers = providers
        self.store = store
        self.clock = clock
    }

    public func register(_ name: String, _ implementation: any ActionImplementation) {
        implementations[name] = implementation
    }

    public static let builtinNames: Set<String> = ["open", "close", "toggle", "close-group", "wait", "repeat"]

    public func handles(_ name: String) -> Bool {
        if Self.builtinNames.contains(name) || StateActions.names.contains(name) || implementations[name] != nil { return true }
        guard let dot = name.firstIndex(of: ".") else { return false }
        return providers.provider(String(name[..<dot])) != nil
    }

    public func isRunning(site: String) -> Bool {
        runningSites[site, default: 0] > 0
    }

    @discardableResult
    public func trigger(_ actions: [ActionIR], site: String?, environment: ActionEnvironment) -> Task<Void, Never>? {
        if let site {
            if isRunning(site: site), Self.guardsAgainstRepeat(actions) {
                return nil
            }
            runningSites[site, default: 0] += 1
        }
        return Task.immediate { @MainActor [self] in
            await self.run(actions, environment: environment)
            if let site {
                self.release(site)
            }
        }
    }

    public func run(_ actions: [ActionIR], environment: ActionEnvironment) async {
        for action in actions {
            await execute(action, environment)
        }
    }

    public func warn(_ diagnostic: Diagnostic) {
        let site = diagnostic.span.map { "\($0.file):\($0.start.offset):\($0.start.line):\($0.start.column)" } ?? ""
        guard warnedSites.insert(site + "|" + diagnostic.message).inserted else { return }
        onWarning?(diagnostic)
    }

    public func forgetWarnings() {
        warnedSites.removeAll()
    }

    static func guardsAgainstRepeat(_ actions: [ActionIR]) -> Bool {
        var pending = actions
        while let action = pending.popLast() {
            switch action {
            case .call(let call):
                if ["close", "close-group", "toggle"].contains(call.name) { return true }
            case .when(_, let then, let otherwise):
                pending.append(contentsOf: then)
                pending.append(contentsOf: otherwise)
            case .switchOn(_, let cases, let otherwise):
                for item in cases { pending.append(contentsOf: item.body) }
                pending.append(contentsOf: otherwise)
            case .each(_, _, _, let body), .repeatBlock(_, let body):
                pending.append(contentsOf: body)
            }
        }
        return false
    }

    private func release(_ site: String) {
        let count = runningSites[site, default: 1] - 1
        if count <= 0 {
            runningSites.removeValue(forKey: site)
        } else {
            runningSites[site] = count
        }
    }

    private func execute(_ action: ActionIR, _ environment: ActionEnvironment) async {
        switch action {
        case .call(let call):
            await perform(call, environment)
        case .when(let condition, let then, let otherwise):
            await run(evaluate(condition, environment).isTruthy ? then : otherwise, environment: environment)
        case .switchOn(let subject, let cases, let otherwise):
            let value = evaluate(subject, environment)
            let chosen = cases.first { item in item.values.contains { evaluate($0, environment) == value } }
            await run(chosen?.body ?? otherwise, environment: environment)
        case .each(let variable, let index, let list, let body):
            let value = evaluate(list, environment)
            guard case .list(let items) = value else {
                if value != .null {
                    fail(ActionFailure("each needs a list, got \(value.typeName)"), span: list.span)
                }
                return
            }
            for (position, item) in items.enumerated() {
                var inner = environment
                inner.scope = inner.scope.adding(variable, item)
                if let index {
                    inner.scope = inner.scope.adding(index, .number(Double(position)))
                }
                await run(body, environment: inner)
            }
        case .repeatBlock(let count, let body):
            let value = evaluate(count, environment)
            guard case .number(let number) = value, number.isFinite else {
                fail(ActionFailure("repeat needs a number, got \(value.typeName)"), span: count.span)
                return
            }
            var times = max(0, Int(Swift.min(number, Double(Self.maximumRepeat + 1)).rounded(.down)))
            if times > Self.maximumRepeat {
                warn(Diagnostic(.warning, "repeat is capped at \(Self.maximumRepeat), got \(Self.text(.number(number.rounded(.down))) ?? "")", span: count.span))
                times = Self.maximumRepeat
            }
            for _ in 0..<times {
                await run(body, environment: environment)
            }
        }
    }

    private func perform(_ call: ActionCallIR, _ environment: ActionEnvironment) async {
        let resolved = resolve(call, environment)
        let waits = resolved.properties["wait"] == .bool(true)
        do {
            switch call.name {
            case "open":
                surfaces?.open(try string(resolved, 0, "surface id"), screenKey: resolved.properties["screen"].flatMap(Self.text))
            case "close":
                let id = try string(resolved, 0, "surface id")
                if waits {
                    await surfaces?.closeAndWait(id)
                } else {
                    surfaces?.close(id)
                }
            case "toggle":
                surfaces?.toggle(try string(resolved, 0, "surface id"))
            case "close-group":
                surfaces?.closeGroup(try string(resolved, 0, "group"))
            case "wait":
                try await waitAction(resolved)
            case _ where StateActions.names.contains(call.name):
                try StateActions(vars: vars).perform(resolved)
            default:
                try await performExternal(resolved, environment, waits: waits)
            }
        } catch {
            fail(error, span: call.span)
        }
    }

    private func performExternal(_ call: ResolvedActionCall, _ environment: ActionEnvironment, waits: Bool) async throws {
        let operation: @MainActor () async throws -> Void
        if let implementation = implementations[call.name] {
            operation = { [self] in try await implementation.perform(call, environment: environment, runtime: self) }
        } else if let dot = call.name.firstIndex(of: "."), let provider = providers.provider(String(call.name[..<dot])) {
            let action = call.name
            operation = { _ = try await provider.perform(action, arguments: call.arguments, properties: call.properties) }
        } else {
            throw ActionFailure("unknown action '\(call.name)'")
        }
        if waits {
            try await operation()
            return
        }
        let span = call.span
        Task.immediate { @MainActor [self] in
            do {
                try await operation()
            } catch {
                self.fail(error, span: span)
            }
        }
    }

    private func waitAction(_ call: ResolvedActionCall) async throws {
        guard var seconds = RuntimeDuration.seconds(call.arguments.first), seconds >= 0 else {
            throw ActionFailure("wait needs a duration like \"500ms\" or \"2s\"")
        }
        if seconds > Self.maximumWait {
            warn(Diagnostic(.warning, "wait is capped at 10s, got \(RuntimeDuration.describe(seconds))", span: call.span))
            seconds = Self.maximumWait
        }
        guard seconds > 0 else { return }
        await sleep(seconds)
    }

    func sleep(_ seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _ = clock.schedule(after: seconds) {
                continuation.resume()
            }
        }
    }

    private func resolve(_ call: ActionCallIR, _ environment: ActionEnvironment) -> ResolvedActionCall {
        let arguments = call.arguments.map { evaluate($0, environment) }
        var properties = Record()
        for name in call.properties.keys.sorted() {
            if let compiled = call.properties[name] {
                properties[name] = evaluate(compiled, environment)
            }
        }
        let children = call.children.map { TemplateValues.evaluate($0) { evaluate($0, environment) } }
        return ResolvedActionCall(name: call.name, arguments: arguments, properties: properties, children: children, span: call.span)
    }

    func evaluate(_ compiled: CompiledValue, _ environment: ActionEnvironment) -> Value {
        let buffer = warningBuffer
        let pinned = evaluator.pinningContext(warn: { buffer.append($0) })
        vars.freshen(compiled.dependencies)
        let scope = BindingScope(snapshot: store.snapshot(), locals: environment.scope, event: environment.event)
        let value = pinned.render(compiled.template, in: scope, at: compiled.span)
        for diagnostic in buffer.drain() {
            warn(diagnostic)
        }
        return value
    }

    private func fail(_ error: any Error, span: SourceSpan) {
        let message: String
        switch error {
        case let diagnostic as Diagnostic:
            message = diagnostic.message
        case let failure as ActionFailure:
            message = failure.message
        default:
            message = "action failed: \(error)"
        }
        logger.warning("\(span.file, privacy: .public):\(span.start.line): \(message, privacy: .public)")
        warn(Diagnostic(.warning, message, span: span))
    }

    private func string(_ call: ResolvedActionCall, _ index: Int, _ label: String) throws -> String {
        guard index < call.arguments.count, let text = Self.text(call.arguments[index]), !text.isEmpty else {
            throw ActionFailure("\(call.name) needs a \(label)")
        }
        return text
    }

    static func text(_ value: Value) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number) where number == number.rounded() && abs(number) < 1e15: String(Int(number))
        case .number(let number) where number == number.rounded() && number.isFinite: String(number)
        default: nil
        }
    }
}

extension RuntimeDuration {
    static func describe(_ seconds: Double) -> String {
        seconds == seconds.rounded() && abs(seconds) < 1e15 ? "\(Int(seconds))s" : "\(seconds)s"
    }
}
