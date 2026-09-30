import AppKit
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
import ApplicationServices

@MainActor
final class MenuBarMenuSources: MenuSourceProviding {
    static let kinds = ["app-menubar", "status-item"]

    let menuBar: SystemMenuBarSource
    let statusItems: SystemStatusItemsSource
    var trusted: () -> Bool = { AXIsProcessTrusted() }

    init(menuBar: SystemMenuBarSource, statusItems: SystemStatusItemsSource) {
        self.menuBar = menuBar
        self.statusItems = statusItems
    }

    func entries(_ kind: String, properties: [String: Value], element: ElementInstance, context: RenderContext) async -> [ElementMenuEntry] {
        guard trusted() else { return AXMenuEntries.permission() }
        switch kind {
        case "app-menubar":
            let menuBar = self.menuBar
            let press: @MainActor ([AXMenuStep]) -> Void = { menuBar.press(steps: $0) }
            if properties["overflow"]?.isTruthy == true {
                let indices = Self.indices(context.menuOverflow[element.identity] ?? [])
                return await menuBar.menus(indices).map { .submenu($0.title, AXMenuEntries.entries($0.nodes, press: press)) }
            }
            guard let index = properties["index"].flatMap(StyleValues.numberValue) else { return [] }
            let menus = await menuBar.menus([Int(index)])
            defer { menuBar.menuClosed() }
            return menus.first.map { AXMenuEntries.entries($0.nodes, press: press) } ?? []
        case "status-item":
            guard let id = Self.itemID(properties["item"] ?? .null) else { return [] }
            if let nodes = await statusItems.menu(id) {
                let items = statusItems
                return AXMenuEntries.entries(nodes) { items.press(id, path: $0) }
            }
            _ = await statusItems.click(id)
            return []
        default:
            return []
        }
    }

    static func indices(_ values: [Value]) -> [Int] {
        values.compactMap { value in
            if case .number(let number) = value { return Int(number) }
            if case .record(let record) = value, case .number(let number)? = record["index"] { return Int(number) }
            return nil
        }
    }

    static func itemID(_ value: Value) -> String? {
        switch value {
        case .string(let id) where !id.isEmpty: return id
        case .record(let record):
            if case .string(let id)? = record["id"], !id.isEmpty { return id }
            return nil
        default: return nil
        }
    }
}
