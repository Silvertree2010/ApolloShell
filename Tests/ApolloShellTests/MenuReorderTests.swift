import Testing
import Foundation
import AppKit
import ApolloConfig
import ApolloShellCore
import ApolloRuntime
@testable import ApolloShell

@MainActor
final class RecordingRuntime: RenderRuntime {
    let inner: any RenderRuntime
    var performed: [String] = []

    init(_ inner: any RenderRuntime) {
        self.inner = inner
    }

    func trigger(_ handler: String, on identity: Identity, event: Record) -> Task<Void, Never>? { inner.trigger(handler, on: identity, event: event) }
    func run(_ actions: [ActionIR], on identity: Identity, site: String, event: Record, locals: [String: Value]) -> Task<Void, Never>? {
        inner.run(actions, on: identity, site: site, event: event, locals: locals)
    }
    func evaluate(_ value: CompiledValue, on identity: Identity, locals: [String: Value]) -> Value { inner.evaluate(value, on: identity, locals: locals) }
    func variable(_ name: String) -> Value { inner.variable(name) }
    func setVariable(_ name: String, _ value: Value) { inner.setVariable(name, value) }
    func bindChords() -> [(id: String, chord: String)] { inner.bindChords() }
    func perform(_ action: String, _ arguments: [String], on identity: Identity) -> Task<Void, Never>? {
        performed.append(([action] + arguments).joined(separator: " "))
        return nil
    }
}

@MainActor
final class FakeAppMenuSystem: AppMenuSystem {
    var dock: [DockMenuNode] = []
    var running = true
    var hidden = false
    var windowList = [AppMenuWindow(title: "", minimized: true), AppMenuWindow(title: "Two", minimized: false)]
    var raised: [Int] = []
    var pressed: [[DockMenuStep]] = []

    func dockMenu(_ bundleID: String) async -> [DockMenuNode] { dock }
    func pressDock(_ path: [DockMenuStep], _ bundleID: String) { pressed.append(path) }
    func isRunning(_ bundleID: String) -> Bool { running }
    func isHidden(_ bundleID: String) -> Bool { hidden }
    func windows(_ bundleID: String) -> [AppMenuWindow] { running ? windowList : [] }
    func raiseWindow(_ bundleID: String, index: Int) { raised.append(index) }
    func commands(_ bundleID: String, newItemsOnly: Bool) -> [String] { newItemsOnly ? ["New Window"] : ["New Window", "Settings…"] }
    var fileManagerName: String { "ForkLift" }
}

extension ElementMenuEntry {
    var flat: [String] {
        switch self {
        case .submenu(let title, let children): [title + " >"] + children.flatMap(\.flat).map { "  " + $0 }
        case .item(let command): [(command.checked ? "✓ " : "") + (command.alternate ? "⌥ " : "") + command.title + (command.disabled ? " (off)" : "")]
        default: [self.title]
        }
    }

    var command: ElementMenuCommand? {
        if case .item(let command) = self { return command }
        return nil
    }
}

@MainActor
@Suite("Render: menu und reorderable (blocks.md 4.3, 4.5)", .serialized)
struct MenuReorderTests {
    static let menuConfig = """
    var picked ""
    var mode "b"
    panel "t" anchor="left" {
        each app in="{['alpha', 'beta']}" index="i" {
            button id="b-{app}" class="b" menu-on="right-click" {
                menu side="right" {
                    section "Apps"
                    item "Open {app}" icon="star" shortcut="cmd+o" { set "picked" "{app}-{i}" }
                    item "Pressed" checked="{self.pressed}" disabled=#true
                    separator
                    each n in="{[1, 2]}" { item "N{n}" }
                    when "{var.mode == 'a'}" { item "A" }
                    else { item "Not A" }
                    submenu "More" { item "Deep {app}" }
                    item "Quit"
                    item "Force" alternate=#true
                    source "app-windows" app="{app}"
                }
            }
        }
    }
    """

    @MainActor
    final class EchoSource: MenuSourceProviding {
        var seen: [String] = []
        func entries(_ kind: String, properties: [String: Value], element: ElementInstance, context: RenderContext) async -> [ElementMenuEntry] {
            seen.append(kind + ":" + (properties["app"]?.plainText ?? "?"))
            return [.item(ElementMenuCommand(title: "from source", perform: {}))]
        }
    }

