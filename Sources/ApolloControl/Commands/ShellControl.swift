import Foundation
import ApolloConfig

public enum SurfaceOperation: String, Sendable, CaseIterable {
    case open, close, toggle
}

public struct DiagnosticSummary: Sendable, Hashable {
    public var text: String
    public var errors: Int
    public var warnings: Int

    public init(text: String, errors: Int, warnings: Int) {
        self.text = text
        self.errors = errors
        self.warnings = warnings
    }
}

public struct ShellControlError: Error, Sendable, Hashable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

public protocol ShellControl: Sendable {
    var shellVersion: String { get }
    func reload() async -> DiagnosticSummary
    func surface(_ operation: SurfaceOperation, _ id: String) async throws
    func run(_ actions: String) async throws -> Value
    func evaluate(_ expression: String) async throws -> Value
    func watch(_ expression: String) async throws -> AsyncStream<Value>
    func variable(_ name: String) async throws -> Value
    func setVariable(_ name: String, to value: Value) async throws
    func emit(_ name: String, event: Value) async throws
    func windowManager(_ arguments: [String]) async throws -> Value
    func providers() async -> Value
    func tree(_ surface: String?) async throws -> Value
    func openCommandCenter() async
    func stats() async throws -> Value
    func restart() async
    func quit() async
    func custom(_ request: ControlRequest) async -> ControlReply
}

public enum FiniteValues {
    public static func clean(_ value: Value) -> Value {
        switch value {
        case .number(let number):
            return JSONText.finite(number)
        case .list(let items):
            return .list(items.map(clean))
        case .record(let record):
            return .record(Record(record.keys.map { ($0, clean(record[$0] ?? .null)) }))
        default:
            return value
        }
    }
}
