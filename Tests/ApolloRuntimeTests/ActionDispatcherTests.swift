import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
final class ActionLog {
    var entries: [String] = []
}

@MainActor
final class LogAction: ActionImplementation {
    let log: ActionLog

    init(_ log: ActionLog) {
        self.log = log
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: ActionRuntime) async throws {
        log.entries.append(call.arguments.map(Self.text).joined(separator: ","))
    }

    static func text(_ value: Value) -> String {
        switch value {
        case .null: "null"
        case .bool(let flag): flag ? "true" : "false"
        case .number(let number): number == number.rounded() ? String(Int(number)) : String(number)
        case .string(let text): text
        case .list(let items): "[" + items.map(text).joined(separator: ",") + "]"
        case .record(let record): "{" + record.keys.map { "\($0)=\(text(record[$0] ?? .null))" }.joined(separator: ",") + "}"
        default: value.typeName
        }
    }
}

@MainActor
final class SlowAction: ActionImplementation {
    let log: ActionLog
    let gate: Gate

    init(_ log: ActionLog, gate: Gate) {
        self.log = log
        self.gate = gate
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: ActionRuntime) async throws {
        await gate.wait()
        log.entries.append("slow-done")
    }
}

struct ActionTestFailure: Error {}

@MainActor
final class FailingAction: ActionImplementation {
    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: ActionRuntime) async throws {
        throw ActionTestFailure()
    }
}

@MainActor
final class FakeSurfaces: SurfaceControlling {
    let log: ActionLog
    let closeGate = Gate()

    init(_ log: ActionLog) {
        self.log = log
    }

    func open(_ surfaceID: String, screenKey: String?) {
        log.entries.append("open:\(surfaceID)")
    }

    func close(_ surfaceID: String) {
        log.entries.append("close:\(surfaceID)")
    }

    func closeAndWait(_ surfaceID: String) async {
        log.entries.append("close-wait:\(surfaceID)")
        await closeGate.wait()
        log.entries.append("closed:\(surfaceID)")
    }

    func toggle(_ surfaceID: String) {
        log.entries.append("toggle:\(surfaceID)")
    }

    func closeGroup(_ group: String) {
        log.entries.append("close-group:\(group)")
    }
}

@MainActor
final class RecordingProvider: ProviderInstance {
    let schema: ProviderSchema
    var performed: [(String, [Value], Record)] = []

    init(id: String) {
        schema = ProviderSchema(id: id, doc: "recording")
    }

    func start(_ context: ProviderContext) {}
    func demandChanged(_ demanded: Set<DependencyPath>) {}
    func configure(_ settings: Record) {}
    func stop() {}

    func perform(_ action: String, arguments: [Value], properties: Record) async throws -> Value {
        performed.append((action, arguments, properties))
        return .null
    }
}

@MainActor
struct DispatcherFixture {
    let store: SignalStore
    let bindings: BindingEngine
    let clock: ManualRuntimeClock
    let vars: VarStore
    let providers: ProviderHost
    let dispatcher: ActionDispatcher
    let log = ActionLog()
    let surfaces: FakeSurfaces
    var warnings: [Diagnostic] { warningLog.entries }
    let warningLog = WarningLog()

    init(vars declarations: [VarDecl] = []) {
        let scheduler = ManualFlushScheduler()
        store = SignalStore(scheduler: scheduler)
        bindings = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        clock = ManualRuntimeClock()
        vars = VarStore(store: store, bindings: bindings, clock: clock)
        providers = ProviderHost(store: store)
        dispatcher = ActionDispatcher(evaluator: BindingTestHarness.evaluator(), vars: vars, providers: providers, store: store, clock: clock)
        surfaces = FakeSurfaces(log)
        dispatcher.surfaces = surfaces
        dispatcher.register("log", LogAction(log))
        dispatcher.register("fail", FailingAction())
        let sink = warningLog
        dispatcher.onWarning = { sink.entries.append($0) }
        vars.onWarning = { sink.entries.append($0) }
        vars.declare(declarations, persisted: [:], shell: Record())
    }

    @discardableResult
    func trigger(_ actions: [ActionIR], site: String? = nil, event: Record = Record(), scope: LocalScope = LocalScope()) -> Task<Void, Never>? {
        dispatcher.trigger(actions, site: site, environment: ActionEnvironment(scope: scope, event: event))
    }
}

@MainActor
final class WarningLog {
    var entries: [Diagnostic] = []
}

@MainActor
@Suite("ActionDispatcher")
struct ActionDispatcherTests {
    typealias IR = RuntimeIR

