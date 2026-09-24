import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

enum KDLLoad {
    static let paths = ConfigPaths(
        builtinConfigs: URL(fileURLWithPath: "/builtin"),
        userConfig: URL(fileURLWithPath: "/config"),
        applicationSupport: URL(fileURLWithPath: "/support")
    )

    static func load(_ shell: String, extra: [String: String] = [:], id: String = "mine") async -> ConfigLoadResult {
        var files = extra
        files["/config/shell.kdl"] = shell
        let snapshot = files
        return await Task.detached {
            let loader = ConfigLoader(fileSystem: MemoryFileSystem(snapshot), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
            return loader.load(ConfigLocation(id: id, root: URL(fileURLWithPath: "/config"), isBuiltin: false))
        }.value
    }
}

@MainActor
struct KDLShell {
    let fixture = ShellFixture(registry: .builtin)
    var runtime: ShellRuntime { fixture.runtime }
    var vars: VarStore { fixture.vars }

    @discardableResult
    func apply(_ result: ConfigLoadResult, screens: [String] = ["A"], persisted: [String: Value] = [:], writer: StateWriter? = nil) -> Bool {
        let applied = runtime.applyLoaded(result, persisted: persisted, screens: screens, shell: Record(), writer: writer)
        fixture.flush()
        return applied
    }

    func load(_ shell: String, extra: [String: String] = [:], id: String = "mine") async throws -> ConfigLoadResult {
        let result = await KDLLoad.load(shell, extra: extra, id: id)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(result.diagnostics.map(\.message))")
        return result
    }

    func texts(_ surface: String, screen: String = "A") -> [String] {
        var out: [String] = []
        var stack = fixture.surface(surface, screen).root.reversed() as [ElementInstance]
        while let element = stack.popLast() {
            if element.kind == "text", let first = element.arguments.first {
                out.append(Self.describe(first.value))
            }
            stack.append(contentsOf: element.children.reversed())
        }
        return out
    }

    static func describe(_ value: Value) -> String {
        switch value {
        case .string(let text): text
        case .number(let number) where number == number.rounded(): String(Int(number))
        default: "\(value)"
        }
    }

    func settle() async {
        for _ in 0..<4 {
            await Task.yield()
            fixture.flush()
        }
    }
}

@MainActor
@Suite("Echte KDL durch die Runtime")
struct LoadedConfigTests {
    @Test("on über emit mit when=, Zähler in var")
    func onViaEmit() async throws {
        let shell = KDLShell()
        let result = try await shell.load("""
        var count 0
        var enabled #true
        on "battery.warning" when="{var.enabled}" { set "count" "{var.count + 1}" }
        panel "bar" { text "{var.count}" }
        """)
        shell.apply(result)
        shell.runtime.emit("battery.warning", Record())
        await shell.settle()
        #expect(shell.vars.value("count") == .number(1))
        #expect(shell.texts("bar") == ["1"])
        _ = shell.vars.set("enabled", .bool(false), for: nil)
        shell.fixture.flush()
        shell.runtime.emit("battery.warning", Record())
        await shell.settle()
        #expect(shell.vars.value("count") == .number(1))
    }

    @Test("bind über triggerBind, when= am bind entscheidet")
    func bindViaTrigger() async throws {
        let shell = KDLShell()
        let result = try await shell.load("""
        var popout "wifi"
        bind "escape" when="{var.popout != ''}" { set "popout" "" }
        bind "alt+space" { toggle "launcher" }
        popup "launcher" { text "L" }
        """)
        shell.apply(result)
        #expect(shell.runtime.triggerBind("escape", event: Record()) != nil)
        await shell.settle()
        #expect(shell.vars.value("popout") == .string(""))
        #expect(shell.runtime.triggerBind("escape", event: Record()) == nil)
        shell.runtime.triggerBind("alt+space", event: Record())
        await shell.settle()
        #expect(shell.fixture.surface("launcher").isOpen)
        #expect(shell.runtime.triggerBind("ctrl+x", event: Record()) == nil)
        #expect(shell.fixture.warnings.contains { $0.message.contains("ctrl+x") })
    }

