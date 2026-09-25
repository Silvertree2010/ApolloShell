import Testing
import AppKit
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloShell

@MainActor
final class ManualTimers {
    var items: [(delay: TimeInterval, work: DispatchWorkItem)] = []

    func schedule(_ delay: TimeInterval, _ work: DispatchWorkItem) {
        items.append((delay, work))
    }

    func fireNext() {
        guard let index = items.firstIndex(where: { !$0.work.isCancelled }) else { return }
        let item = items.remove(at: index)
        item.work.perform()
    }

    var live: [TimeInterval] { items.filter { !$0.work.isCancelled }.map(\.delay) }
}

@MainActor
final class ShellHarness {
    static let a = ScreenGeometry(key: "A 1440x900", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect(x: 0, y: 0, width: 1440, height: 870))
    static let b = ScreenGeometry(key: "B 1920x1080", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), visible: CGRect(x: 1440, y: 0, width: 1920, height: 1050))

    let home: URL
    let config: URL
    let factory = FakeFactory()
    let shell: LiveShell
    var screens: [String: ScreenGeometry] = [a.key: a]
    var fullscreenKeys: Set<String> = []
    var pointerKey: String?
    var scheduledChecks = 0
    var reloadTimers: [(delay: TimeInterval, work: @MainActor () -> Void)] = []

    init(_ source: String, settings: String? = nil, useConfigFolder: Bool = true) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("round2-\(UUID().uuidString)")
        config = home.appendingPathComponent("cfg")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("apolloshell/state"), withIntermediateDirectories: true)
        let text = source
        try text.write(to: config.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        if let settings {
            try settings.write(to: home.appendingPathComponent("apolloshell/settings.kdl"), atomically: true, encoding: .utf8)
        }
        let resources = PackageResources.root.appendingPathComponent("Resources")
        let options = LiveShell.Options(config: useConfigFolder ? config : nil, resources: resources, fixture: resources.appendingPathComponent("render/fixture.kdl"))
        var sink: ShellHarness?
        let monitor = FullscreenMonitor(read: { sink?.fullscreenKeys }, schedule: { _, _ in sink?.scheduledChecks += 1 })
        let debouncer = ReloadDebouncer(schedule: { delay, work in MainActor.assumeIsolated { sink?.reloadTimers.append((delay, work)) } })
        shell = LiveShell(options: options, host: WindowHost(factory: factory), environment: ["XDG_CONFIG_HOME": home.path], home: home, fullscreen: monitor, debouncer: debouncer)
        shell.interactive = false
        shell.registrar = FakeRegistrar()
        sink = self
        shell.currentScreens = { sink?.screens ?? [:] }
        shell.pointerScreen = { sink?.pointerKey }
        shell.edgeHover.makeTimer = { _, _ in nil }
    }

    func start() async throws {
        try await shell.start()
        settle()
    }

    func settle() {
        let wake = Timer(timeInterval: 0.002, repeats: true) { _ in }
        RunLoop.main.add(wake, forMode: .default)
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        wake.invalidate()
    }

    func elapseReloadDelay() {
        let due = reloadTimers
        reloadTimers.removeAll()
        due.forEach { $0.work() }
    }

    func write(_ source: String) throws {
        try source.write(to: config.appendingPathComponent("shell.kdl"), atomically: false, encoding: .utf8)
    }

    var runtime: ShellRuntime { shell.assembly!.runtime }

    func window(_ id: String, _ screen: ScreenGeometry = a) -> FakeWindow? {
        shell.host.controllers[SurfaceHost.key(id, screen.key)]?.window as? FakeWindow
    }

    func identities() -> [String: ObjectIdentifier] {
        shell.host.controllers.mapValues { ObjectIdentifier($0.window) }
    }
}

