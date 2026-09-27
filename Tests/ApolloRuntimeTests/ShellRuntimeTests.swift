import Testing
import Foundation
import Observation
import Synchronization
import ApolloBase
import ApolloConfig
import ApolloStyle
@testable import ApolloRuntime

@MainActor
final class RecordingHost: SurfaceHosting {
    var events: [String] = []

    func surfaceAdded(_ surface: SurfaceInstance) {
        events.append("added:\(surface.id)@\(surface.screenKey)")
    }

    func surfaceChanged(_ surface: SurfaceInstance) {
        events.append("changed:\(surface.id)@\(surface.screenKey)")
    }

    func surfaceReplaced(_ surface: SurfaceInstance) {
        events.append("replaced:\(surface.id)@\(surface.screenKey)")
    }

    func surfaceRemoved(id: String, screenKey: String) {
        events.append("removed:\(id)@\(screenKey)")
    }
}

@MainActor
struct ShellFixture {
    let scheduler = ManualFlushScheduler()
    let store: SignalStore
    let bindings: BindingEngine
    let clock = ManualRuntimeClock()
    let vars: VarStore
    let providers: ProviderHost
    let actions: ActionDispatcher
    let host = RecordingHost()
    let runtime: ShellRuntime
    let warningLog = WarningLog()
    let log = ActionLog()

    var warnings: [Diagnostic] { warningLog.entries }

    init(registry: SchemaRegistry = SchemaRegistry()) {
        store = SignalStore(scheduler: scheduler)
        bindings = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        vars = VarStore(store: store, bindings: bindings, clock: clock)
        providers = ProviderHost(store: store)
        actions = ActionDispatcher(evaluator: BindingTestHarness.evaluator(), vars: vars, providers: providers, store: store, clock: clock)
        runtime = ShellRuntime(registry: registry, evaluator: BindingTestHarness.evaluator(), store: store, bindings: bindings, vars: vars, providers: providers, actions: actions, host: host)
        let sink = warningLog
        runtime.onWarning = { sink.entries.append($0) }
        actions.onWarning = { sink.entries.append($0) }
        vars.onWarning = { sink.entries.append($0) }
        actions.register("log", LogAction(log))
    }

    func apply(_ surfaces: [SurfaceIR], vars declarations: [VarDecl] = [], defines: [DefineIR] = [], events: [EventHandlerIR] = [], screens: [String] = ["A"], id: String = "test") {
        let ir = ConfigIR(
            id: id,
            root: URL(fileURLWithPath: "/config"),
            vars: declarations,
            surfaces: surfaces,
            events: events,
            defines: Dictionary(uniqueKeysWithValues: defines.map { ($0.name, $0) })
        )
        runtime.apply(ir, persisted: [:], screens: screens, shell: Record())
    }

    func flush() {
        scheduler.runPending()
    }

    func demanded(_ root: String) -> Set<DependencyPath> {
        store.demandedPaths(root: root)
    }

    func surface(_ id: String, _ screen: String = "A") -> SurfaceInstance {
        runtime.surface(id, screenKey: screen)!
    }
}

final class ChangeCounter: Sendable {
    private let storage = Mutex(0)

    func bump() {
        storage.withLock { $0 += 1 }
    }

    var count: Int {
        storage.withLock { $0 }
    }
}

enum TreeIR {
    typealias IR = RuntimeIR

    static func text(_ key: String, _ content: CompiledValue, properties: [String: CompiledValue] = [:], handlers: [HandlerIR] = [], line: Int = 1) -> ChildIR {
        .element(ElementIR(kind: "text", key: key, arguments: [content], properties: properties, handlers: handlers, span: IR.span(line)))
    }

    static func box(_ key: String, properties: [String: CompiledValue] = [:], handlers: [HandlerIR] = [], slots: [String: [ChildIR]] = [:], children: [ChildIR], line: Int = 1) -> ChildIR {
        .element(ElementIR(kind: "column", key: key, properties: properties, handlers: handlers, slots: slots, children: children, span: IR.span(line)))
    }