    @Test("Handler am Element über trigger, when/else als Aktion im Handler")
    func elementHandlerWhen() async throws {
        let shell = KDLShell()
        let result = try await shell.load("""
        var armed #false
        var hits 0
        panel "bar" {
            button id="go" {
                on-click {
                    when "{var.armed}" { set "hits" "{var.hits + 1}" }
                }
                text "go"
            }
        }
        """)
        shell.apply(result)
        let identity = try #require(shell.fixture.surface("bar").root.first?.identity)
        shell.runtime.trigger("on-click", on: identity, event: Record())
        await shell.settle()
        #expect(shell.vars.value("hits") == .number(0))
        _ = shell.vars.set("armed", .bool(true), for: nil)
        shell.fixture.flush()
        shell.runtime.trigger("on-click", on: identity, event: Record())
        await shell.settle()
        #expect(shell.vars.value("hits") == .number(1))
    }

    static let sidebar = """
    var sidebar-modules persist=#true {
        - kind="clock" label="Uhr"
        - kind="power"
    }
    define "sidebar-clock" {
        param "module"
        text "clock {module.label}"
    }
    define "sidebar-power" {
        param "module"
        text "power"
    }
    panel "sidebar" {
        column {
            each module in="{var.sidebar-modules}" key="{module.id ?? module.kind}" {
                use "sidebar-{module.kind}" module="{module}"
            }
        }
    }
    """

