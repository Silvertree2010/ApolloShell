import ApolloBase
import ApolloConfig
import ApolloRuntime

@MainActor
public class BaseProvider: ProviderInstance {
    public let schema: ProviderSchema
    public let clock: any RuntimeClock
    public let timers: ProviderTimers
    public private(set) var context: ProviderContext?
    public private(set) var demand = DemandSet()

    public var isRunning: Bool { context != nil }

    public init(schema: ProviderSchema, clock: any RuntimeClock) {
        self.schema = schema
        self.clock = clock
        timers = ProviderTimers(clock: clock)
    }

    public func start(_ context: ProviderContext) {
        self.context = context
        demand = DemandSet()
        didStart()
    }

    public func demandChanged(_ demanded: Set<DependencyPath>) {
        demand = DemandSet(demanded)
        guard isRunning else { return }
        didChangeDemand()
    }

    public func configure(_ settings: Record) {
        didConfigure(settings)
    }

    public func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value {
        try await handle(ActionArguments(action, arguments, properties))
    }

    public func stop() {
        timers.cancelAll()
        didStop()
        context = nil
        demand = DemandSet()
    }

    func didStart() {}

    func didChangeDemand() {}

    func didStop() {}

    func didConfigure(_ settings: Record) {}

    func handle(_ arguments: ActionArguments) async throws -> Value {
        throw ProviderActionError.unknownAction(arguments.action)
    }

    func publish(_ field: String, _ value: Value) {
        context?.publish(field.split(separator: ".").map(String.init), value)
    }

    func emit(_ event: String, _ fields: Record = Record()) {
        context?.emit(event, fields)
    }

    func note(_ message: String) {
        context?.warn(Diagnostic(.note, message, span: .synthetic(schema.id)))
    }

    func warn(_ message: String) {
        context?.warn(Diagnostic(.warning, message, span: .synthetic(schema.id)))
    }
}

public enum ProviderValue {
    public static func number(_ value: Double?) -> Value {
        guard let value, value.isFinite else { return .null }
        return .number(value)
    }

    public static func number(_ value: Int?) -> Value {
        value.map { .number(Double($0)) } ?? .null
    }

    public static func string(_ value: String?) -> Value {
        value.map(Value.string) ?? .null
    }

    public static func bool(_ value: Bool?) -> Value {
        value.map(Value.bool) ?? .null
    }
}

public enum BuiltinProviderSchemas {
    public static func schema(_ id: String) -> ProviderSchema {
        SchemaRegistry.builtin.providers[id] ?? ProviderSchema(id: id, doc: "")
    }
}