    @Test("Aktionen laufen der Reihe nach und lesen den Zustand zum Zeitpunkt ihres Laufs")
    func runsInOrder() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("x", .number, .number(0))])
        await fixture.trigger([
            IR.log("a"),
            IR.call("set", [IR.string("x"), IR.number(1)]),
            IR.log("{var.x}"),
            IR.call("set", [IR.string("x"), IR.value("{var.x + 1}")]),
            IR.log("{var.x}"),
        ])?.value
        #expect(fixture.log.entries == ["a", "1", "2"])
    }

    @Test("event und Schleifenvariablen sind im Scope")
    func eventAndLocalsVisible() async {
        let fixture = DispatcherFixture()
        await fixture.trigger(
            [IR.log("{event.dx} {item}", locals: ["item"])],
            event: Record([("dx", .number(3))]),
            scope: LocalScope(["item": .string("x")])
        )?.value
        #expect(fixture.log.entries == ["3 x"])
    }

    @Test("Ein ganzer Wert behält seinen Typ, Kinder werden beim Auslösen ausgewertet")
    func wholeValueKeepsType() async {
        let fixture = DispatcherFixture(vars: [
            IR.plainVar("cards", .list, .list([.string("a"), .string("b")])),
            IR.plainVar("pages", .list, .list([])),
        ])
        await fixture.trigger([
            IR.call("set", [IR.string("pages")], children: [
                .record([
                    ValueTemplateField(name: "name", value: .scalar(IR.string("Overview"))),
                    ValueTemplateField(name: "cards", value: .scalar(IR.value("{var.cards}"))),
                ]),
            ]),
        ])?.value
        #expect(fixture.vars.value("pages") == .list([.record(Record([("name", .string("Overview")), ("cards", .list([.string("a"), .string("b")]))]))]))
    }

    @Test("wait=#true hält den Handler an, ohne wait läuft er weiter")
    func waitPropertyHolds() async {
        let fixture = DispatcherFixture()
        let gate = Gate()
        fixture.dispatcher.register("slow", SlowAction(fixture.log, gate: gate))

        let holding = fixture.trigger([
            IR.call("slow", properties: ["wait": IR.literal(.bool(true))]),
            IR.log("after"),
        ])
        await settle()
        #expect(fixture.log.entries == [])
        gate.open()
        await holding?.value
        #expect(fixture.log.entries == ["slow-done", "after"])

        fixture.log.entries.removeAll()
        let otherGate = Gate()
        fixture.dispatcher.register("slow", SlowAction(fixture.log, gate: otherGate))
        fixture.trigger([IR.call("slow"), IR.log("after")])
        #expect(fixture.log.entries == ["after"])
        otherGate.open()
        await settle()
        #expect(fixture.log.entries == ["after", "slow-done"])
    }

    @Test("close … wait=#true wartet auf die Rückmeldung des Hosts")
    func closeWaitAwaitsHost() async {
        let fixture = DispatcherFixture()
        let task = fixture.trigger([
            IR.call("close", [IR.string("picker")], properties: ["wait": IR.literal(.bool(true))]),
            IR.log("shot"),
        ])
        await settle()
        #expect(fixture.log.entries == ["close-wait:picker"])
        fixture.surfaces.closeGate.open()
        await task?.value
        #expect(fixture.log.entries == ["close-wait:picker", "closed:picker", "shot"])
    }

    @Test("Oberflächen-Aktionen gehen an den Oberflächen-Steuerer")
    func surfaceActions() async {
        let fixture = DispatcherFixture()
        await fixture.trigger([
            IR.call("open", [IR.string("a")]),
            IR.call("close", [IR.string("b")]),
            IR.call("toggle", [IR.string("c")]),
            IR.call("close-group", [IR.string("g")]),
        ])?.value
        #expect(fixture.log.entries == ["open:a", "close:b", "toggle:c", "close-group:g"])
    }

    @Test("when/else wählt den Zweig beim Auslösen")
    func whenElse() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("on", .bool, .bool(false))])
        let actions: [ActionIR] = [.when(condition: IR.value("{var.on}"), then: [IR.log("then")], otherwise: [IR.log("else")])]
        await fixture.trigger(actions)?.value
        fixture.vars.set("on", .bool(true))
        await fixture.trigger(actions)?.value
        #expect(fixture.log.entries == ["else", "then"])
    }

    @Test("switch mit mehreren Werten je case und default")
    func switchCases() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("tab", .string, .string("media"))])
        let actions: [ActionIR] = [.switchOn(
            subject: IR.value("{var.tab}"),
            cases: [
                ActionCaseIR(values: [IR.string("media")], body: [IR.log("media")]),
                ActionCaseIR(values: [IR.string("performance"), IR.string("weather")], body: [IR.log("perf-or-weather")]),
            ],
            otherwise: [IR.log("default")]
        )]
        for tab in ["media", "weather", "performance", "other"] {
            fixture.vars.set("tab", .string(tab))
            await fixture.trigger(actions)?.value
        }
        #expect(fixture.log.entries == ["media", "perf-or-weather", "perf-or-weather", "default"])
    }

    @Test("each läuft der Reihe nach über die Liste vom Start, auch wenn der Handler sie ändert")
    func eachUsesListFromStart() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("items", .list, .list([.string("a"), .string("b")]))])
        await fixture.trigger([
            .each(variable: "item", index: "i", list: IR.value("{var.items}"), body: [
                IR.call("list.insert", [IR.string("items")], properties: ["value": IR.string("z")]),
                IR.log("{i}:{item}", locals: ["item", "i"]),
            ]),
        ])?.value
        #expect(fixture.log.entries == ["0:a", "1:b"])
        #expect(fixture.vars.value("items") == .list([.string("a"), .string("b"), .string("z"), .string("z")]))
    }

    @Test("repeat läuft n-mal, höchstens 100, mit Warnung")
    func repeatCapped() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("n", .number, .number(0))])
        await fixture.trigger([.repeatBlock(count: IR.number(3), body: [IR.call("set", [IR.string("n"), IR.value("{var.n + 1}")])])])?.value
        #expect(fixture.vars.value("n") == .number(3))
        await fixture.trigger([.repeatBlock(count: IR.number(500, line: 7), body: [IR.call("set", [IR.string("n"), IR.value("{var.n + 1}")])])])?.value
        #expect(fixture.vars.value("n") == .number(103))
        #expect(fixture.warnings.filter { $0.message.contains("repeat") }.count == 1)
    }

    @Test("wait wartet auf die Uhr, 20s wird auf 10s gekappt mit Warnung")
    func waitCapped() async {
        let fixture = DispatcherFixture()
        let task = fixture.trigger([IR.call("wait", [IR.string("20s")], line: 4), IR.log("done")])
        await settle()
        fixture.clock.advance(by: 9.9)
        await settle()
        #expect(fixture.log.entries == [])
        fixture.clock.advance(by: 0.1)
        await task?.value
        #expect(fixture.log.entries == ["done"])
        #expect(fixture.warnings.count == 1)
        #expect(fixture.warnings.first?.message.contains("10s") == true)
        #expect(fixture.warnings.first?.span == RuntimeIR.span(4))
    }

    @Test("wait versteht ms, s, m und Zahlen in Sekunden")
    func waitUnits() async {
        let fixture = DispatcherFixture()
        let task = fixture.trigger([IR.call("wait", [IR.string("250ms")]), IR.log("a"), IR.call("wait", [IR.number(1)]), IR.log("b")])
        await settle()
        fixture.clock.advance(by: 0.25)
        await settle()
        #expect(fixture.log.entries == ["a"])
        fixture.clock.advance(by: 1)
        await task?.value
        #expect(fixture.log.entries == ["a", "b"])
    }

    @Test("Doppelklick auf einen Handler mit close läuft einmal, ohne close zweimal")
    func doubleTriggerGuard() async {
        let fixture = DispatcherFixture()
        let closing: [ActionIR] = [IR.call("close", [IR.string("popup")]), IR.call("wait", [IR.string("1s")]), IR.log("closing")]
        let first = fixture.trigger(closing, site: "button/on-click")
        let second = fixture.trigger(closing, site: "button/on-click")
        #expect(first != nil)
        #expect(second == nil)
        fixture.clock.advance(by: 1)
        await first?.value
        #expect(fixture.log.entries == ["close:popup", "closing"])

        fixture.log.entries.removeAll()
        let plain: [ActionIR] = [IR.call("wait", [IR.string("1s")]), IR.log("plain")]
        let a = fixture.trigger(plain, site: "other/on-click")
        let b = fixture.trigger(plain, site: "other/on-click")
        fixture.clock.advance(by: 1)
        await a?.value
        await b?.value
        #expect(fixture.log.entries == ["plain", "plain"])
    }

    @Test("Der Schutz sieht close auch verschachtelt und gilt nicht mehr nach Ende des Handlers")
    func guardNestedAndReleases() async {
        let fixture = DispatcherFixture()
        let nested: [ActionIR] = [
            .when(condition: IR.literal(.bool(true)), then: [IR.call("wait", [IR.string("1s")])], otherwise: [IR.call("toggle", [IR.string("x")])]),
        ]
        let first = fixture.trigger(nested, site: "s")
        #expect(fixture.trigger(nested, site: "s") == nil)
        fixture.clock.advance(by: 1)
        await first?.value
        #expect(fixture.trigger(nested, site: "s") != nil)
    }

    @Test("Eine werfende Aktion stoppt die übrigen nicht, Warnung nur einmal bei 10 Auslösungen")
    func failingActionWarnsOnce() async {
        let fixture = DispatcherFixture()
        let actions: [ActionIR] = [IR.call("fail", line: 5), IR.call("does-not-exist", line: 6), IR.log("rest")]
        for _ in 0..<10 {
            await fixture.trigger(actions)?.value
        }
        #expect(fixture.log.entries.count == 10)
        #expect(fixture.warnings.filter { $0.span == RuntimeIR.span(5) }.count == 1)
        #expect(fixture.warnings.filter { $0.span == RuntimeIR.span(6) }.count == 1)
        #expect(fixture.warnings.count == 2)
    }

    @Test("Eine werfende Aktion ohne wait meldet sich auch nach dem Ende des Handlers")
    func failingDetachedActionWarns() async {
        let fixture = DispatcherFixture()
        await fixture.trigger([IR.call("fail", line: 8)])?.value
        await settle()
        #expect(fixture.warnings.map(\.span) == [RuntimeIR.span(8)])
    }

    @Test("set auf ein abgeleitetes var warnt und ändert nichts")
    func setDerivedWarns() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("a", .number, .number(1)), IR.derivedVar("b", .number, from: "{var.a * 2}")])
        await fixture.trigger([IR.call("set", [IR.string("b"), IR.number(5)], line: 3)])?.value
        #expect(fixture.warnings.contains { $0.span == RuntimeIR.span(3) && $0.message.contains("derived") })
    }

    @Test("toggle-var kehrt bool um und warnt bei anderem Typ; reset stellt die Vorgabe her")
    func toggleAndReset() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("flag", .bool, .bool(false)), IR.plainVar("text", .string, .string("x"))])
        await fixture.trigger([IR.call("toggle-var", [IR.string("flag")]), IR.call("toggle-var", [IR.string("text")], line: 2)])?.value
        #expect(fixture.vars.value("flag") == .bool(true))
        #expect(fixture.warnings.contains { $0.span == RuntimeIR.span(2) })
        await fixture.trigger([IR.call("reset", [IR.string("flag")])])?.value
        #expect(fixture.vars.value("flag") == .bool(false))
    }

    @Test("set … for= setzt vorübergehend über die Uhr")
    func setFor() async {
        let fixture = DispatcherFixture(vars: [IR.plainVar("osd", .bool, .bool(false))])
        await fixture.trigger([IR.call("set", [IR.string("osd"), IR.literal(.bool(true))], properties: ["for": IR.string("500ms")])])?.value
        #expect(fixture.vars.value("osd") == .bool(true))
        fixture.clock.advance(by: 0.5)
        #expect(fixture.vars.value("osd") == .bool(false))
    }

    @Test("set mit in= und field= wirkt auf das Feld eines Eintrags")
    func setInField() async {
        let pages: Value = .list([.record(Record([("id", .string("p1")), ("title", .string("Old"))]))])
        let fixture = DispatcherFixture(vars: [IR.plainVar("pages", .list, pages)])
        await fixture.trigger([IR.call("set", [IR.string("pages"), IR.string("New")], properties: ["in": IR.string("p1"), "field": IR.string("title")])])?.value
        #expect(fixture.vars.value("pages") == .list([.record(Record([("id", .string("p1")), ("title", .string("New"))]))]))
    }

    @Test("list-Aktionen: insert mit Kindern, remove, move, update, swap und move-to als Transaktion")
    func listActions() async {
        let fixture = DispatcherFixture(vars: [
            IR.plainVar("a", .list, .list([.string("x"), .string("y")])),
            IR.plainVar("b", .list, .list([.string("q")])),
            IR.plainVar("cards", .list, .list([.record(Record([("id", .string("c1")), ("size", .number(1))]))])),
        ])
        await fixture.trigger([
            IR.call("list.insert", [IR.string("a")], properties: ["at": IR.number(0)], children: [.scalar(IR.string("w"))]),
            IR.call("list.remove", [IR.string("a")], properties: ["key": IR.string("y")]),
            IR.call("list.move", [IR.string("a")], properties: ["from": IR.number(0), "to": IR.number(2)]),
            IR.call("list.update", [IR.string("cards")], properties: ["key": IR.string("c1")], children: [.record([ValueTemplateField(name: "size", value: .scalar(IR.number(2)))])]),
            IR.call("list.swap", [IR.string("a"), IR.number(0), IR.string("b"), IR.number(0)]),
            IR.call("list.move-to", [IR.string("a"), IR.string("b")], properties: ["from": IR.number(1), "to": IR.number(0)]),
        ])?.value
        #expect(fixture.vars.value("a") == .list([.string("q")]))
        #expect(fixture.vars.value("b") == .list([.string("w"), .string("x")]))
        #expect(fixture.vars.value("cards") == .list([.record(Record([("id", .string("c1")), ("size", .number(2))]))]))

        await fixture.trigger([IR.call("list.move-to", [IR.string("a"), IR.string("b")], properties: ["from": IR.number(9), "to": IR.number(0)], line: 9)])?.value
        #expect(fixture.vars.value("a") == .list([.string("q")]))
        #expect(fixture.vars.value("b") == .list([.string("w"), .string("x")]))
        #expect(fixture.warnings.contains { $0.span == RuntimeIR.span(9) })
    }

    @Test("Provider-Aktionen gehen an den ProviderHost")
    func providerActions() async {
        let fixture = DispatcherFixture()
        let provider = RecordingProvider(id: "media")
        fixture.providers.register(provider)
        await fixture.trigger([IR.call("media.seek", [IR.number(30)], properties: ["wait": IR.literal(.bool(true)), "relative": IR.literal(.bool(true))])])?.value
        #expect(provider.performed.count == 1)
        #expect(provider.performed.first?.0 == "media.seek")
        #expect(provider.performed.first?.1 == [.number(30)])
        #expect(provider.performed.first?.2["relative"] == .bool(true))
    }

    @Test("Ein laufender Handler arbeitet mit seiner eingefangenen IR zu Ende")
    func runningHandlerKeepsCapturedIR() async {
        let fixture = DispatcherFixture()
        var actions: [ActionIR] = [IR.call("wait", [IR.string("1s")]), IR.log("old")]
        let task = fixture.trigger(actions, site: "h")
        actions = [IR.log("new")]
        fixture.clock.advance(by: 1)
        await task?.value
        #expect(fixture.log.entries == ["old"])
        #expect(actions.count == 1)
    }

    @Test("run über ActionRuntime läuft verschachtelt im selben Handler")
    func nestedRun() async {
        let fixture = DispatcherFixture()
        await fixture.dispatcher.run([IR.log("a"), IR.log("b")], environment: ActionEnvironment())
        #expect(fixture.log.entries == ["a", "b"])
    }
}

