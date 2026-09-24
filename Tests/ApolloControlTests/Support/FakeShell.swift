import Foundation
import ApolloConfig
@testable import ApolloControl

final class FakeShell: ShellControl, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    let probe = StreamProbe()
    var reloadSummary = DiagnosticSummary(text: "", errors: 0, warnings: 0)
    var variables: [String: Value] = ["index": .number(3)]

    var calls: [String] { lock.withLock { log } }

    private func record(_ entry: String) {
        lock.withLock { log.append(entry) }
    }

    let shellVersion = "0.2.0-test"

    func reload() async -> DiagnosticSummary {
        record("reload")
        return reloadSummary
    }

    func surface(_ operation: SurfaceOperation, _ id: String) async throws {
        guard id != "missing" else { throw ShellControlError("no surface named 'missing'") }
        record("\(operation.rawValue) \(id)")
    }

    func run(_ actions: String) async throws -> Value {
        record("run \(actions)")
        return .null
    }

    func evaluate(_ expression: String) async throws -> Value {
        record("eval \(expression)")
        return .record(Record([("sum", .number(2)), ("bad", .number(.nan))]))
    }

    func watch(_ expression: String) async throws -> AsyncStream<Value> {
        record("watch \(expression)")
        return probe.makeStream()
    }

    func variable(_ name: String) async throws -> Value {
        guard let value = lock.withLock({ variables[name] }) else { throw ShellControlError("no var named '\(name)'") }
        return value
    }

    func setVariable(_ name: String, to value: Value) async throws {
        record("set \(name) \(JSONText.encode(value))")
        lock.withLock { variables[name] = value }
    }

    func emit(_ name: String, event: Value) async throws {
        record("emit \(name) \(JSONText.encode(event))")
    }

    func windowManager(_ arguments: [String]) async throws -> Value {
        record("wm \(arguments.joined(separator: " "))")
        return arguments == ["windows"] ? .list([.record(Record([("id", .number(1))]))]) : .null
    }

    func providers() async -> Value {
        record("providers")
        return .record(Record([("battery", .record(Record([("percent", .number(0.5))])))]))
    }

    func tree(_ surface: String?) async throws -> Value {
        record("tree \(surface ?? "-")")
        return .list([.string("panel#sidebar")])
    }

    func openCommandCenter() async {
        record("command-center")
    }

    func stats() async throws -> Value {
        throw ShellControlError("stats need the start argument --perf-probe")
    }

    func restart() async {
        record("restart")
    }

    func quit() async {
        record("quit")
    }

    func custom(_ request: ControlRequest) async -> ControlReply {
        record("custom \(request.cmd) \(JSONText.encode(.record(request.args)))")
        return .success(.string("custom ok"))
    }
}
