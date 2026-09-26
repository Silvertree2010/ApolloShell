import Testing
import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloWMCore
@testable import ApolloProviders

@MainActor
@Suite("Provider wm")
struct WMProviderTests {
    func make(_ engine: FakeWMEngine = FakeWMEngine(), settings: WMSettings? = WMSettings(), enabled: Bool = true) -> (ProviderHarness, FakeWMEngine, WMProvider) {
        let harness = ProviderHarness()
        let provider = WMProvider(engine: engine, clock: harness.clock)
        harness.register(provider)
        provider.apply(settings)
        provider.configure(Record([("enabled", .bool(enabled))]))
        harness.flush()
        return (harness, engine, provider)
    }

    static func window(_ id: UInt32, _ title: String, workspace: Int? = nil, group: [UInt32] = []) -> WMWindowInfo {
        WMWindowInfo(id: id, pid: 42, app: "Kitty", bundleID: "net.kovidgoyal.kitty", title: title, desktop: 1, display: 1, workspace: workspace, group: group, frame: CGRect(x: 12, y: 40, width: 800, height: 600))
    }

    @Test("enabled startet und stoppt die Engine, ohne Nachfrage")
    func lifecycle() {
        let (_, engine, provider) = make(enabled: false)
        #expect(engine.starts.isEmpty && !provider.isEngineRunning)
        provider.configure(Record([("enabled", .bool(true))]))
        #expect(engine.starts.count == 1 && provider.isEngineRunning)
        provider.configure(Record([("enabled", .bool(true))]))
        #expect(engine.starts.count == 1)
        provider.configure(Record([("enabled", .bool(false))]))
        #expect(engine.stops == 1 && !provider.isEngineRunning)
    }

    @Test("Ohne Bedienungshilfen bleibt enabled falsch und startet nach Freigabe von selbst")
    func accessibility() {
        let engine = FakeWMEngine()
        engine.accessibilityTrusted = false
        let (harness, _, provider) = make(engine)
        harness.demand("wm")
        #expect(engine.starts.isEmpty)
        #expect(harness.value("wm", "enabled") == .bool(false))
        engine.accessibilityTrusted = true
        harness.advance(2)
        #expect(engine.starts.count == 1 && provider.isEngineRunning)
        #expect(harness.value("wm", "enabled") == .bool(true))
    }

    @Test("proxy ohne Bildschirmaufnahme faellt mit Warnung auf smooth zurueck und startet")
    func screenRecording() throws {
        let engine = FakeWMEngine()
        engine.screenRecordingAllowed = false
        var proxy = WMSettings()
        proxy.resize = .proxy
        let (harness, _, provider) = make(engine, settings: proxy)
        harness.demand("wm")
        #expect(provider.isEngineRunning)
        #expect(harness.value("wm", "enabled") == .bool(true))
        let started = try #require(engine.starts.first)
        #expect(started.resize == .smooth)
        #expect(provider.currentSettings.resize == .proxy)
        let fallbacks = harness.warnings.filter { $0.severity == .warning && $0.message.contains("screen recording") }
        #expect(fallbacks.count == 1)
        var gapped = proxy
        gapped.innerGap = 4
        provider.apply(gapped)
        #expect(engine.configures.last?.resize == .smooth)
        #expect(harness.warnings.filter { $0.message.contains("screen recording") }.count == 1)
    }

    @Test("proxy mit Bildschirmaufnahme bleibt proxy, ohne Warnung")
    func screenRecordingAllowed() throws {
        var proxy = WMSettings()
        proxy.resize = .proxy
        let (harness, engine, _) = make(settings: proxy)
        #expect(try #require(engine.starts.first).resize == .proxy)
        #expect(!harness.warnings.contains { $0.message.contains("screen recording") })
    }

    @Test("Neue Einstellungen gehen an die laufende Engine")
    func reconfigure() {
        let (_, engine, provider) = make()
        var next = WMSettings()
        next.innerGap = 4
        provider.apply(next)
        #expect(engine.configures == [next])
        provider.apply(next)
        #expect(engine.configures.count == 1)
    }