@MainActor
@Suite("BindingEngine mit CompiledValue")
struct CompiledValueBindingTests {
    @Test("bind(CompiledValue) reagiert auf globale Abhängigkeiten und liest lokale Namen")
    func bindCompiledValue() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        var values: [Value] = []
        let handle = engine.bind(RuntimeIR.value("{item}-{perf.cpu}", locals: ["item"]), scope: LocalScope(["item": .string("a")]), active: true) { values.append($0) }
        #expect(handle.currentValue == .string("a-"))
        store.set(DependencyPath("perf", ["cpu"]), .number(2))
        engine.flush()
        #expect(handle.currentValue == .string("a-2"))
        handle.updateScope(LocalScope(["item": .string("b")]))
        engine.flush()
        #expect(handle.currentValue == .string("b-2"))
        #expect(values.count == 3)
    }

    @Test("Ein Ausdruck nur aus lokalen Namen abonniert nichts, reagiert aber auf updateScope")
    func localOnlyIsNotStatic() {
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let engine = BindingEngine(store: store, evaluator: BindingTestHarness.evaluator())
        let compiled = RuntimeIR.value("app-{app.id}", locals: ["app"])
        #expect(compiled.isConstant)
        let handle = engine.bind(compiled, scope: LocalScope(["app": .record(Record([("id", .string("x"))]))]), active: true) { _ in }
        #expect(handle.currentValue == .string("app-x"))
        handle.updateScope(LocalScope(["app": .record(Record([("id", .string("y"))]))]))
        engine.flush()
        #expect(handle.currentValue == .string("app-y"))
    }
}