@MainActor
@Suite("Tasten wiederholen (Fund 39)")
struct KeyRepeatTests {
    @Test("repeat=#true: Auslösen beim Drücken, dann im Systemtakt bis zum Loslassen")
    func repeats() throws {
        var scheduled: [(TimeInterval, @MainActor () -> Void)] = []
        let repeater = KeyRepeater(timing: { .init(delay: 0.3, interval: 0.05) }, schedule: { delay, work in
            scheduled.append((delay, work))
            return DispatchWorkItem {}
        })
        let keys = try KeysFixture("""
        popup "menu" { row {} }
        bind "ctrl+alt+up" id="louder" repeat=#true { toggle "menu" }
        bind "ctrl+alt+d" id="once" { toggle "menu" }
        """, repeater: repeater)
        keys.registrar.press("ctrl+alt+up")
        #expect(keys.triggered == ["louder"])
        #expect(scheduled.map(\.0) == [0.3])
        scheduled.removeFirst().1()
        #expect(keys.triggered == ["louder", "louder"])
        #expect(scheduled.map(\.0) == [0.05])
        scheduled.removeFirst().1()
        #expect(keys.triggered.count == 3)
        keys.registrar.release("ctrl+alt+up")
        #expect(repeater.active.isEmpty)
        scheduled.forEach { $0.1() }
        scheduled.removeAll()
        #expect(keys.triggered.count == 3)
        keys.registrar.press("ctrl+alt+d")
        #expect(keys.triggered.last == "once")
        #expect(keys.registrar.releases["ctrl+alt+d"] == nil)
        #expect(scheduled.isEmpty)
    }

    @Test("Systemtakt kommt aus den Tastatureinstellungen")
    func systemTiming() {
        let timing = KeyRepeater.Timing.system
        #expect(timing.delay >= 0.05 && timing.interval >= 0.01)
    }
}

@MainActor
@Suite("Host Runde 2: osd, Bildschirm unter dem Zeiger, Vollbild, hover-edge, reserve")
struct HostRoundTwoTests {
    @Test("osd: Timer ruht, solange der Zeiger darauf liegt")
    func osdHover() throws {
        let fixture = try HostFixture("osd \"volume\" timeout=\"1s\" { row {} }")
        let timers = ManualTimers()
        fixture.host.scheduleTimer = { timers.schedule($0, $1) }
        var pointer = CGPoint(x: -500, y: -500)
        fixture.host.pointer = { pointer }
        fixture.assembly.runtime.open("volume", screenKey: nil)
        fixture.flush()
        let frame = try #require(fixture.host.controllers.values.first?.openFrame)
        #expect(timers.live == [1])
        pointer = CGPoint(x: frame.midX, y: frame.midY)
        timers.fireNext()
        #expect(fixture.assembly.runtime.surface("volume", screenKey: HostFixture.screen.key)?.isOpen == true)
        #expect(timers.live == [WindowHost.hoverPoll])
        timers.fireNext()
        #expect(timers.live == [WindowHost.hoverPoll])
        pointer = CGPoint(x: -500, y: -500)
        timers.fireNext()
        #expect(timers.live == [1])
        #expect(fixture.assembly.runtime.surface("volume", screenKey: HostFixture.screen.key)?.isOpen == true)
        timers.fireNext()
        #expect(fixture.assembly.runtime.surface("volume", screenKey: HostFixture.screen.key)?.isOpen == false)
    }

