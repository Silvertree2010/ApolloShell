import Foundation
import ApolloConfig
import ApolloRuntime

@MainActor
public final class MenuBarProvider: BaseProvider {
    private let source: any MenuBarSource

    public init(source: any MenuBarSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("menubar"), clock: clock)
    }

    override func didChangeDemand() {
        if demand.wantsAny(["app-name", "bundle-id", "menus", "trusted"]) {
            source.start { [weak self] state in self?.apply(state) }
        } else {
            source.stop()
        }
    }

    override func didStop() {
        source.stop()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "menubar.press" else { throw ProviderActionError.unknownAction(arguments.action) }
        let path = arguments.values.compactMap { value -> String? in
            if case .string(let text) = value { return text }
            return nil
        }
        guard !path.isEmpty else {
            throw ProviderActionError.invalidArgument(action: arguments.action, message: "needs a menu title and an entry title")
        }
        if !(await source.press(path)) { warn("menubar.press: no entry \(path.joined(separator: " > "))") }
        return .null
    }

    private func apply(_ state: MenuBarState?) {
        guard isRunning else { return }
        publish("app-name", .string(state.map(Self.appTitle) ?? ""))
        publish("bundle-id", ProviderValue.string(state?.bundleID))
        publish("menus", .list(state.map(Self.menus) ?? []))
        publish("trusted", .bool(state?.trusted ?? false))
    }

    public static func appTitle(_ state: MenuBarState) -> String {
        state.titles.count > 1 && !state.titles[1].isEmpty ? state.titles[1] : state.appName
    }

    public static func menus(_ state: MenuBarState) -> [Value] {
        var titles = state.titles
        if titles.count < 2 { titles = ["Apple", appTitle(state)] }
        titles[1] = appTitle(state)
        return titles.enumerated().map { index, title in
            .record(Record([
                ("index", .number(Double(index))),
                ("title", .string(title)),
                ("apple", .bool(index == 0)),
                ("app", .bool(index == 1)),
            ]))
        }
    }
}

@MainActor
public final class StatusItemsProvider: BaseProvider {
    private let source: any StatusItemsSource

    public init(source: any StatusItemsSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("status-items"), clock: clock)
    }

    override func didChangeDemand() {
        if demand.wants("list") {
            source.start { [weak self] items in self?.apply(items) }
        } else {
            source.stop()
        }
    }

    override func didStop() {
        source.stop()
    }

    public func imageData(_ id: String) -> Data? {
        source.imageData(Self.itemID(id))
    }

    static func itemID(_ imageID: String) -> String {
        imageID.split(separator: "#", maxSplits: 1).first.map(String.init) ?? imageID
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "status-items.click" else { throw ProviderActionError.unknownAction(arguments.action) }
        let id: String
        switch try arguments.value(0) {
        case .string(let text): id = text
        case .record(let record):
            if case .string(let text)? = record["id"] { id = text } else { id = "" }
        default: id = ""
        }
        guard !id.isEmpty else { throw ProviderActionError.invalidArgument(action: arguments.action, message: "needs a status item id") }
        if !(await source.click(id)) { warn("status-items.click: status item \(id) is gone") }
        return .null
    }

    private func apply(_ items: [StatusItemState]) {
        guard isRunning else { return }
        publish("list", .list(items.map(Self.record)))
    }

    public static func record(_ item: StatusItemState) -> Value {
        .record(Record([
            ("id", .string(item.id)),
            ("app", ProviderValue.string(item.app)),
            ("name", .string(item.name)),
            ("title", .string(item.title)),
            ("image", item.hasImage ? .image(ImageRef(source: "status-item", id: "\(item.id)#\(item.imageVersion)")) : .null),
            ("kind", ProviderValue.string(item.kind)),
            ("monochrome", .bool(item.monochrome)),
            ("symbol", ProviderValue.string(item.symbol)),
        ]))
    }
}
