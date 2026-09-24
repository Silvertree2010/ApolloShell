import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
final class StubProvider: ProviderInstance {
    let schema: ProviderSchema
    var startCount = 0
    var stopCount = 0
    var demandChangedCount = 0
    var lastDemand: Set<DependencyPath> = []
    var lastContext: ProviderContext?
    var configuredSettings: [Record] = []
    var failOnStart = false

    init(id: String) {
        schema = ProviderSchema(id: id, doc: "stub")
    }

    func start(_ context: ProviderContext) {
        startCount += 1
        lastContext = context
        if failOnStart {
            context.warn(Diagnostic(.warning, "provider \"\(schema.id)\" failed to start", span: .synthetic()))
        }
    }

    func demandChanged(_ demanded: Set<DependencyPath>) {
        demandChangedCount += 1
        lastDemand = demanded
    }

    func configure(_ settings: Record) {
        configuredSettings.append(settings)
    }

    func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value {
        .null
    }

    func stop() {
        stopCount += 1
    }
}