    @Test("popup screen=pointer geht auf dem Bildschirm unter dem Zeiger auf")
    func pointerScreen() async throws {
        let harness = try ShellHarness("popup \"menu\" { row {} }\npanel \"bar\" anchor=\"left\" { row {} }")
        harness.screens = [ShellHarness.a.key: ShellHarness.a, ShellHarness.b.key: ShellHarness.b]
        harness.pointerKey = ShellHarness.b.key
        try await harness.start()
        harness.runtime.toggle("menu")
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.b.key)?.isOpen == true)
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.a.key)?.isOpen == false)
        harness.pointerKey = ShellHarness.a.key
        harness.runtime.close("menu")
        harness.runtime.open("menu", screenKey: nil)
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.a.key)?.isOpen == true)
        harness.shell.shutdown()
    }

    @Test("Vollbild-Monitor meldet nur Änderungen je Bildschirm an die Runtime")
    func fullscreenMonitor() async throws {
        let harness = try ShellHarness("panel \"bar\" anchor=\"left\" { row {} }\noverlay \"corners\" { row {} }")
        try await harness.start()
        let bar = try #require(harness.window("bar"))
        #expect(bar.isShown)
        harness.fullscreenKeys = [ShellHarness.a.key, "gone"]
        harness.shell.fullscreen.check()
        #expect(!bar.isShown)
        #expect(harness.window("corners")?.isShown == true)
        let shows = bar.shows
        harness.shell.fullscreen.check()
        #expect(bar.shows == shows)
        harness.fullscreenKeys = []
        harness.shell.fullscreen.check()
        #expect(bar.isShown)
        harness.shell.host.spaceChanged()
        #expect(harness.shell.host.stats.windowsCreated == 2)
        harness.shell.shutdown()
    }

    @Test("hover-edge: Kante öffnet, Verlassen schliesst, per Kürzel offen bleibt bis einmal hinein und hinaus")
    func hoverEdge() throws {
        let fixture = try HostFixture("popup \"drawer\" anchor=\"left\" hover-edge=#true hover-margin=10 { row {} }")
        let runtime = fixture.assembly.runtime
        let hover = EdgeHoverController()
        var point = CGPoint(x: 700, y: 450)
        var fullscreen = false
        hover.targets = { fixture.host.hoverTargets() }
        hover.pointer = { point }
        hover.isFullscreen = { _ in fullscreen }
        hover.open = { runtime.open($0, screenKey: $1) }
        hover.close = { runtime.close($0) }
        var ticking = false
        var watching = false
        hover.makeTimer = { _, _ in ticking = true; return nil }
        hover.makeMonitor = { _ in watching = true; return "m" }
        hover.removeMonitor = { _ in }
        hover.refresh()
        #expect(watching)
        #expect(!ticking)
        let target = try #require(fixture.host.hoverTargets().first)
        #expect(target.anchor == .left)
        func isOpen() -> Bool { runtime.surface("drawer", screenKey: HostFixture.screen.key)?.isOpen == true }
        hover.tick()
        #expect(!isOpen())
        point = CGPoint(x: 0, y: target.frame.midY)
        fullscreen = true
        hover.tick()
        #expect(!isOpen())
        fullscreen = false
        hover.tick()
        #expect(isOpen())
        point = CGPoint(x: target.frame.maxX + 5, y: target.frame.midY)
        hover.tick()
        #expect(isOpen())
        point = CGPoint(x: 900, y: 450)
        hover.tick()
        #expect(!isOpen())
        runtime.open("drawer", screenKey: nil)
        hover.tick()
        #expect(isOpen())
        hover.tick()
        #expect(isOpen())
        point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        hover.tick()
        point = CGPoint(x: 900, y: 450)
        hover.tick()
        #expect(!isOpen())
    }

    @Test("hover-gap hält die Ecke frei, center löst nie aus")
    func hoverAreas() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let corner = EdgeHoverController.Target(key: "k", surfaceID: "s", screenKey: "A", anchor: .bottomRight, frame: CGRect(x: 1140, y: 0, width: 300, height: 200), screen: screen, margin: 0, gap: 12, isOpen: false)
        let area = EdgeHoverController.area(corner, open: false)
        #expect(area.maxX == 1428)
        #expect(area.contains(CGPoint(x: 1300, y: 0)))
        #expect(!area.contains(CGPoint(x: 1435, y: 0)))
        var center = corner
        center.anchor = .center
        #expect(EdgeHoverController.area(center, open: false).isNull)
    }

    @Test("reserve: Ränder je Kante für die Fensterwache, Klemmen an allen Kanten")
    func reservedEdges() throws {
        let fixture = try HostFixture(WindowHostTests.shell, css: WindowHostTests.css)
        #expect(fixture.host.reservedEdges() == [HostFixture.screen.key: ReservedEdges(left: 44)])
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 0, y: 100, width: 400, height: 300), screen: screen, reserved: ReservedEdges(left: 44)) == CGRect(x: 44, y: 100, width: 356, height: 300))
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 700, y: 100, width: 300, height: 300), screen: screen, reserved: ReservedEdges(right: 50)) == CGRect(x: 650, y: 100, width: 300, height: 300))
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 0, y: 0, width: 1000, height: 800), screen: screen, reserved: ReservedEdges(left: 40, right: 60)) == CGRect(x: 40, y: 0, width: 900, height: 800))
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 100, y: 10, width: 300, height: 300), screen: screen, reserved: ReservedEdges(top: 60)) == CGRect(x: 100, y: 60, width: 300, height: 300))
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 100, y: 0, width: 300, height: 800), screen: screen, reserved: ReservedEdges(bottom: 70)) == CGRect(x: 100, y: 0, width: 300, height: 730))
        #expect(WindowClamp.clampedFrame(window: CGRect(x: 100, y: 100, width: 300, height: 300), screen: screen, reserved: ReservedEdges(left: 44, top: 30)) == nil)
    }
}

