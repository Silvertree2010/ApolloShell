import ApolloConfig
import ApolloRuntime

@MainActor
public final class KeyboardProvider: BaseProvider {
    private let source: any KeyboardSource
    private var lastID: String??

    public init(source: any KeyboardSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("keyboard"), clock: clock)
    }

    override func didStart() {
        lastID = nil
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    override func didStop() {
        source.stopObserving()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "keyboard.next-source":
            let sources = source.sources
            guard !sources.isEmpty else { return .null }
            let index = sources.firstIndex { $0.id == source.current?.id } ?? -1
            _ = source.select(sources[(index + 1) % sources.count].id)
        case "keyboard.select":
            let id = try arguments.string(0)
            guard source.sources.contains(where: { $0.id == id }) else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown input source \"\(id)\"")
            }
            if !source.select(id) { warn("keyboard.select: \(id) could not be selected") }
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        refresh()
        return .null
    }

    private func refresh() {
        guard isRunning else { return }
        let current = source.current
        publish("source", current.map(Self.record) ?? .null)
        publish("sources", .list(source.sources.map(Self.record)))
        publish("caps-lock", .bool(source.capsLock))
        if let lastID, lastID != current?.id {
            emit("keyboard.source-changed")
        }
        lastID = .some(current?.id)
    }

    static func record(_ source: KeyboardInputSource) -> Value {
        .record(Record([("id", .string(source.id)), ("name", .string(source.name)), ("short", .string(source.short))]))
    }
}
