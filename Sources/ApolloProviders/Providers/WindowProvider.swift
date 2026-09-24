import ApolloConfig
import ApolloRuntime

@MainActor
public final class WindowProvider: BaseProvider {
    private let source: any WindowSource
    public var appRecord: (@MainActor (String) -> Value?)?

    public init(source: any WindowSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("window"), clock: clock)
    }

    override func didStart() {
        source.start { [weak self] state in
            self?.apply(state)
        }
    }

    override func didStop() {
        source.stop()
    }

    private func apply(_ state: FrontWindowState?) {
        guard isRunning else { return }
        publish("app", state.flatMap(record) ?? .null)
        publish("title", ProviderValue.string(state?.title))
        publish("fullscreen", .bool(state?.fullscreen ?? false))
    }

    private func record(_ state: FrontWindowState) -> Value? {
        guard let id = state.bundleID else { return nil }
        if let resolved = appRecord?(id) { return resolved }
        return .record(Record([
            ("bundle-id", .string(id)),
            ("name", .string(state.appName ?? id)),
            ("path", ProviderValue.string(state.appPath)),
            ("icon", .image(ImageRef(source: "app-icon", id: id))),
        ]))
    }
}