@MainActor
@Suite("Start und IPC Runde 2")
struct HostStartIPCTests {
    @Test("settings.kdl nennt eine fehlende Config: Diagnose landet im Overlay")
    func resolverDiagnostics() async throws {
        let harness = try ShellHarness("panel \"x\" { row {} }", settings: "config \"nope\"\n", useConfigFolder: false)
        try await harness.start()
        #expect(harness.shell.overlay.problems.contains { $0.message.contains("settings.kdl names config 'nope'") })
        harness.shell.shutdown()
        let named = try ShellHarness("panel \"x\" { row {} }", settings: "config \"good\"\n", useConfigFolder: false)
        let good = named.home.appendingPathComponent("apolloshell/configs/good")
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try "panel \"x\" { row {} }".write(to: good.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try await named.start()
        #expect(named.shell.location?.id == "good")
        try "config \"still-missing\"\n".write(to: named.home.appendingPathComponent("apolloshell/settings.kdl"), atomically: true, encoding: .utf8)
        await named.shell.reload()?.value
        #expect(named.shell.overlay.problems.contains { $0.message.contains("'still-missing'") })
        named.shell.shutdown()
    }

    @Test("var persist: Wert aus state/<config>.kdl geladen, set schreibt zurück")
    func persistedVars() async throws {
        let harness = try ShellHarness("var tab \"a\" persist=#true\npanel \"bar\" { text \"{var.tab}\" }")
        let state = harness.home.appendingPathComponent("apolloshell/state/cfg.kdl")
        try "tab \"b\"\n".write(to: state, atomically: true, encoding: .utf8)
        try await harness.start()
        #expect(try harness.shell.variable("tab") == .string("b"))
        try harness.shell.setVariable("tab", .string("c"))
        harness.shell.assembly?.vars.flushPendingSaves()
        #expect(try String(contentsOf: state, encoding: .utf8).contains("\"c\""))
        try "tab \"d\"\n".write(to: state, atomically: true, encoding: .utf8)
        harness.shell.filesChanged([state.path])
        #expect(try harness.shell.variable("tab") == .string("d"))
        #expect(harness.shell.debouncer.pokes == 0)
        #expect(harness.shell.debouncer.fired == 0)
        harness.shell.shutdown()
    }

    @Test("IPC: eval, watch, get/set, run, tree, providers")
    func ipc() async throws {
        let harness = try ShellHarness("var count 1\npopup \"menu\" { row { text \"hi\" } }")
        try await harness.start()
        let shell = harness.shell
        #expect(try shell.evaluate("var.count + 2") == .number(3))
        #expect(throws: (any Error).self) { try shell.evaluate("var.count +") }
        #expect(throws: (any Error).self) { try shell.variable("missing") }
        let stream = try shell.watchExpression("var.count * 10")
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .number(10))
        _ = try await shell.runActions("set \"count\" 5\nopen \"menu\"")
        harness.settle()
        #expect(try shell.variable("count") == .number(5))
        #expect(await iterator.next() == .number(50))
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.a.key)?.isOpen == true)
        await #expect(throws: (any Error).self) { _ = try await shell.runActions("nonsense-action 1") }
        guard case .list(let tree) = try shell.tree("menu"), case .record(let menu)? = tree.first else {
            Issue.record("no tree")
            return
        }
        #expect(menu["surface"] == .string("menu"))
        guard case .list(let children) = menu["children"] ?? .null else { Issue.record("no children"); return }
        #expect(children.count == 1)
        guard case .record(let providers) = shell.providerValues() else { Issue.record("no providers"); return }
        #expect(!providers.keys.isEmpty)
        #expect(!shell.commandCenterEntries().isEmpty)
        shell.shutdown()
    }
}

@MainActor
@Suite("Review Focus 1 und 2")
struct ReviewFocusTests {
    static let source = """
    panel "bar" anchor="left" { row {} }
    popup "menu" { row {} }
    """