    static func surface(_ kind: String, _ id: String, properties: [String: CompiledValue] = [:], handlers: [HandlerIR] = [], children: [ChildIR]) -> SurfaceIR {
        SurfaceIR(kind: kind, id: id, properties: properties, handlers: handlers, children: children, span: IR.span(80))
    }
}

@MainActor
@Suite("ShellRuntime Elementbaum")
struct ShellRuntimeTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    @Test("apply baut Oberflächen je Bildschirm mit Zellen je Property und Konstanten ohne Binding")
    func buildsSurfacesAndCells() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [
            T.text("0", IR.value("{perf.cpu}"), properties: ["class": IR.string("cpu")]),
        ])], screens: ["A", "B"])
        let bar = fixture.surface("bar", "B")
        #expect(bar.root.count == 1)
        #expect(bar.root[0].kind == "text")
        #expect(bar.root[0].property("class") == .string("cpu"))
        #expect(bar.root[0].arguments.first?.value == .null)
        fixture.store.set(DependencyPath("perf", ["cpu"]), .number(3))
        fixture.flush()
        #expect(bar.root[0].arguments.first?.value == .number(3))
        #expect(fixture.runtime.stats.surfacesBuilt == 2)
        #expect(fixture.runtime.stats.elementsBuilt == 2)
        #expect(fixture.host.events == ["added:bar@A", "added:bar@B"])
    }

    @Test("Feine Updates: Änderung an Zelle B meldet keinem Leser von A, gleicher Wert meldet nichts")
    func fineGrainedObservation() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [
            T.text("0", IR.value("{perf.cpu}")),
            T.text("1", IR.value("{perf.gpu}")),
        ])])
        let a = fixture.surface("bar").root[0].arguments[0]
        let b = fixture.surface("bar").root[1].arguments[0]
        fixture.store.set(DependencyPath("perf", ["cpu"]), .number(1))
        fixture.flush()

        let aChanged = ChangeCounter()
        withObservationTracking { _ = a.value } onChange: { aChanged.bump() }
        let bChanged = ChangeCounter()
        withObservationTracking { _ = b.value } onChange: { bChanged.bump() }

        fixture.store.set(DependencyPath("perf", ["gpu"]), .number(9))
        fixture.flush()
        #expect(aChanged.count == 0)
        #expect(bChanged.count == 1)

        withObservationTracking { _ = a.value } onChange: { aChanged.bump() }
        fixture.store.set(DependencyPath("perf", ["cpu"]), .number(1))
        fixture.store.set(DependencyPath("perf", ["gpu"]), .number(10))
        fixture.flush()
        #expect(aChanged.count == 0)
        #expect(a.value == .number(1))
    }

    @Test("id wird immer aus properties[\"id\"] ausgewertet, auch wenn isConstant wahr ist")
    func idFromLoopVariable() {
        let fixture = ShellFixture()
        let each = EachIR(key: "0", variable: "app", list: IR.value("{var.apps}"), body: [
            T.text("0", IR.value("{app.name}", locals: ["app"]), properties: ["id": IR.value("app-{app.id}", locals: ["app"])]),
        ])
        fixture.apply([T.surface("panel", "dock", children: [.each(each)])], vars: [
            IR.plainVar("apps", .list, .list([
                .record(Record([("id", .string("safari")), ("name", .string("Safari"))])),
                .record(Record([("id", .string("mail")), ("name", .string("Mail"))])),
            ])),
        ])
        let root = fixture.surface("dock").root
        #expect(root.map(\.identity.description) == ["dock@A/#app-safari", "dock@A/#app-mail"])
        #expect(root.map { $0.property("id") } == [.string("app-safari"), .string("app-mail")])
        #expect(root.map { $0.arguments[0].value } == [.string("Safari"), .string("Mail")])
    }

    @Test("Doppelte Laufzeit-id: Warnung, das spätere Element verliert sie")
    func duplicateRuntimeID() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [
            T.text("0", IR.string("a"), properties: ["id": IR.string("same", line: 3)]),
            T.text("1", IR.string("b"), properties: ["id": IR.value("{var.name}", line: 4)]),
        ])], vars: [IR.plainVar("name", .string, .string("same"))])
        let root = fixture.surface("bar").root
        #expect(root[0].identity.description == "bar@A/#same")
        #expect(root[1].identity.description == "bar@A/1")
        #expect(root[1].property("id") == .null)
        #expect(fixture.warnings.count == 1)
        #expect(fixture.warnings.first?.message.contains("duplicate id") == true)
        #expect(fixture.warnings.first?.span == RuntimeIR.span(4))
    }

    @Test("when falsch: Kinder weg, Bindings beendet, Nachfrage weg; wahr: neu gebaut")
    func whenRemovesChildren() {
        let fixture = ShellFixture()
        let when = WhenIR(key: "0", condition: IR.value("{var.show}"), then: [T.text("0", IR.value("{battery.percent}"))], otherwise: [T.text("0", IR.string("none"))])
        fixture.apply([T.surface("panel", "bar", children: [.when(when)])], vars: [IR.plainVar("show", .bool, .bool(true))])
        let first = fixture.surface("bar").root
        #expect(first.count == 1)
        #expect(fixture.demanded("battery") == [DependencyPath("battery", ["percent"])])

        fixture.vars.set("show", .bool(false))
        fixture.flush()
        #expect(fixture.demanded("battery").isEmpty)
        let second = fixture.surface("bar").root
        #expect(second.count == 1)
        #expect(second[0].arguments[0].value == .string("none"))
        let evaluations = fixture.bindings.evaluationCount
        fixture.store.set(DependencyPath("battery", ["percent"]), .number(50))
        fixture.flush()
        #expect(fixture.bindings.evaluationCount == evaluations)

        fixture.vars.set("show", .bool(true))
        fixture.flush()
        #expect(fixture.surface("bar").root[0] !== first[0])
        #expect(fixture.surface("bar").root[0].arguments[0].value == .number(50))
    }

    @Test("switch mit mehreren Werten je case und default, Zweigwechsel baut neu")
    func switchBranches() {
        let fixture = ShellFixture()
        let switchIR = SwitchIR(key: "0", subject: IR.value("{var.tab}"), cases: [
            SwitchCaseIR(values: [IR.string("media")], body: [T.text("0", IR.string("Media"))]),
            SwitchCaseIR(values: [IR.string("performance"), IR.string("weather")], body: [T.text("0", IR.value("P {var.tab}"))]),
        ], otherwise: [T.text("0", IR.string("Overview"))])
        fixture.apply([T.surface("panel", "dash", children: [.switchOn(switchIR)])], vars: [IR.plainVar("tab", .string, .string("media"))])
        func shown() -> [Value] { fixture.surface("dash").root.map { $0.arguments[0].value } }
        #expect(shown() == [.string("Media")])
        fixture.vars.set("tab", .string("weather"))
        fixture.flush()
        #expect(shown() == [.string("P weather")])
        let weather = fixture.surface("dash").root[0]
        fixture.vars.set("tab", .string("performance"))
        fixture.flush()
        #expect(shown() == [.string("P performance")])
        #expect(fixture.surface("dash").root[0] === weather)
        fixture.vars.set("tab", .string("other"))
        fixture.flush()
        #expect(shown() == [.string("Overview")])
    }

    @Test("Popup zu: Feld nicht gefragt, auf: gefragt, zu: wieder nicht")
    func popupDemand() {
        let fixture = ShellFixture()
        fixture.apply([
            T.surface("popup", "dashboard", children: [T.text("0", IR.value("{perf.cpu}"))]),
            T.surface("panel", "bar", children: [T.text("0", IR.value("{clock.now}"))]),
        ])
        #expect(fixture.demanded("perf").isEmpty)
        #expect(!fixture.demanded("clock").isEmpty)
        #expect(fixture.surface("dashboard").isVisible == false)

        fixture.store.set(DependencyPath("perf", ["cpu"]), .number(7))
        fixture.runtime.open("dashboard", screenKey: nil)
        #expect(fixture.demanded("perf") == [DependencyPath("perf", ["cpu"])])
        #expect(fixture.surface("dashboard").isOpen)
        #expect(fixture.surface("dashboard").root[0].arguments[0].value == .number(7))

        fixture.runtime.close("dashboard")
        #expect(fixture.demanded("perf").isEmpty)
    }

    @Test("Vollbild versteckt ein Panel: nicht gefragt; fullscreen=show bleibt gefragt")
    func fullscreenHidesPanel() {
        let fixture = ShellFixture()
        fixture.apply([
            T.surface("panel", "bar", children: [T.text("0", IR.value("{perf.cpu}"))]),
            T.surface("panel", "clock", properties: ["fullscreen": IR.string("show")], children: [T.text("0", IR.value("{clock.now}"))]),
        ], screens: ["A", "B"])
        fixture.runtime.setHiddenByFullscreen(true, screenKey: "A")
        #expect(fixture.surface("bar", "A").isVisible == false)
        #expect(fixture.surface("bar", "B").isVisible == true)
        #expect(fixture.surface("clock", "A").isVisible == true)
        #expect(!fixture.demanded("perf").isEmpty)
        fixture.runtime.setHiddenByFullscreen(true, screenKey: "B")
        #expect(fixture.demanded("perf").isEmpty)
        #expect(!fixture.demanded("clock").isEmpty)
        fixture.runtime.setHiddenByFullscreen(false, screenKey: "A")
        #expect(!fixture.demanded("perf").isEmpty)
    }

    @Test("visible falsch hält nur das eigene Binding aktiv")
    func invisibleElementKeepsOnlyVisibleBinding() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [
            T.box("0", properties: ["visible": IR.value("{var.show}"), "tooltip": IR.value("{perf.gpu}")], children: [
                T.text("0", IR.value("{perf.cpu}")),
                .when(WhenIR(key: "1", condition: IR.value("{battery.present}"), then: [T.text("0", IR.string("b"))])),
            ]),
        ])], vars: [IR.plainVar("show", .bool, .bool(false))])
        #expect(fixture.demanded("perf").isEmpty)
        #expect(fixture.demanded("battery").isEmpty)
        #expect(fixture.demanded("var") == [DependencyPath("var", ["show"])])
        let box = fixture.surface("bar").root[0]
        #expect(box.children.count == 1)

        fixture.store.set(DependencyPath("perf", ["cpu"]), .number(4))
        fixture.store.set(DependencyPath("battery", ["present"]), .bool(true))
        fixture.vars.set("show", .bool(true))
        fixture.flush()
        #expect(fixture.demanded("perf") == [DependencyPath("perf", ["cpu"]), DependencyPath("perf", ["gpu"])])
        #expect(box.children.count == 2)
        #expect(box.children[0].arguments[0].value == .number(4))

        let kept = box.children[0]
        fixture.vars.set("show", .bool(false))
        fixture.flush()
        #expect(fixture.demanded("perf").isEmpty)
        #expect(box.children[0] === kept)
    }

    @Test("when= an on zählt zur Nachfrage, auch ohne sichtbare Oberfläche")
    func handlerWhenDemand() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("popup", "menu", children: [T.box("0", children: [])])], events: [
            EventHandlerIR(event: "battery.warning", when: IR.value("{var.enabled}"), actions: [IR.log("warn {event.level}")], span: IR.span(6)),
        ])
        #expect(fixture.demanded("var") == [DependencyPath("var", ["enabled"])])
    }

    @Test("self.* folgt pseudo, surface.* folgt dem Offen-Zustand")
    func selfAndSurfaceSignals() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("popup", "menu", children: [
            T.text("0", IR.value("{self.hover ? 'hot' : 'cold'}")),
            T.text("1", IR.value("{surface.open}")),
        ])])
        fixture.runtime.open("menu", screenKey: "A")
        let root = fixture.surface("menu").root
        #expect(root[0].arguments[0].value == .string("cold"))
        #expect(root[1].arguments[0].value == .bool(true))
        root[0].pseudo = [.hover]
        fixture.flush()
        #expect(root[0].arguments[0].value == .string("hot"))
        root[0].pseudo = []
        fixture.flush()
        #expect(root[0].arguments[0].value == .string("cold"))
    }

    @Test("Laufzeit-use: Name ausgewertet, Parameter mit Vorgabe, unbekannter Name und Parameter warnen")
    func dynamicUse() {
        let fixture = ShellFixture()
        let weather = DefineIR(name: "card-weather", parameters: [
            ParameterIR(name: "title", type: .string, defaultValue: .scalar(IR.string("Weather"))),
            ParameterIR(name: "module"),
        ], body: [T.text("0", IR.value("{title}: {module.city}", locals: ["title", "module"]))], span: IR.span(40))
        let each = EachIR(key: "0", variable: "module", list: IR.value("{var.modules}"), body: [
            .dynamicUse(DynamicUseIR(key: "0", name: IR.value("card-{module.kind}", locals: ["module"], line: 41), arguments: [
                "module": IR.value("{module}", locals: ["module"]),
                "legacy": IR.literal(.bool(true)),
            ])),
        ])
        fixture.apply([T.surface("panel", "side", children: [.each(each)])], vars: [
            IR.plainVar("modules", .list, .list([
                .record(Record([("id", .string("w")), ("kind", .string("weather")), ("city", .string("Chur"))])),
                .record(Record([("id", .string("x")), ("kind", .string("weathr"))])),
            ])),
        ], defines: [weather])
        let root = fixture.surface("side").root
        #expect(root.count == 1)
        #expect(root[0].arguments[0].value == .string("Weather: Chur"))
        #expect(fixture.warnings.contains { $0.message.contains("unknown block 'card-weathr'") })
        #expect(fixture.warnings.contains { $0.message.contains("unknown parameter 'legacy'") })
    }

    @Test("Laufzeit-use füllt unbenannten und benannten Slot mit dem Inhalt der Aufrufstelle")
    func dynamicUseSlots() {
        let fixture = ShellFixture()
        let card = DefineIR(name: "card", parameters: [ParameterIR(name: "title")], body: [
            T.box("0", children: [
                T.text("0", IR.value("{title}", locals: ["title"])),
                .slot(name: nil),
                .slot(name: "footer"),
                .slot(name: "missing"),
            ]),
        ], span: IR.span(45))
        fixture.apply([T.surface("panel", "side", children: [
            .dynamicUse(DynamicUseIR(key: "0", name: IR.string("card", line: 46), arguments: ["title": IR.string("T")], slots: [
                "": [T.text("0", IR.string("A")), T.text("1", IR.value("{var.label}"))],
                "footer": [T.text("0", IR.string("F"))],
            ])),
        ])], vars: [IR.plainVar("label", .string, .string("B"))], defines: [card])
        fixture.flush()
        let root = fixture.surface("side").root
        #expect(root.count == 1)
        let children = root.first?.children ?? []
        #expect(children.map { $0.arguments.first?.value }  == [.string("T"), .string("A"), .string("B"), .string("F")])
        #expect(fixture.surface("side").root.map(\.kind) == ["column"])
        #expect(Set(children.map(\.identity.description)).count == 4)
        #expect(fixture.warnings.map(\.message) == [])
    }

    @Test("Laufzeit-use rekursiv bis 32, darüber Warnung ohne Absturz")
    func recursiveUseCapped() {
        let fixture = ShellFixture()
        let nested = DefineIR(name: "nest", parameters: [ParameterIR(name: "level")], body: [
            T.box("0", children: [
                .dynamicUse(DynamicUseIR(key: "1", name: IR.string("nest", line: 42), arguments: ["level": IR.value("{level + 1}", locals: ["level"])])),
            ]),
        ], span: IR.span(42))
        fixture.apply([T.surface("panel", "deep", children: [
            .dynamicUse(DynamicUseIR(key: "0", name: IR.string("nest", line: 43), arguments: ["level": IR.number(1)])),
        ])], defines: [nested])
        var depth = 0
        var current = fixture.surface("deep").root
        while let first = current.first {
            depth += 1
            current = first.children
        }
        #expect(depth == ConfigLimits.useDepth)
        #expect(fixture.warnings.filter { $0.message.contains("32") }.count == 1)
    }

    @Test("Schlimmster Fall 64 IR-Ebenen × 32 use: harte Tiefengrenze 256, kein Absturz")
    func worstCaseDepth() {
        let fixture = ShellFixture()
        var body: [ChildIR] = [.dynamicUse(DynamicUseIR(key: "0", name: IR.string("deep", line: 44)))]
        for level in 0..<64 {
            body = [T.box("\(level)", children: body)]
        }
        let deep = DefineIR(name: "deep", body: body, span: IR.span(44))
        fixture.apply([T.surface("panel", "tower", children: [
            .dynamicUse(DynamicUseIR(key: "0", name: IR.string("deep", line: 45))),
        ])], defines: [deep])
        var depth = 0
        var current = fixture.surface("tower").root
        while let first = current.first {
            depth += 1
            current = first.children
        }
        #expect(depth == RuntimeLimits.elementDepth)
        #expect(fixture.runtime.stats.elementsBuilt == RuntimeLimits.elementDepth)
        #expect(fixture.warnings.contains { $0.message.contains("256") })
        fixture.apply([])
        #expect(fixture.demanded("var").isEmpty)
    }

    @Test("each baut höchstens 5 000 Einträge, Elementbudget je Oberfläche 10 000")
    func eachAndElementBudget() {
        let fixture = ShellFixture()
        let inner = EachIR(key: "0", variable: "b", list: IR.value("{var.items}"), body: [T.text("0", IR.string("x"))])
        let outer = EachIR(key: "0", variable: "a", list: IR.value("{var.items}"), body: [.each(inner)])
        let flat = EachIR(key: "1", variable: "c", list: IR.value("{var.many}"), body: [T.text("0", IR.string("y"))])
        fixture.apply([
            T.surface("panel", "grid", children: [.each(outer)]),
            T.surface("panel", "list", children: [.each(flat)]),
        ], vars: [
            IR.plainVar("items", .list, .list((0..<200).map { .number(Double($0)) })),
            IR.plainVar("many", .list, .list((0..<6_000).map { .number(Double($0)) })),
        ])
        #expect(fixture.surface("grid").root.count == RuntimeLimits.elementsPerSurface)
        #expect(fixture.surface("list").root.count == RuntimeLimits.eachEntries)
        #expect(fixture.warnings.filter { $0.message.contains("\(RuntimeLimits.elementsPerSurface) elements") }.count == 1)
        #expect(fixture.warnings.filter { $0.message.contains("5000") }.count == 1)
    }

    @Test("späte Grösse einer entfernten Oberfläche legt keinen Eintrag unter surfaces an")
    func lateSizeOfRemovedSurface() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [])])
        fixture.runtime.setSurfaceSize("bar", screenKey: "A", width: 800, height: 30)
        #expect(fixture.runtime.surfaceValue("bar", screenKey: "A", "width") == .number(800))
        fixture.apply([], id: "other")
        fixture.flush()
        fixture.runtime.setSurfaceSize("bar", screenKey: "A", width: 800, height: 31)
        #expect(fixture.store.value(DependencyPath("surfaces:A", ["bar"])) == .null)
        fixture.runtime.setSurfaceSize("ghost", screenKey: "A", width: 1, height: 1)
        #expect(fixture.store.value(DependencyPath("surfaces:A", ["ghost"])) == .null)
    }

    @Test("setScreens mit gleicher Liste baut 0 Oberflächen, neue Bildschirme bauen nur ihre")
    func setScreens() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.string("x"))])], screens: ["A", "B"])
        let before = fixture.runtime.stats
        let barA = fixture.surface("bar", "A")
        fixture.runtime.setScreens(["A", "B"])
        #expect(fixture.runtime.stats.surfacesBuilt == before.surfacesBuilt)
        #expect(fixture.runtime.stats.elementsBuilt == before.elementsBuilt)
        fixture.host.events.removeAll()
        fixture.runtime.setScreens(["A", "C"])
        #expect(fixture.runtime.stats.surfacesBuilt == before.surfacesBuilt + 1)
        #expect(fixture.runtime.surface("bar", screenKey: "A") === barA)
        #expect(fixture.runtime.surface("bar", screenKey: "B") == nil)
        #expect(fixture.host.events == ["removed:bar@B", "added:bar@C"])
    }

    @Test("toggle, close-group und Gruppen: Aufgehen schliesst die anderen der Gruppe")
    func toggleAndGroups() {
        let fixture = ShellFixture()
        fixture.apply([
            T.surface("popup", "a", properties: ["group": IR.string("g")], children: []),
            T.surface("popup", "b", properties: ["group": IR.string("g")], children: []),
            T.surface("panel", "bar", children: []),
        ])
        fixture.runtime.toggle("a")
        #expect(fixture.surface("a").isOpen)
        fixture.runtime.open("b", screenKey: nil)
        #expect(!fixture.surface("a").isOpen)
        #expect(fixture.surface("b").isOpen)
        fixture.runtime.closeGroup("g")
        #expect(!fixture.surface("b").isOpen)
        fixture.runtime.toggle("a")
        fixture.runtime.toggle("a")
        #expect(!fixture.surface("a").isOpen)
    }

    @Test("close … wait=#true wartet auf surfaceDidFinishClosing")
    func closeWaitsForHost() async {
        let fixture = ShellFixture()
        let button = HandlerIR(name: "on-click", actions: [
            IR.call("close", [IR.string("picker")], properties: ["wait": IR.literal(.bool(true))]),
            IR.log("shot"),
        ], span: IR.span(7))
        fixture.apply([
            T.surface("popup", "picker", children: [T.box("0", properties: ["id": IR.string("pick")], handlers: [button], children: [])]),
        ])
        fixture.runtime.open("picker", screenKey: "A")
        let task = fixture.runtime.trigger("on-click", on: Identity(["picker@A", "#pick"]), event: Record())
        await settle()
        #expect(fixture.log.entries == [])
        #expect(!fixture.surface("picker").isOpen)
        #expect(fixture.runtime.trigger("on-click", on: Identity(["picker@A", "#pick"]), event: Record()) == nil)
        fixture.runtime.surfaceDidFinishClosing(id: "picker", screenKey: "A")
        await task?.value
        #expect(fixture.log.entries == ["shot"])
    }

    @Test("close … wait=#true auf eine geschlossene Oberfläche wartet nicht")
    func closeWaitOnClosedSurface() async {
        let fixture = ShellFixture()
        fixture.apply([T.surface("popup", "picker", children: [])])
        await fixture.runtime.closeAndWait("picker")
        #expect(!fixture.surface("picker").isOpen)
    }

    @Test("Handler laufen mit dem Scope ihres Elements, on-Ereignisse mit when und event")
    func triggerAndEmit() async {
        let fixture = ShellFixture()
        let each = EachIR(key: "0", variable: "item", list: IR.value("{var.items}"), body: [
            T.box("0", properties: ["id": IR.value("row-{item}", locals: ["item"])], handlers: [
                HandlerIR(name: "on-click", actions: [IR.log("clicked {item} {event.button}", locals: ["item"])], span: IR.span(8)),
            ], children: []),
        ])
        fixture.apply([T.surface("panel", "list", children: [.each(each)])], vars: [
            IR.plainVar("items", .list, .list([.string("a"), .string("b")])),
            IR.plainVar("enabled", .bool, .bool(false)),
        ], events: [
            EventHandlerIR(event: "battery.warning", when: IR.value("{var.enabled}"), actions: [IR.log("warn {event.level}")], span: IR.span(9)),
            EventHandlerIR(event: "battery.warning", actions: [IR.log("always")], span: IR.span(10)),
        ])
        await fixture.runtime.trigger("on-click", on: Identity(["list@A", "#row-b"]), event: Record([("button", .string("left"))]))?.value
        #expect(fixture.log.entries == ["clicked b left"])
        fixture.runtime.emit("battery.warning", Record([("level", .number(10))]))
        await settle()
        #expect(fixture.log.entries == ["clicked b left", "always"])
        fixture.vars.set("enabled", .bool(true))
        fixture.runtime.emit("battery.warning", Record([("level", .number(5))]))
        await settle()
        #expect(fixture.log.entries == ["clicked b left", "always", "warn 5", "always"])
    }

    @Test("on hält den Provider wach, Oberflächen-Aktionen laufen über ShellRuntime")
    func eventsKeepProvidersAwakeAndActionsReachRuntime() async {
        let fixture = ShellFixture()
        let provider = StubProvider(id: "battery")
        fixture.providers.register(provider)
        fixture.apply([T.surface("popup", "menu", children: [])], events: [
            EventHandlerIR(event: "battery.warning", actions: [IR.call("open", [IR.string("menu")])], span: IR.span(11)),
        ])
        fixture.flush()
        #expect(provider.startCount == 1)
        provider.lastContext?.emit("battery.warning", Record())
        await settle()
        #expect(fixture.surface("menu").isOpen)
        #expect(fixture.runtime.stats.providersRunning == 1)
    }

    @Test("Slots eines Elements werden als slotChildren gebaut")
    func slots() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "osd", children: [
            T.box("0", slots: ["thumb": [T.text("0", IR.value("{var.level}"))]], children: []),
        ])], vars: [IR.plainVar("level", .number, .number(0.5))])
        let slider = fixture.surface("osd").root[0]
        #expect(slider.slotChildren["thumb"]?.count == 1)
        #expect(slider.slotChildren["thumb"]?.first?.arguments[0].value == .number(0.5))
        #expect(slider.slotChildren["thumb"]?.first?.identity.description == "osd@A/0/slot:thumb/0")
    }

    @Test("Oberflächen-Properties bleiben aktiv, visible der Oberfläche steuert die Sichtbarkeit")
    func surfaceProperties() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("panel", "bar", properties: ["visible": IR.value("{var.bar}"), "offset-y": IR.value("{var.offset}")], children: [
            T.text("0", IR.value("{perf.cpu}")),
        ])], vars: [IR.plainVar("bar", .bool, .bool(true)), IR.plainVar("offset", .number, .number(4))])
        let bar = fixture.surface("bar")
        #expect(bar.properties["offset-y"]?.value == .number(4))
        #expect(bar.isVisible)
        fixture.vars.set("bar", .bool(false))
        fixture.flush()
        #expect(!bar.isVisible)
        #expect(fixture.demanded("perf").isEmpty)
        fixture.vars.set("offset", .number(8))
        fixture.flush()
        #expect(bar.properties["offset-y"]?.value == .number(8))
    }
}
