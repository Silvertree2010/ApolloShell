import Foundation
import ApolloConfig

public enum ScriptKind: String, Sendable {
    case poll
    case listen
}

public enum ScriptFormat: String, Sendable {
    case text
    case json
    case lines
}

public struct ScriptSourceSpec: Equatable, Sendable {
    public static let minimumInterval: Double = 0.5

    public var name: String
    public var command: String
    public var interval: Double
    public var format: ScriptFormat
    public var initial: Value
    public var timeout: Double

    public init(name: String, command: String, interval: Double = 5, format: ScriptFormat = .text, initial: Value = .null, timeout: Double = 10) {
        self.name = name
        self.command = command
        self.interval = interval.isFinite ? max(interval, Self.minimumInterval) : 5
        self.format = format
        self.initial = initial
        self.timeout = timeout.isFinite && timeout > 0 ? timeout : 10
    }
}

@MainActor
public protocol ScriptHandle: AnyObject {
    func terminate()
}

@MainActor
public protocol ScriptRunner: AnyObject {
    var now: Date { get }
    func run(_ command: String, _ completion: @escaping @MainActor (Int32, String) -> Void) -> (any ScriptHandle)?
    func stream(_ command: String, onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) -> (any ScriptHandle)?
}
