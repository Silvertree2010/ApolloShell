import AppKit
import ApolloShellCore
import ApolloConfig
import ApolloRuntime

struct AppMenuWindow: Equatable {
    var title: String
    var minimized: Bool
}

@MainActor
protocol AppMenuSystem {
    func dockMenu(_ bundleID: String) async -> [DockMenuNode]
    func pressDock(_ path: [DockMenuStep], _ bundleID: String)
    func isRunning(_ bundleID: String) -> Bool
    func isHidden(_ bundleID: String) -> Bool
    func windows(_ bundleID: String) -> [AppMenuWindow]
    func raiseWindow(_ bundleID: String, index: Int)
    func commands(_ bundleID: String, newItemsOnly: Bool) -> [String]
    var fileManagerName: String { get }
}

@MainActor
final class AppMenuSources: MenuSourceProviding {
    static let kinds = ["app-dock", "app-commands", "app-windows"]

    let system: any AppMenuSystem

    init(system: any AppMenuSystem) {
        self.system = system
    }

    func entries(_ kind: String, properties: [String: Value], element: ElementInstance, context: RenderContext) async -> [ElementMenuEntry] {
        guard let app = Self.bundleID(properties["app"] ?? .null) else { return [] }
        var record: Record?
        if case .record(let fields) = properties["app"] ?? .null { record = fields }
        let act: @MainActor (String, [String]) -> Void = { [weak context] action, arguments in
            guard let task = context?.runtime?.perform(action, [app] + arguments, on: element.identity) else { return }
            context?.pending.append(task)
        }
        switch kind {
        case "app-dock":
            let nodes = await system.dockMenu(app)
            if !nodes.isEmpty { return mirrored(nodes, app: app, pinned: record?["dock-pinned"]?.isTruthy ?? false, act: act) }
            if properties["fallback"]?.plainText == "commands" { return commandEntries(app, newItemsOnly: false, act: act) }
            return full(app, name: record?["name"]?.plainText ?? app, pinned: record?["dock-pinned"]?.isTruthy ?? false, act: act)
        case "app-commands":
            var result = commandEntries(app, newItemsOnly: false, act: act)
            if !result.isEmpty { result.append(.separator) }
            result.append(.item(ElementMenuCommand(title: "Show in Finder", perform: { act("apps.reveal", ["finder"]) })))
            return result
        case "app-windows":
            return windowEntries(app, name: record?["name"]?.plainText ?? app)
        default:
            return []
        }
    }

    static func bundleID(_ value: Value) -> String? {
        switch value {
        case .string(let id) where !id.isEmpty: return id
        case .record(let record):
            if case .string(let id) = record["bundle-id"] ?? .null, !id.isEmpty { return id }
            return nil
        default: return nil
        }
    }

    func mirrored(_ nodes: [DockMenuNode], app: String, pinned: Bool, act: @escaping @MainActor (String, [String]) -> Void) -> [ElementMenuEntry] {
        nodes.map { node in
            if node.separator { return .separator }
            if !node.children.isEmpty { return .submenu(node.title, mirrored(node.children, app: app, pinned: pinned, act: act)) }
            if DockMenuTree.isKeepInDock(node.title) {
                return .item(ElementMenuCommand(title: node.title, checked: pinned, perform: { act(pinned ? "apps.dock-unpin" : "apps.dock-pin", []) }))
            }
            let path = node.path
            let system = self.system
            return .item(ElementMenuCommand(title: node.title, checked: node.checked, disabled: !node.enabled, perform: { system.pressDock(path, app) }))
        }
    }

    func windowEntries(_ app: String, name: String) -> [ElementMenuEntry] {
        let windows = system.windows(app)
        let front = windows.firstIndex { !$0.minimized }
        let system = self.system
        return windows.enumerated().map { index, window in
            .item(ElementMenuCommand(title: window.title.isEmpty ? name : window.title, icon: window.minimized ? "minus.circle" : "macwindow",
                                     checked: index == front, perform: { system.raiseWindow(app, index: index) }))
        }
    }