    @Test("enabled weglassen oder den wm-Block entfernen stoppt die Engine")
    func removedEnabledStops() {
        let (_, engine, provider) = make()
        #expect(provider.isEngineRunning)
        provider.configure(Record())
        #expect(!provider.isEngineRunning && engine.stops == 1)
        provider.configure(Record([("enabled", .bool(true))]))
        #expect(provider.isEngineRunning)
        provider.apply(nil)
        provider.configure(Record())
        #expect(!provider.isEngineRunning && engine.stops == 2)
    }

    @Test("wm.toggle schaltet um, bis enabled sich ändert")
    func toggle() async throws {
        let (harness, engine, provider) = make()
        _ = try await harness.perform("wm", "wm.toggle")
        #expect(!provider.isEngineRunning && engine.stops == 1)
        _ = try await harness.perform("wm", "wm.toggle")
        #expect(provider.isEngineRunning && engine.starts.count == 2)
        _ = try await harness.perform("wm", "wm.toggle")
        provider.configure(Record([("enabled", .bool(false))]))
        provider.configure(Record([("enabled", .bool(true))]))
        #expect(provider.isEngineRunning)
    }

    @Test("Jede Aktion aus runtime.md 9.2 wird zum TWM-Befehl")
    func actions() async throws {
        let (harness, engine, _) = make()
        let cases: [(String, [Value], Command)] = [
            ("wm.focus", [.string("left")], .focus(.left)),
            ("wm.focus", [.string("next")], .cycleFocus),
            ("wm.swap", [.string("down")], .swap(.down)),
            ("wm.split", [], .toggleSplit),
            ("wm.equalize", [], .equalize),
            ("wm.grow", [.number(0.05), .number(0)], .grow(CGSize(width: 0.05, height: 0))),
            ("wm.terminal", [], .newTerminal),
            ("wm.group", [], .toggleGroup),
            ("wm.tab", [.string("next")], .cycleTab(true)),
            ("wm.tab-move", [.string("prev")], .moveTab(false)),
            ("wm.group-app", [], .groupApp),
            ("wm.float", [], .toggleFloating),
            ("wm.fullscreen", [], .toggleFullscreen),
            ("wm.close", [], .closeWindow),
            ("wm.desktop", [.number(3)], .workspace(3)),
            ("wm.send", [.number(9)], .sendToDesktop(9)),
            ("wm.scratchpad", [], .scratchpad),
            ("wm.display", [.string("next")], .focusDisplay(true)),
            ("wm.move-display", [.string("prev")], .sendToDisplay(false)),
        ]
        for (action, arguments, _) in cases {
            _ = try await harness.perform("wm", action, arguments)
        }
        #expect(engine.commands == cases.map(\.2))
        _ = try await harness.perform("wm", "wm.layout", [.string("canvas")])
        #expect(engine.layouts == [.canvas])
    }

    @Test("Registry und Provider kennen dieselben wm-Aktionen")
    func registryActions() async throws {
        let (harness, engine, _) = make()
        engine.current.windows = [Self.window(7, "a")]
        harness.demand("wm")
        for action in BuiltinProviderSchemas.schema("wm").actions where action.name != "wm.toggle" {
            let arguments: [Value] = action.arguments.map { argument in
                switch (action.name, argument.name) {
                case ("wm.layout", _): .string("dwindle")
                case ("wm.focus", _), ("wm.swap", _): .string("left")
                case (_, "direction"): .string("next")
                case (_, "index"): .number(2)
                case (_, "id"): .string("7")
                default: .number(0.1)
                }
            }
            _ = try await harness.perform("wm", action.name, arguments)
        }
        #expect(harness.warnings.isEmpty)
        #expect(engine.commands.count == BuiltinProviderSchemas.schema("wm").actions.count - 3)
    }

    @Test("Falsche Argumente sind Fehler, ohne laufende Engine nur eine Warnung")
    func invalid() async throws {
        let (harness, engine, provider) = make()
        await #expect(throws: ProviderActionError.self) { _ = try await harness.perform("wm", "wm.focus", [.string("sideways")]) }
        await #expect(throws: ProviderActionError.self) { _ = try await harness.perform("wm", "wm.desktop", [.number(12)]) }
        await #expect(throws: ProviderActionError.self) { _ = try await harness.perform("wm", "wm.layout", [.string("spiral")]) }
        await #expect(throws: ProviderActionError.self) { _ = try await harness.perform("wm", "wm.bogus") }
        harness.demand("wm")
        provider.configure(Record([("enabled", .bool(false))]))
        _ = try await harness.perform("wm", "wm.float")
        #expect(engine.commands.isEmpty)
        #expect(harness.warnings.map(\.message) == ["wm.float: the window manager is not running"])
    }