    @Test("MenuModel wertet each/when/section/submenu/source mit dem Element als Bezug aus, Aktion läuft")
    func model() async throws {
        let mounted = try Mounted.mount(Self.menuConfig, css: "#t { width: 60px; height: 60px; } .b { width: 20px; height: 20px; }")
        let source = EchoSource()
        mounted.session.context.menuSources["app-windows"] = source
        let beta = try mounted.catcher("b-beta")
        let element = try #require(beta.element)
        let entries = await MenuModel.entries(for: element, context: mounted.session.context)
        try #require(entries.count == 11, "\(entries.flatMap(\.flat))")
        #expect(entries.flatMap(\.flat) == [
            "[Apps]", "Open beta", "Pressed (off)", "-", "N1", "N2", "Not A", "More >", "  Deep beta", "Quit", "⌥ Force", "from source",
        ])
        #expect(source.seen == ["app-windows:beta"])
        let open = try #require(entries[1].command)
        #expect(open.icon == "star" && open.shortcut == "cmd+o")
        open.perform()
        await mounted.settle()
        #expect(mounted.variable("picked") == .string("beta-1"))
        let menu = NativeMenu.make(entries, context: mounted.session.context)
        #expect(menu.items[1].keyEquivalent == "o" && menu.items[1].keyEquivalentModifierMask == .command)
        #expect(menu.items[2].isEnabled == false)
        #expect(menu.items[9].isAlternate && menu.items[9].keyEquivalentModifierMask.contains(.option))
        #expect(menu.items[7].submenu?.items.first?.title == "Deep beta")
    }

    @Test("Menü liegt rechts/links/unter dem Element mit Abstand, sonst am Zeiger")
    func location() {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
        #expect(NativeMenu.location(side: "right", offset: 6, bounds: bounds, flipped: true, menuWidth: 100, pointer: nil) == NSPoint(x: 46, y: 0))
        #expect(NativeMenu.location(side: "right", offset: 6, bounds: bounds, flipped: false, menuWidth: 100, pointer: nil) == NSPoint(x: 46, y: 20))
        #expect(NativeMenu.location(side: "left", offset: 6, bounds: bounds, flipped: true, menuWidth: 100, pointer: nil) == NSPoint(x: -106, y: 0))
        #expect(NativeMenu.location(side: "below", offset: 6, bounds: bounds, flipped: true, menuWidth: 100, pointer: nil) == NSPoint(x: 0, y: 26))
        #expect(NativeMenu.location(side: "pointer", offset: 6, bounds: bounds, flipped: true, menuWidth: 100, pointer: NSPoint(x: 3, y: 4)) == NSPoint(x: 3, y: 4))
    }

    static let sourceConfig = """
    panel "t" anchor="left" {
        button id="b" class="b" {
            menu { source "app-dock" app="{fixture-app}" }
        }
    }
    """

    func sourceSetup(_ system: FakeAppMenuSystem) throws -> (Mounted, ElementInstance, RecordingRuntime) {
        let mounted = try Mounted.mount(Self.sourceConfig.replacingOccurrences(of: "{fixture-app}", with: "com.example.app"),
                                        css: "#t { width: 40px; height: 40px; } .b { width: 20px; height: 20px; }")
        let runtime = RecordingRuntime(try #require(mounted.session.context.runtime))
        mounted.session.context.runtime = runtime
        return (mounted, try #require(try mounted.catcher("b").element), runtime)
    }

    @Test("app-dock spiegelt Apples Dock-Menü, Keep in Dock wirkt auf den apps-Provider")
    func appDockMirrored() async throws {
        let system = FakeAppMenuSystem()
        system.dock = DockMenuTree.nodes(from: [
            RawMenuItem(title: "Recent.txt"),
            RawMenuItem(title: ""),
            RawMenuItem(title: "Options", hasSubmenu: true, children: [RawMenuItem(title: "Keep in Dock", mark: "✓"), RawMenuItem(title: "Open at Login", enabled: false)]),
        ])
        let (mounted, element, runtime) = try sourceSetup(system)
        let sources = AppMenuSources(system: system)
        let record = Value.record(Record([("bundle-id", .string("com.example.app")), ("dock-pinned", .bool(false)), ("name", .string("Example"))]))
        let entries = await sources.entries("app-dock", properties: ["app": record], element: element, context: mounted.session.context)
        #expect(entries.flatMap(\.flat) == ["Recent.txt", "-", "Options >", "  Keep in Dock", "  Open at Login (off)"])
        entries[0].command?.perform()
        #expect(system.pressed.first?.map(\.title) == ["Recent.txt"])
        guard case .submenu(_, let options) = entries[2] else { Issue.record("no submenu"); return }
        options[0].command?.perform()
        #expect(runtime.performed == ["apps.dock-pin com.example.app"])
    }

    @Test("app-dock Rückfall full wie 0.1.2, commands nur Befehle; app-windows und app-commands")
    func appDockFallbacks() async throws {
        let system = FakeAppMenuSystem()
        let (mounted, element, runtime) = try sourceSetup(system)
        let context = mounted.session.context
        let sources = AppMenuSources(system: system)
        let app: [String: Value] = ["app": .record(Record([("bundle-id", .string("com.example.app")), ("dock-pinned", .bool(true)), ("name", .string("Example"))]))]
        let full = await sources.entries("app-dock", properties: app, element: element, context: context)
        #expect(full.flatMap(\.flat) == [
            "Example", "✓ Two", "-", "New Window", "-", "Options >", "  ✓ Keep in Dock", "  Show in ForkLift",
            "-", "Show All Windows", "Hide", "Quit", "⌥ Force Quit",
        ])
        try #require(full.count == 11)
        #expect(full[0].command?.icon == "minus.circle")
        full[1].command?.perform()
        #expect(system.raised == [1])
        full[3].command?.perform()
        full[9].command?.perform()
        #expect(runtime.performed == ["apps.run-command com.example.app New Window", "apps.quit com.example.app"])
        var commandsOnly = app
        commandsOnly["fallback"] = .string("commands")
        #expect(await sources.entries("app-dock", properties: commandsOnly, element: element, context: context).flatMap(\.flat) == ["New Window", "Settings…"])
        #expect(await sources.entries("app-commands", properties: ["app": .string("com.example.app")], element: element, context: context).flatMap(\.flat)
            == ["New Window", "Settings…", "-", "Show in Finder"])
        #expect(await sources.entries("app-windows", properties: app, element: element, context: context).flatMap(\.flat) == ["Example", "✓ Two"])
        system.running = false
        #expect(await sources.entries("app-dock", properties: app, element: element, context: context).flatMap(\.flat)
            == ["Open", "-", "Options >", "  ✓ Keep in Dock", "  Show in ForkLift"])
        #expect(await sources.entries("app-dock", properties: ["app": .null], element: element, context: context).isEmpty)
    }

    static let reorderConfig = """
    var log ""
    panel "t" anchor="left" {
        reorderable axis="horizontal" id="list" {
            on-reorder { set "log" "{event.from}>{event.to} {event.key} {event.from-key}>{event.to-key}" }
            each item in="{['a', 'b', 'c', 'd']}" key="{item}" {
                stack class="cell cell-{item}"
            }
        }
    }
    """
    static let reorderCSS = """
    #t { width: 80px; height: 20px; align-items: start; }
    .cell { width: 20px; height: 20px; }
    .cell-a { background: #ff0000; } .cell-b { background: #00ff00; } .cell-c { background: #0000ff; } .cell-d { background: #000000; }
    """

    @Test("reorderable: move feuert on-reorder mit from/to/key, Vorschau sofort, Rücksprung ohne Listenänderung")
    func reorderCoordinator() async throws {
        let mounted = try Mounted.mount(Self.reorderConfig, css: Self.reorderCSS)
        let context = mounted.session.context
        let list = try #require(context.reorders.values.first)
        #expect(list.keys == [.string("a"), .string("b"), .string("c"), .string("d")])
        let a = list.entry(for: list.container.children[0], index: 0)
        let c = list.entry(for: list.container.children[2], index: 2)
        #expect(a.token.hasSuffix("|a"))
        #expect(list.drop(token: a.token, on: c))
        #expect(list.ordered(list.container.children).map { $0.entryKey } == [.string("b"), .string("c"), .string("a"), .string("d")])
        await mounted.settle()
        #expect(mounted.variable("log") == .string("0>3 a a>c"))
        #expect(!list.drop(token: "other|a", on: c))
        #expect(!list.move(ReorderMove(from: 1, to: 1), keys: list.keys))
        for _ in 0..<60 where list.preview != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(list.preview == nil)
        #expect(list.ordered(list.container.children).map { $0.entryKey } == list.keys)
    }
}
