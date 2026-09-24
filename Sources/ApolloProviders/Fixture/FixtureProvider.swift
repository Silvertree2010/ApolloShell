import ApolloConfig
import ApolloRuntime

@MainActor
public final class FixtureProvider: ProviderInstance {
    public let schema: ProviderSchema
    public let values: Record
    private let onAction: @MainActor (String, [Value], Record) -> Void
    private var context: ProviderContext?

    public init(schema: ProviderSchema, values: Record, onAction: @escaping @MainActor (String, [Value], Record) -> Void = { _, _, _ in }) {
        self.schema = schema
        self.values = Self.filled(values, schema: schema)
        self.onAction = onAction
    }

    public static func all(
        fixture: ProviderFixture,
        registry: SchemaRegistry = .builtin,
        onAction: @escaping @MainActor (String, [Value], Record) -> Void = { _, _, _ in }
    ) -> [FixtureProvider] {
        registry.providers.keys.sorted().compactMap { id in
            registry.providers[id].map { FixtureProvider(schema: $0, values: fixture.values[id] ?? Record(), onAction: onAction) }
        }
    }

    public func start(_ context: ProviderContext) {
        self.context = context
        context.publish([], .record(values))
    }

    public func demandChanged(_ demanded: Set<DependencyPath>) {}

    public func configure(_ settings: Record) {}

    public func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value {
        guard schema.actions.contains(where: { $0.name == action }) else {
            throw ProviderActionError.unknownAction(action)
        }
        onAction(action, arguments, properties)
        return .null
    }

    public func stop() {
        context = nil
    }

    static func filled(_ values: Record, schema: ProviderSchema) -> Record {
        var root = Value.record(values)
        for field in schema.fields where ProviderConformance.lookup(root, field.path) == nil {
            root = insert(root, field.path, field.type == .list ? .list([]) : .null)
        }
        guard case .record(let record) = root else { return values }
        return record
    }

    static func insert(_ value: Value, _ path: [String], _ newValue: Value) -> Value {
        guard let first = path.first else { return newValue }
        var record: Record
        if case .record(let existing) = value { record = existing } else { record = Record() }
        record[first] = insert(record[first] ?? .null, Array(path.dropFirst()), newValue)
        return .record(record)
    }
}