    func commandEntries(_ app: String, newItemsOnly: Bool, act: @escaping @MainActor (String, [String]) -> Void) -> [ElementMenuEntry] {
        guard system.isRunning(app) else { return [] }
        return system.commands(app, newItemsOnly: newItemsOnly).map { title in
            .item(ElementMenuCommand(title: title, perform: { act("apps.run-command", [title]) }))
        }
    }

    func full(_ app: String, name: String, pinned: Bool, act: @escaping @MainActor (String, [String]) -> Void) -> [ElementMenuEntry] {
        var result: [ElementMenuEntry] = []
        let running = system.isRunning(app)
        if running {
            let windows = windowEntries(app, name: name)
            result += windows
            if !windows.isEmpty { result.append(.separator) }
            let commands = commandEntries(app, newItemsOnly: true, act: act)
            result += commands
            if !commands.isEmpty { result.append(.separator) }
        } else {
            result.append(.item(ElementMenuCommand(title: "Open", perform: { act("apps.launch", []) })))
            result.append(.separator)
        }
        result.append(.submenu("Options", [
            .item(ElementMenuCommand(title: "Keep in Dock", checked: pinned, perform: { act(pinned ? "apps.dock-unpin" : "apps.dock-pin", []) })),
            .item(ElementMenuCommand(title: "Show in " + system.fileManagerName, perform: { act("apps.reveal", []) })),
        ]))
        if running {
            let hidden = system.isHidden(app)
            result.append(.separator)
            result.append(.item(ElementMenuCommand(title: "Show All Windows", perform: { act("apps.show-all-windows", []) })))
            result.append(.item(ElementMenuCommand(title: hidden ? "Show" : "Hide", perform: { act(hidden ? "apps.unhide" : "apps.hide", []) })))
            result.append(.item(ElementMenuCommand(title: "Quit", perform: { act("apps.quit", []) })))
            result.append(.item(ElementMenuCommand(title: "Force Quit", alternate: true, perform: { act("apps.force-quit", []) })))
        }
        return result
    }
}

@MainActor
final class LiveAppMenuSystem: AppMenuSystem {
    func dockMenu(_ bundleID: String) async -> [DockMenuNode] {
        await AppleDockMenu.snapshot(bundleID: bundleID)
    }

    func pressDock(_ path: [DockMenuStep], _ bundleID: String) {
        Task { _ = await AppleDockMenu.press(path: path, bundleID: bundleID) }
    }

    private func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    func isRunning(_ bundleID: String) -> Bool { running(bundleID) != nil }

    func isHidden(_ bundleID: String) -> Bool { running(bundleID)?.isHidden ?? false }

    func windows(_ bundleID: String) -> [AppMenuWindow] {
        guard let app = running(bundleID) else { return [] }
        return DockWindows.list(pid: app.processIdentifier, allSpaces: true).map { AppMenuWindow(title: $0.title, minimized: $0.minimized) }
    }

    func raiseWindow(_ bundleID: String, index: Int) {
        guard let app = running(bundleID) else { return }
        let windows = DockWindows.list(pid: app.processIdentifier, allSpaces: true)
        guard windows.indices.contains(index) else { return }
        DockWindows.raise(windows[index], of: app)
    }

    func commands(_ bundleID: String, newItemsOnly: Bool) -> [String] {
        guard let app = running(bundleID) else { return [] }
        return DockAppCommands.commands(pid: app.processIdentifier).filter { !newItemsOnly || $0.kind == .newItem }.map(\.title)
    }

    var fileManagerName: String {
        guard let id = UserDefaults.standard.string(forKey: "NSFileViewer"),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return "Finder" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

extension RenderContext {
    func connectLive(_ assembly: ShellAssembly) {
        runtime = AssemblyRenderRuntime(assembly)
        let sources = AppMenuSources(system: LiveAppMenuSystem())
        for kind in AppMenuSources.kinds { menuSources[kind] = sources }
    }
}
