import Foundation
import ApolloBase
import ApolloConfig

public struct ActionEnvironment: Sendable, Hashable {
    public var scope: LocalScope
    public var surfaceID: String?
    public var screenKey: String?
    public var event: Record

    public init(scope: LocalScope = LocalScope(), surfaceID: String? = nil, screenKey: String? = nil, event: Record = Record()) {
        self.scope = scope
        self.surfaceID = surfaceID
        self.screenKey = screenKey
        self.event = event
    }
}

public struct ResolvedActionCall: Sendable, Hashable {
    public var name: String
    public var arguments: [Value]
    public var properties: Record
    public var children: [Value]
    public var span: SourceSpan

    public init(name: String, arguments: [Value] = [], properties: Record = Record(), children: [Value] = [], span: SourceSpan) {
        self.name = name
        self.arguments = arguments
        self.properties = properties
        self.children = children
        self.span = span
    }
}

public struct ActionFailure: Error, Sendable, Hashable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

@MainActor
public protocol ActionImplementation: AnyObject {
    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws
}

@MainActor
public protocol ActionRuntime: AnyObject {
    func run(_ actions: [ActionIR], environment: ActionEnvironment) async
    var vars: VarStore { get }
    var providers: ProviderHost { get }
    func warn(_ diagnostic: Diagnostic)
}

@MainActor
public protocol SurfaceControlling: AnyObject {
    func open(_ surfaceID: String, screenKey: String?)
    func close(_ surfaceID: String)
    func closeAndWait(_ surfaceID: String) async
    func toggle(_ surfaceID: String)
    func closeGroup(_ group: String)
}

public enum RuntimeDuration {
    public static func seconds(_ value: Value?) -> Double? {
        switch value {
        case .number(let number)?:
            return number.isFinite ? number : nil
        case .string(let text)?:
            return parse(text)
        default:
            return nil
        }
    }

    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let units: [(String, Double)] = [("ms", 0.001), ("s", 1), ("m", 60), ("h", 3600)]
        for (suffix, factor) in units where trimmed.hasSuffix(suffix) {
            let number = trimmed.dropLast(suffix.count)
            guard !number.isEmpty, number.allSatisfy({ $0.isNumber || $0 == "." }), let amount = Double(number), amount.isFinite else { return nil }
            return amount * factor
        }
        guard let amount = Double(trimmed), amount.isFinite else { return nil }
        return amount
    }
}

enum TemplateValues {
    static func evaluate(_ template: ValueTemplate, _ scalar: (CompiledValue) -> Value) -> Value {
        switch template {
        case .scalar(let compiled):
            return scalar(compiled)
        case .list(let items):
            return .list(items.map { evaluate($0, scalar) })
        case .record(let fields):
            var record = Record()
            for field in fields {
                record[field.name] = evaluate(field.value, scalar)
            }
            return .record(record)
        }
    }
}
