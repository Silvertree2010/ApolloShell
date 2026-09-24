import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
final class ProviderHarness {
    let scheduler = ManualFlushScheduler()
    let store: SignalStore
    let host: ProviderHost
    let clock = ManualRuntimeClock()
    var events: [(name: String, fields: Record)] = []
    var warnings: [Diagnostic] = []
    var recorders: [String: RecordingProvider] = [:]

    init() {
        store = SignalStore(scheduler: scheduler)
        host = ProviderHost(store: store)
        host.onEvent = { [weak self] name, fields in self?.events.append((name, fields)) }
        host.onWarning = { [weak self] diagnostic in self?.warnings.append(diagnostic) }
    }

    func register(_ provider: any ProviderInstance) {
        let recorder = RecordingProvider(provider)
        recorders[provider.schema.id] = recorder
        host.register(recorder)
        flush()
    }

    @discardableResult
    func demand(_ root: String, _ fields: String...) -> SubscriptionToken {
        let paths = Set(fields.map { DependencyPath(root, $0.split(separator: ".").map(String.init)) })
        let token = store.demand(paths.isEmpty ? [DependencyPath(root)] : paths)
        flush()
        return token
    }

    func release(_ token: SubscriptionToken) {
        store.unsubscribe(token)
        flush()
    }

    func keepAwake(_ root: String) -> SubscriptionToken {
        let token = host.keepAwake(root)
        flush()
        return token
    }

    func releaseAwake(_ token: SubscriptionToken) {
        host.unsubscribe(token)
        flush()
    }

    func flush() {
        for _ in 0..<4 { scheduler.runPending() }
    }

    func advance(_ seconds: Double) {
        var remaining = seconds
        while remaining > 0 {
            let step = min(remaining, 0.25)
            clock.advance(by: step)
            flush()
            remaining -= step
        }
    }

    func value(_ root: String, _ field: String) -> Value {
        store.value(DependencyPath(root, field.split(separator: ".").map(String.init)))
    }

    func root(_ id: String) -> Value {
        store.value(DependencyPath(id))
    }

    func perform(_ root: String, _ action: String, _ arguments: [Value] = [], properties: Record = Record()) async throws -> Value {
        guard let provider = host.provider(root) else { return .null }
        let result = try await provider.perform(action, arguments: arguments, properties: properties)
        flush()
        return result
    }

    func eventNames() -> [String] {
        events.map(\.name)
    }

    func conformanceProblems(_ schema: ProviderSchema, strict: Bool = true) -> [String] {
        ProviderConformance.problems(schema: schema, root: recorders[schema.id]?.published ?? .null, strictNullability: strict)
    }
}