    @Test("halb gespeichert: leere Datei, 20 ms später Inhalt, ein Reload, gleiche Fenster, kein Flackern")
    func halfSaved() async throws {
        let harness = try ShellHarness(Self.source)
        try await harness.start()
        harness.runtime.open("menu", screenKey: nil)
        harness.settle()
        let before = harness.identities()
        let bar = try #require(harness.window("bar"))
        let menu = try #require(harness.window("menu"))
        let hides = (bar.hides, menu.hides)
        try harness.write("")
        harness.shell.filesChanged([harness.config.appendingPathComponent("shell.kdl").path])
        #expect(harness.shell.debouncer.fired == 0)
        try harness.write(Self.source.replacingOccurrences(of: "row {}", with: "row { text \"x\" }"))
        harness.shell.filesChanged([harness.config.appendingPathComponent("shell.kdl").path])
        #expect(harness.reloadTimers.map(\.delay).allSatisfy { $0 == 0.15 })
        #expect(harness.shell.debouncer.fired == 0)
        harness.elapseReloadDelay()
        for _ in 0..<400 where harness.shell.reloadsApplied == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        harness.settle()
        #expect(harness.shell.debouncer.fired == 1)
        #expect(harness.shell.reloadsApplied == 1)
        #expect(harness.identities() == before)
        #expect(harness.shell.host.stats.windowsClosed == 0)
        #expect((bar.hides, menu.hides) == hides)
        #expect(bar.isShown && menu.isShown)
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.a.key)?.isOpen == true)
        harness.shell.shutdown()
    }

    @Test("nur die leere Datei gesehen: letzte gute Config bleibt, ältere Ladung überholt keine neuere")
    func emptyAloneAndOrder() async throws {
        let harness = try ShellHarness(Self.source)
        try await harness.start()
        let before = harness.identities()
        try harness.write("  \n")
        await harness.shell.reload()?.value
        #expect(harness.shell.reloadsApplied == 0)
        #expect(harness.identities() == before)
        try harness.write(Self.source + "\npopup \"extra\" { row {} }")
        let first = harness.shell.reload()
        let second = harness.shell.reload()
        await first?.value
        await second?.value
        #expect(harness.shell.reloadsApplied == 1)
        #expect(harness.shell.host.stats.windowsCreated == 3)
        #expect(harness.shell.host.stats.windowsClosed == 0)
        harness.shell.shutdown()
    }

    @Test("Bildschirm ab und an, Ruhezustand mit offenem Popup: kein Absturz, neue Fenster nur für den neuen Bildschirm")
    func screensAndSleep() async throws {
        let harness = try ShellHarness(Self.source)
        try await harness.start()
        let shell = harness.shell
        harness.runtime.open("menu", screenKey: ShellHarness.a.key)
        harness.settle()
        let onA = harness.identities()
        #expect(shell.host.stats.windowsCreated == 2)
        shell.screensDidChange([:])
        #expect(harness.identities() == onA)
        shell.screensDidChange([ShellHarness.a.key: ShellHarness.a, ShellHarness.b.key: ShellHarness.b])
        harness.settle()
        #expect(shell.host.stats.windowsCreated == 4)
        #expect(harness.identities().filter { $0.key.hasSuffix(ShellHarness.a.key) } == onA)
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.a.key)?.isOpen == true)
        harness.runtime.open("menu", screenKey: ShellHarness.b.key)
        shell.screensDidChange([ShellHarness.b.key: ShellHarness.b])
        harness.settle()
        #expect(shell.host.stats.windowsCreated == 4)
        #expect(shell.host.stats.windowsClosed == 2)
        #expect(harness.window("menu", ShellHarness.b)?.isShown == true)
        let onB = harness.identities()
        shell.screensDidChange([:])
        let center = NotificationCenter()
        shell.fullscreen.observe(center)
        let checksBefore = harness.scheduledChecks
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(harness.scheduledChecks == checksBefore + FullscreenMonitor.checks.count)
        shell.fullscreen.poke()
        shell.host.spaceChanged()
        shell.screensDidChange([ShellHarness.b.key: ShellHarness.b])
        harness.settle()
        #expect(harness.identities() == onB)
        #expect(shell.host.stats.windowsCreated == 4)
        #expect(harness.runtime.surface("menu", screenKey: ShellHarness.b.key)?.isOpen == true)
        shell.screensDidChange([ShellHarness.a.key: ShellHarness.a, ShellHarness.b.key: ShellHarness.b])
        harness.settle()
        #expect(shell.host.stats.windowsCreated == 6)
        shell.shutdown()
    }
}