    @Test("Liefert jedes Registry-Feld, focused mit group-size")
    func fields() {
        let (harness, engine, _) = make()
        harness.demand("wm")
        engine.change {
            $0.windows = [Self.window(7, "a", group: [7, 8]), Self.window(8, "b", group: [7, 8])]
            $0.focused = 7
            $0.tabBars = [WMTabBarInfo(frame: CGRect(x: 12, y: 10, width: 800, height: 30), screen: "Built-in 1512x982", active: 7, tabs: [WMTabInfo(window: 7, title: "a", app: "Kitty")])]
        }
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("wm")).isEmpty)
        #expect(harness.value("wm", "enabled") == .bool(true))
        #expect(harness.value("wm", "focused.group-size") == .number(2))
        #expect(harness.value("wm", "focused.title") == .string("a"))
        guard case .list(let bars) = harness.value("wm", "tab-bars"), case .record(let bar) = bars.first else {
            Issue.record("tab-bars fehlt")
            return
        }
        #expect(bar["height"] == .number(30) && bar["screen"] == .string("Built-in 1512x982"))
        #expect(harness.value("wm", "workspaces") == .list([]))
    }

    @Test("Eigene Arbeitsbereiche erscheinen nur bei apple-desktops #false")
    func workspaces() {
        var own = WMSettings()
        own.appleDesktops = false
        let (harness, engine, _) = make(settings: own)
        harness.demand("wm")
        engine.change {
            $0.windows = [Self.window(1, "a", workspace: 2), Self.window(2, "b", workspace: 2)]
            $0.workspace = 2
        }
        guard case .list(let spaces) = harness.value("wm", "workspaces"), spaces.count == 9, case .record(let second) = spaces[1] else {
            Issue.record("workspaces fehlt")
            return
        }
        #expect(second["active"] == .bool(true) && second["windows"] == .number(2))
    }

    @Test("Ereignisse aus dem Unterschied zweier Zustände")
    func events() {
        let (harness, engine, _) = make()
        harness.demand("wm")
        engine.change { $0.windows = [Self.window(1, "a")] }
        engine.change { $0.focused = 1 }
        engine.change { $0.layout = .canvas }
        engine.change { $0.workspace = 3 }
        engine.change {
            $0.windows = []
            $0.focused = nil
        }
        #expect(harness.eventNames() == ["wm.window-opened", "wm.focus-changed", "wm.layout-changed", "wm.workspace-changed", "wm.window-closed", "wm.focus-changed"])
        #expect(harness.events[0].fields["title"] == .string("a"))
    }

    @Test("apollo wm: ping, windows, Befehle wie twmctl, Unsinn ist ein Fehler")
    func control() throws {
        let (_, engine, provider) = make()
        engine.current.windows = [Self.window(5, "x")]
        #expect(try provider.control(["ping"]) == .string("pong"))
        guard case .list(let windows) = try provider.control(["windows"]), case .record(let first) = windows.first else {
            Issue.record("windows fehlt")
            return
        }
        #expect(first["id"] == .number(5) && first["title"] == .string("x"))
        #expect(try provider.control(["focus", "left"]) == .string("ok"))
        #expect(try provider.control(["grow 0.05 0"]) == .string("ok"))
        #expect(try provider.control(["layout", "canvas"]) == .string("ok"))
        #expect(try provider.control(["focus-window", "5"]) == .string("ok"))
        #expect(engine.commands == [.focus(.left), .grow(CGSize(width: 0.05, height: 0))])
        #expect(engine.layouts == [.canvas] && engine.focusedWindows == [5])
        #expect(throws: ProviderActionError.self) { try provider.control(["dance"]) }
        #expect(throws: ProviderActionError.self) { try provider.control(["focus-window", "99"]) }
        #expect(try provider.control(["toggle"]) == .string("ok"))
        #expect(!provider.isEngineRunning)
        #expect(throws: ProviderActionError.self) { try provider.control(["focus", "left"]) }
        #expect(try provider.control(["windows"]) == .list([]))
    }
}