    @Test("Laufzeit-use aus einer var-Liste: Einfügen, unbekannter Name warnt, Rest bleibt")
    func runtimeUseFromVarList() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load(Self.sidebar))
        #expect(shell.texts("sidebar") == ["clock Uhr", "power"])
        let powerBefore = shell.fixture.surface("sidebar").root.first?.children.last
        let modules: Value = .list([
            .record(Record([("kind", .string("weathr"))])),
            .record(Record([("kind", .string("clock")), ("label", .string("Neu"))])),
            .record(Record([("kind", .string("power"))])),
        ])
        #expect(shell.vars.set("sidebar-modules", modules, for: nil))
        shell.fixture.flush()
        #expect(shell.texts("sidebar") == ["clock Neu", "power"])
        #expect(shell.fixture.surface("sidebar").root.first?.children.last === powerBefore)
        #expect(shell.fixture.warnings.contains { $0.message.contains("unknown block 'sidebar-weathr'") })
    }

    @Test("Reload zweier Config-Stände: Text geändert, Kind eingefügt, Instanzen bleiben")
    func reloadTwoStates() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var n 1
        panel "bar" {
            text "a {var.n}" id="a"
            text "b"
        }
        """))
        let bar = shell.fixture.surface("bar")
        let first = try #require(bar.root.first)
        shell.fixture.host.events.removeAll()
        shell.apply(try await shell.load("""
        var n 1
        panel "bar" {
            text "neu"
            text "A {var.n}" id="a"
            text "b"
        }
        """))
        #expect(shell.fixture.surface("bar") === bar)
        #expect(shell.texts("bar") == ["neu", "A 1", "b"])
        #expect(bar.root[1] === first)
        #expect(shell.fixture.host.events == ["changed:bar@A"])
    }

    @Test("Reload ohne Änderung aus echter KDL: 0 Elemente, 0 Auswertungen, keine Host-Meldung")
    func reloadWithoutChange() async throws {
        let shell = KDLShell()
        let source = Self.sidebar + """

        var tab "media"
        popup "dashboard" {
            text "{perf.cpu | percent}"
            when "{var.tab == 'media'}" { text "{media.title ?? ''}" }
            else { text "idle" }
        }
        on "battery.warning" { set "tab" "x" }
        bind "escape" { close "dashboard" }
        """
        shell.apply(try await shell.load(source), screens: ["A", "B"])
        let before = shell.runtime.stats
        shell.fixture.host.events.removeAll()
        shell.apply(try await shell.load(source), screens: ["A", "B"])
        let after = shell.runtime.stats
        #expect(after.elementsBuilt == before.elementsBuilt)
        #expect(after.surfacesBuilt == before.surfacesBuilt)
        #expect(after.bindingsEvaluated == before.bindingsEvaluated)
        #expect(shell.fixture.host.events.isEmpty)
    }

    @Test("Nachfrage: Dashboard zu, 60 s: perf startet 0-mal; auf → Start, zu → Stopp")
    func demandScenario() async throws {
        let shell = KDLShell()
        let perf = StubProvider(id: "perf")
        shell.fixture.providers.register(perf)
        shell.apply(try await shell.load("""
        popup "dashboard" { text "{perf.cpu | percent}" }
        panel "bar" { text "bar" }
        """))
        for _ in 0..<60 {
            shell.fixture.clock.advance(by: 1)
            shell.fixture.flush()
        }
        #expect(perf.startCount == 0)
        shell.runtime.open("dashboard", screenKey: nil)
        shell.fixture.flush()
        #expect(perf.startCount == 1)
        #expect(perf.lastDemand.contains(DependencyPath("perf", ["cpu"])))
        shell.runtime.close("dashboard")
        shell.fixture.flush()
        #expect(perf.stopCount == 1)
        #expect(shell.runtime.stats.providersRunning == 0)
    }

    @Test("Provider mit on-Handler bleibt wach und liefert Ereignisse ohne Nachfrage")
    func eventProviderStaysAwake() async throws {
        let shell = KDLShell()
        let power = StubProvider(id: "power")
        shell.fixture.providers.register(power)
        shell.apply(try await shell.load("""
        var reason ""
        on "power.keep-awake-stopped" { set "reason" "{event.reason}" }
        panel "bar" { text "bar" }
        """))
        #expect(power.startCount == 1)
        power.lastContext?.emit("power.keep-awake-stopped", Record([("reason", .string("battery"))]))
        await shell.settle()
        #expect(shell.vars.value("reason") == .string("battery"))
        shell.apply(try await shell.load("panel \"bar\" { text \"bar\" }\n"))
        #expect(power.stopCount == 1)
    }

    @Test("Ladefehler: apply unterbleibt, alte Config bleibt, config.failed; Erfolg: config.loaded mit warnings")
    func loadErrorsKeepOldConfig() async throws {
        let shell = KDLShell()
        let good = """
        var failed -1
        var loaded -1
        on "config.failed" { set "failed" "{event.errors}" }
        on "config.loaded" { set "loaded" "{event.warnings}" }
        panel "bar" { text "alt" }
        """
        #expect(shell.apply(try await shell.load(good)))
        await shell.settle()
        #expect(shell.vars.value("loaded") == .number(0))
        let broken = await KDLLoad.load("panel \"bar\" { text \"neu\" unknown-prop=1 }\n")
        #expect(broken.ir == nil)
        var reported: [Diagnostic] = []
        shell.runtime.onDiagnostics = { reported = $0 }
        #expect(!shell.apply(broken))
        await shell.settle()
        #expect(shell.texts("bar") == ["alt"])
        #expect(shell.vars.value("failed") == .number(Double(broken.diagnostics.filter { $0.severity == .error }.count)))
        #expect(reported == broken.diagnostics)
    }

    @Test("Config-Wechsel reicht Zustand und Writer der Ziel-Config durch")
    func configSwitchPassesStateAndWriter() async throws {
        let shell = KDLShell()
        let source = "var tab \"a\" persist=#true\npanel \"bar\" { text \"{var.tab}\" }\n"
        shell.apply(try await shell.load(source, id: "one"), persisted: ["tab": .string("eins")])
        #expect(shell.texts("bar") == ["eins"])
        let fileSystem = MemoryFileSystem([:])
        let writer = StateWriter(file: URL(fileURLWithPath: "/config/state/two.kdl"), fileSystem: fileSystem)
        shell.apply(try await shell.load(source, id: "two"), persisted: ["tab": .string("zwei")], writer: writer)
        #expect(shell.texts("bar") == ["zwei"])
        #expect(shell.vars.set("tab", .string("drei"), for: nil))
        shell.vars.flushPendingSaves()
        #expect(try fileSystem.read(URL(fileURLWithPath: "/config/state/two.kdl")).contains("drei"))
    }
}

@MainActor
@Suite("Echte KDL: Slots, Lecks")
struct LoadedConfigScopeTests {
    @Test("Slot-Inhalt sieht die Namen der Aufrufstelle, nicht die Parameter des define (statisch)")
    func staticSlotScope() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var names { - "x" }
        define "card" {
            param "title"
            column {
                text "param {title}"
                slot
            }
        }
        panel "p" {
            each title in="{var.names}" {
                use "card" title="T" { text "slot {title}" }
            }
        }
        """))
        #expect(shell.texts("p") == ["param T", "slot x"])
    }

    @Test("Slot-Inhalt sieht die Namen der Aufrufstelle, nicht die Parameter des define (Laufzeit-use)")
    func runtimeSlotScope() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var names { - "x" }
        var block "card"
        define "card" {
            param "title"
            column {
                text "param {title}"
                slot
            }
        }
        panel "p" {
            each title in="{var.names}" {
                use "{var.block}" title="T" { text "slot {title}" }
            }
        }
        """))
        #expect(shell.texts("p") == ["param T", "slot x"])
    }

    func textInstances(_ shell: KDLShell, _ surface: String) -> [String: ElementInstance] {
        var out: [String: ElementInstance] = [:]
        var stack = shell.fixture.surface(surface, "A").root
        while let element = stack.popLast() {
            if element.kind == "text", let first = element.arguments.first {
                out[KDLShell.describe(first.value)] = element
            }
            stack.append(contentsOf: element.children)
        }
        return out
    }

    @Test("Laufzeit-use in each der Aufrufstelle: Slot-Inhalt folgt Eintrag und Index, auch wenn Parameter gleich heissen")
    func runtimeSlotInEach() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var names { - "x"; - "y" }
        var block "card"
        define "card" {
            param "title"
            param "i"
            column {
                text "param {title} {i}"
                slot
            }
        }
        panel "p" {
            each title in="{var.names}" key="{title}" index="i" {
                use "{var.block}" title="T" i=9 { text "slot {title} {i}" }
            }
        }
        """))
        #expect(shell.texts("p") == ["param T 9", "slot x 0", "param T 9", "slot y 1"])
        let before = textInstances(shell, "p")
        #expect(shell.vars.set("names", .list([.string("w"), .string("x"), .string("y")]), for: nil))
        shell.fixture.flush()
        #expect(shell.texts("p") == ["param T 9", "slot w 0", "param T 9", "slot x 1", "param T 9", "slot y 2"])
        let after = textInstances(shell, "p")
        #expect(before["slot x 0"] != nil && before["slot x 0"] === after["slot x 1"])
        #expect(before["slot y 1"] != nil && before["slot y 1"] === after["slot y 2"])
    }

    @Test("Verschachteltes Laufzeit-use: Slot reicht Slot weiter, jede Ebene sieht ihre Aufrufstelle")
    func nestedRuntimeSlot() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var names { - "x" }
        var outer "outer"
        var inner "inner"
        define "inner" {
            param "title"
            row {
                text "inner {title}"
                slot
            }
        }
        define "outer" {
            param "title"
            column {
                text "outer {title}"
                use "{var.inner}" title="I" {
                    text "mid {title}"
                    slot
                }
            }
        }
        panel "p" {
            each title in="{var.names}" key="{title}" index="i" {
                use "{var.outer}" title="O" { text "slot {title} {i}" }
            }
        }
        """))
        #expect(shell.texts("p") == ["outer O", "inner I", "mid O", "slot x 0"])
        let before = textInstances(shell, "p")
        #expect(shell.vars.set("names", .list([.string("w"), .string("x")]), for: nil))
        shell.fixture.flush()
        #expect(shell.texts("p") == ["outer O", "inner I", "mid O", "slot w 0", "outer O", "inner I", "mid O", "slot x 1"])
        #expect(before["slot x 0"] != nil && before["slot x 0"] === textInstances(shell, "p")["slot x 1"])
    }

    static func slotState(_ variant: Int) -> String {
        let argument = variant == 0 ? "T" : "U"
        let label = variant == 2 ? "label" : "param"
        let extra = variant == 0 ? "" : "text \"more {title}\""
        return """
        var names { - "x" }
        var block "card"
        define "card" {
            param "title"
            column {
                text "\(label) {title}"
                slot
            }
        }
        panel "p" {
            each title in="{var.names}" {
                use "{var.block}" title="\(argument)" {
                    text "slot {title}"
                    \(extra)
                }
            }
        }
        """
    }

    @Test("Reload behält Slot-Instanzen bei geändertem Argument, Slot-Inhalt und define")
    func reloadKeepsSlotInstances() async throws {
        let shell = KDLShell()
        let states = [try await shell.load(Self.slotState(0)), try await shell.load(Self.slotState(1)), try await shell.load(Self.slotState(2))]
        shell.apply(states[0])
        #expect(shell.texts("p") == ["param T", "slot x"])
        let slot = textInstances(shell, "p")["slot x"]
        #expect(slot != nil)
        shell.apply(states[1])
        #expect(shell.texts("p") == ["param U", "slot x", "more x"])
        #expect(textInstances(shell, "p")["slot x"] === slot)
        shell.apply(states[2])
        #expect(shell.texts("p") == ["label U", "slot x", "more x"])
        #expect(textInstances(shell, "p")["slot x"] === slot)
        weak var dropped = textInstances(shell, "p")["more x"]
        #expect(dropped != nil)
        shell.apply(states[0])
        #expect(shell.texts("p") == ["param T", "slot x"])
        #expect(textInstances(shell, "p")["slot x"] === slot)
        #expect(dropped == nil)
    }

    struct Counters: Equatable {
        var subscriptions: Int
        var roots: Int
        var demanded: Int
        var bindings: Int
        var elements: Int
        var surfaces: Int
        var awake: Int
    }

    func counters(_ shell: KDLShell) -> Counters {
        let fixture = shell.fixture
        return Counters(
            subscriptions: fixture.store.subscriptionCount,
            roots: fixture.store.rootCount,
            demanded: fixture.store.demandedPathCount,
            bindings: fixture.bindings.liveBindingCount,
            elements: fixture.runtime.elements.count,
            surfaces: fixture.runtime.surfaceNodes.count,
            awake: fixture.providers.awakeTokenCount
        )
    }

    static func state(_ variant: Int) -> String {
        let extra = variant == 0 ? "" : "text \"extra {var.n}\" id=\"extra\"\n"
        return """
        var n \(variant)
        var list { - "a"; - "b"; - "c" }
        var block "card-\(variant)"
        define "card-0" { param "v"; text "zero {v}" }
        define "card-1" { param "v"; row { text "one {v}" } }
        on "battery.warning" when="{var.n > \(variant)}" { set "n" \(variant + 1) }
        bind "escape" when="{var.n == \(variant)}" { set "n" 0 }
        panel "bar" {
            \(extra)text "{var.n} {perf.cpu}"
            each item in="{var.list}" key="{item}" { text "\(variant) {item} {self.hover}" }
            use "{var.block}" v="{var.n}"
            when "{var.n == 0}" { text "zero" }
        }
        popup "menu-\(variant)" { text "{battery.percent}" }
        """
    }

    @Test("200 Reloads zwischen zwei Config-Ständen: Zähler im Store bleiben stabil, alte Elemente werden frei")
    func noLeaksOverManyReloads() async throws {
        let shell = KDLShell()
        let states = [try await shell.load(Self.state(0)), try await shell.load(Self.state(1))]
        shell.apply(states[0])
        shell.apply(states[1])
        shell.apply(states[0])
        let baseline = counters(shell)
        weak var dropped: ElementInstance?
        do {
            shell.apply(states[1])
            dropped = shell.runtime.element(shell.runtime.surfaceNodes["bar@A"]!.identity.appending("#extra"))
            #expect(dropped != nil)
        }
        for index in 1...200 {
            shell.apply(states[index % 2])
        }
        #expect(counters(shell) == baseline)
        #expect(dropped == nil)
        #expect(shell.texts("bar") == ["0 ", "0 a ", "0 b ", "0 c ", "zero 0", "zero"])
    }
}
