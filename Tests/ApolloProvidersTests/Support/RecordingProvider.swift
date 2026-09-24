import ApolloConfig
@testable import ApolloRuntime

@MainActor
final class RecordingProvider: ProviderInstance {
    let inner: any ProviderInstance
    private(set) var published: Value = .record(Record())

    init(_ inner: any ProviderInstance) {
        self.inner = inner
    }

    var schema: ProviderSchema { inner.schema }

    func start(_ context: ProviderContext) {
        let recording = ProviderContext(
            publish: { [weak self] fields, value in
                if let self { self.published = Self.write(self.published, fields, value) }
                context.publish(fields, value)
            },
            emit: context.emit,
            warn: context.warn
        )
        inner.start(recording)
    }

    func demandChanged(_ demanded: Set<DependencyPath>) { inner.demandChanged(demanded) }

    func configure(_ settings: Record) { inner.configure(settings) }

    func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value {
        try await inner.perform(action, arguments: arguments, properties: properties)
    }

    func stop() { inner.stop() }

    static func write(_ value: Value, _ fields: [String], _ newValue: Value) -> Value {
        guard let first = fields.first else { return newValue }
        var record: Record
        if case .record(let existing) = value { record = existing } else { record = Record() }
        record[first] = write(record[first] ?? .null, Array(fields.dropFirst()), newValue)
        return .record(record)
    }
}
