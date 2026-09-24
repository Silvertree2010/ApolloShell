import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Reload-Abgleich")
struct ReloadTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    static let vars = [
        IR.plainVar("label", .string, .string("L")),
        IR.plainVar("size", .number, .number(10)),
        IR.plainVar("show", .bool, .bool(true)),
        IR.plainVar("items", .list, .list([.string("a"), .string("b")])),
    ]

    static func dashboard(line: Int = 1) -> [SurfaceIR] {
        let each = EachIR(key: "2", variable: "item", list: IR.value("{var.items}", line: line + 3), body: [
            T.text("0", IR.value("{item | upper}", locals: ["item"], line: line + 4), line: line + 4),
        ])
        return [
            T.surface("panel", "bar", properties: ["height": IR.value("{var.size}", line: line)], children: [
                T.text("0", IR.value("{var.label}", line: line + 1), properties: ["class": IR.string("title", line: line + 1)], line: line + 1),
                T.box("1", properties: ["visible": IR.value("{var.show}", line: line + 2)], children: [
                    T.text("0", IR.value("{var.size * 2}", line: line + 2), properties: ["id": IR.string("size", line: line + 2)], line: line + 2),
                ], line: line + 2),
                .each(each),
            ]),
            T.surface("popup", "menu", children: [T.text("0", IR.value("{self.hover ? 'hot' : 'cold'}", line: line + 5), line: line + 5)]),
        ]
    }

    func counts(_ fixture: ShellFixture) -> [Int] {
        let stats = fixture.runtime.stats
        return [stats.bindingsEvaluated, stats.elementsBuilt, stats.surfacesBuilt]
    }

    @Test("Reload ohne Änderung: 0 Auswertungen, 0 gebaut, keine Host-Ereignisse, gleiche Instanzen")
    func unchangedReload() {
        let fixture = ShellFixture()
        fixture.apply(Self.dashboard(), vars: Self.vars, screens: ["A", "B"])
        fixture.flush()
        let before = counts(fixture)
        let root = fixture.surface("bar", "B").root
        fixture.host.events.removeAll()
        fixture.apply(Self.dashboard(), vars: Self.vars, screens: ["A", "B"])
        fixture.flush()
        #expect(counts(fixture) == before)
        #expect(fixture.host.events == [])
        #expect(ShellRuntime.same(fixture.surface("bar", "B").root, root))
    }

    @Test("Nur verschobene Zeilen (auch in Filtern): 0 Auswertungen, keine Host-Ereignisse, Bindings leben weiter")
    func spanShiftOnly() {
        let fixture = ShellFixture()
        fixture.apply(Self.dashboard(), vars: Self.vars)
        fixture.flush()
        let before = counts(fixture)
        let root = fixture.surface("bar").root
        fixture.host.events.removeAll()
        fixture.apply(Self.dashboard(line: 40), vars: Self.vars)
        fixture.flush()
        #expect(counts(fixture) == before)
        #expect(fixture.host.events == [])
        #expect(ShellRuntime.same(fixture.surface("bar").root, root))
        #expect(root[0].instance(ir: \.span.start.line) == 41)
        _ = fixture.vars.set("label", .string("M"), for: nil)
        _ = fixture.vars.set("items", .list([.string("c")]), for: nil)
        fixture.flush()
        #expect(root[0].arguments[0].value == .string("M"))
        #expect(fixture.surface("bar").root.last?.arguments[0].value == .string("C"))
    }

    @Test("Property und Binding geändert: gleiche Instanz und Zelle, neuer Wert, altes Binding beendet")
    func propertyAndBindingChanged() {
        let fixture = ShellFixture()
        let vars = [IR.plainVar("a", .string, .string("A")), IR.plainVar("b", .string, .string("B"))]
        fixture.apply([T.surface("panel", "bar", children: [
            T.text("0", IR.value("{var.a}"), properties: ["class": IR.string("x"), "tip": IR.value("{var.a}")]),
        ])], vars: vars)
        fixture.flush()
        let element = fixture.surface("bar").root[0]
        let tip = element.properties["tip"]
        let argument = element.arguments[0]
        fixture.host.events.removeAll()
        fixture.apply([T.surface("panel", "bar", children: [
            T.text("0", IR.value("{var.b}"), properties: ["class": IR.string("y"), "tip": IR.value("{var.b}")]),
        ])], vars: vars)
        #expect(fixture.surface("bar").root[0] === element)
        #expect(element.properties["tip"] === tip)
        #expect(element.arguments[0] === argument)
        #expect(element.property("class") == .string("y"))
        #expect(element.property("tip") == .string("B"))
        #expect(argument.value == .string("B"))
        #expect(fixture.host.events == ["changed:bar@A"])
        let evaluated = fixture.runtime.stats.bindingsEvaluated
        _ = fixture.vars.set("a", .string("Z"), for: nil)
        fixture.flush()
        #expect(fixture.runtime.stats.bindingsEvaluated == evaluated)
    }

    @Test("Handler geändert: Instanz bleibt, trigger nimmt den neuen Handler, laufender alter Handler endet normal")
    func handlerChanged() async {
        let fixture = ShellFixture()
        let old = HandlerIR(name: "on-click", actions: [IR.call("wait", [IR.string("1s")]), IR.log("old")], span: IR.span(5))
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.string("x"), handlers: [old])])])
        let element = fixture.surface("bar").root[0]
        let running = fixture.runtime.trigger("on-click", on: element.identity, event: Record())
        await settle()
        let new = HandlerIR(name: "on-click", actions: [IR.log("new")], span: IR.span(6))
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.string("x"), handlers: [new])])])
        #expect(fixture.surface("bar").root[0] === element)
        await fixture.runtime.trigger("on-click", on: element.identity, event: Record())?.value
        fixture.clock.advance(by: 2)
        await running?.value
        #expect(fixture.log.entries == ["new", "old"])
    }

    static func labelled(_ labels: [String], ids: Bool) -> [SurfaceIR] {
        [T.surface("panel", "bar", children: labels.enumerated().map { index, label in
            T.text(ids ? label : String(index), IR.string(label), properties: ids ? ["id": IR.string(label)] : [:])
        })]
    }

    @Test("Kind vorn eingefügt: ohne id wandert der Zustand mit dem Index, mit id bleibt er beim Element", arguments: [false, true])
    func insertedChild(ids: Bool) {
        let fixture = ShellFixture()
        fixture.apply(Self.labelled(["a", "b"], ids: ids))
        let old = fixture.surface("bar").root
        old[1].pseudo = [.hover]
        fixture.apply(Self.labelled(["n", "a", "b"], ids: ids))
        let root = fixture.surface("bar").root
        #expect(root.map { $0.arguments[0].value } == [.string("n"), .string("a"), .string("b")])
        #expect(fixture.runtime.stats.elementsBuilt == 3)
        if ids {
            #expect(root[1] === old[0] && root[2] === old[1])
            #expect(root[2].pseudo == [.hover] && root[1].pseudo == [])
        } else {
            #expect(root[0] === old[0] && root[1] === old[1])
            #expect(root[1].pseudo == [.hover] && root[2].pseudo == [])
        }
    }

    @Test("Kind mit id verschoben: Instanzen bleiben, Reihenfolge neu, nichts gebaut")
    func movedWithID() {
        let fixture = ShellFixture()
        fixture.apply(Self.labelled(["a", "b", "c"], ids: true))
        let old = fixture.surface("bar").root
        fixture.apply(Self.labelled(["c", "a", "b"], ids: true))
        let root = fixture.surface("bar").root
        #expect(root[0] === old[2] && root[1] === old[0] && root[2] === old[1])
        #expect(fixture.runtime.stats.elementsBuilt == 3)
    }

    @Test("Kind entfernt: Instanz weg, Bindings beendet")
    func removedChild() {
        let fixture = ShellFixture()
        let vars = [IR.plainVar("a", .string, .string("A")), IR.plainVar("b", .string, .string("B"))]
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.value("{var.a}")), T.text("1", IR.value("{var.b}"))])], vars: vars)
        fixture.flush()
        let live = fixture.bindings.liveBindingCount
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.value("{var.a}"))])], vars: vars)
        fixture.flush()
        #expect(fixture.surface("bar").root.count == 1)
        #expect(fixture.bindings.liveBindingCount == live - 1)
        #expect(fixture.runtime.element(Identity(["bar@A", "1"])) == nil)
        let evaluated = fixture.runtime.stats.bindingsEvaluated
        _ = fixture.vars.set("b", .string("Z"), for: nil)
        fixture.flush()
        #expect(fixture.runtime.stats.bindingsEvaluated == evaluated)
    }

    @Test("Art geändert bei gleicher Identität: Teilbaum ersetzt, keine Zellen und kein Pseudo-Zustand übernommen")
    func kindChanged() {
        let fixture = ShellFixture()
        let hover = IR.value("{self.hover ? 'hot' : 'cold'}")
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", hover, properties: ["tip": hover])])])
        let old = fixture.surface("bar").root[0]
        old.pseudo = [.hover]
        fixture.flush()
        fixture.apply([T.surface("panel", "bar", children: [T.box("0", properties: ["tip": hover], children: [T.text("0", IR.string("inner"))])])])
        fixture.flush()
        let new = fixture.surface("bar").root[0]
        #expect(new !== old)
        #expect(new.kind == "column" && new.identity == old.identity)
        #expect(new.properties["tip"] !== old.properties["tip"])
        #expect(new.pseudo == [])
        #expect(new.property("tip") == .string("cold"))
        #expect(new.children.first?.arguments.first?.value == .string("inner"))
        new.pseudo = [.hover]
        fixture.flush()
        #expect(new.property("tip") == .string("hot"))
    }

    @Test("id-Element wandert in einen anderen Elternknoten und behält Instanz, Zellen und Pseudo-Zustand", arguments: [(0, 1), (1, 0)])
    func idElementChangesParent(from: Int, to: Int) {
        let fixture = ShellFixture()
        let moving = T.text("x", IR.value("{var.a}"), properties: ["id": IR.string("x")])
        func surfaces(_ at: Int) -> [SurfaceIR] {
            [T.surface("panel", "bar", children: [
                T.box("0", children: at == 0 ? [moving] : [T.text("0", IR.string("p"))]),
                T.box("1", children: at == 1 ? [moving] : [T.text("0", IR.string("q"))]),
            ])]
        }
        fixture.apply(surfaces(from), vars: [IR.plainVar("a", .string, .string("A"))])
        let element = fixture.surface("bar").root[from].children[0]
        let cell = element.arguments[0]
        element.pseudo = [.focus]
        let built = fixture.runtime.stats.elementsBuilt
        fixture.apply(surfaces(to), vars: [IR.plainVar("a", .string, .string("A"))])
        let root = fixture.surface("bar").root
        #expect(root[to].children.first === element)
        #expect(root[from].children.map(\.kind) == ["text"])
        #expect(root[from].children.first !== element)
        #expect(element.arguments[0] === cell && element.pseudo == [.focus])
        #expect(fixture.runtime.stats.elementsBuilt == built + 1)
        _ = fixture.vars.set("a", .string("B"), for: nil)
        fixture.flush()
        #expect(cell.value == .string("B"))
    }

    @Test("var: geänderte Vorgabe behält den Wert, geänderter Typ nicht, Config-Wechsel tauscht den Zustand")
    func varTakeover() {
        let fixture = ShellFixture()
        let surfaces = [T.surface("panel", "bar", children: [T.text("0", IR.value("{var.n}"))])]
        fixture.apply(surfaces, vars: [IR.plainVar("n", .number, .number(1)), IR.plainVar("s", .string, .string("a"))])
        _ = fixture.vars.set("n", .number(5), for: nil)
        _ = fixture.vars.set("s", .string("b"), for: nil)
        fixture.apply(surfaces, vars: [IR.plainVar("n", .number, .number(2)), IR.plainVar("s", .number, .number(0))])
        #expect(fixture.vars.value("n") == .number(5))
        #expect(fixture.vars.value("s") == .number(0))
        let element = fixture.surface("bar").root[0]
        #expect(element.arguments[0].value == .number(5))
        fixture.apply(surfaces, vars: [IR.plainVar("n", .number, .number(2))], id: "other")
        #expect(fixture.vars.value("n") == .number(2))
        #expect(fixture.surface("bar").root[0] === element)
        #expect(element.arguments[0].value == .number(2))
    }

    @Test("laufendes set … for= läuft über den Reload hinweg zurück")
    func transientSetSurvivesReload() {
        let fixture = ShellFixture()
        let vars = [IR.plainVar("mode", .string, .string("idle"))]
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.value("{var.mode}"))])], vars: vars)
        _ = fixture.vars.set("mode", .string("busy"), for: 2)
        fixture.apply([T.surface("panel", "bar", children: [T.text("0", IR.value("{var.mode}!"))])], vars: vars)
        #expect(fixture.surface("bar").root[0].arguments[0].value == .string("busy!"))
        fixture.clock.advance(by: 3)
        fixture.flush()
        #expect(fixture.surface("bar").root[0].arguments[0].value == .string("idle!"))
    }

    @Test("Offenes Popup bleibt offen; Art gewechselt meldet surfaceReplaced statt Entfernen und Hinzufügen")
    func popupStaysOpen() {
        let fixture = ShellFixture()
        func menu(_ kind: String, width: Double) -> [SurfaceIR] {
            [T.surface(kind, "menu", properties: ["width": IR.number(width)], children: [T.text("0", IR.string("x"))])]
        }
        fixture.apply(menu("popup", width: 100))
        fixture.runtime.open("menu", screenKey: "A")
        let instance = fixture.surface("menu")
        fixture.host.events.removeAll()
        fixture.apply(menu("popup", width: 200))
        #expect(fixture.surface("menu") === instance)
        #expect(instance.isOpen)
        #expect(instance.property("width") == .number(200))
        #expect(fixture.host.events == ["changed:menu@A"])
        fixture.apply(menu("overlay", width: 200))
        #expect(fixture.surface("menu") !== instance)
        #expect(fixture.host.events == ["changed:menu@A", "replaced:menu@A"])
    }

    @Test("Oberflächen neu und entfernt: nur für diese Host-Ereignisse, die übrigen behalten ihre Instanz")
    func surfacesAddedAndRemoved() {
        let fixture = ShellFixture()
        func surfaces(_ ids: [String]) -> [SurfaceIR] {
            ids.map { T.surface("panel", $0, children: [T.text("0", IR.string($0))]) }
        }
        fixture.apply(surfaces(["a", "b"]), screens: ["A", "B"])
        let kept = fixture.surface("b", "B")
        fixture.host.events.removeAll()
        fixture.apply(surfaces(["b", "c"]), screens: ["A", "B"])
        #expect(fixture.surface("b", "B") === kept)
        #expect(fixture.runtime.surface("a", screenKey: "A") == nil)
        #expect(fixture.host.events == ["removed:a@A", "removed:a@B", "added:c@A", "added:c@B"])
    }

    @Test("Ganzer Abgleich in einer Transaktion: genau ein Flush, Werte danach ohne weiteren Flush aktuell")
    func singleTransaction() {
        let fixture = ShellFixture()
        fixture.apply(Self.dashboard(), vars: Self.vars)
        fixture.flush()
        let flushes = fixture.bindings.flushCount
        var changed = Self.dashboard()
        changed[0].properties["height"] = IR.value("{var.size + 1}")
        changed[0].children.append(T.text("3", IR.value("{var.label}?")))
        fixture.apply(changed, vars: Self.vars)
        #expect(fixture.bindings.flushCount == flushes + 1)
        #expect(fixture.surface("bar").property("height") == .number(11))
        #expect(fixture.surface("bar").root.last?.arguments[0].value == .string("L?"))
    }

    @Test("each-Rumpf geändert: Einträge behalten ihre Instanzen und gleichen den Rumpf ab")
    func eachBodyChanged() {
        let fixture = ShellFixture()
        func surfaces(_ text: String) -> [SurfaceIR] {
            [T.surface("panel", "bar", children: [.each(EachIR(key: "0", variable: "item", list: IR.value("{var.items}"), body: [
                T.text("0", IR.value(text, locals: ["item"])),
            ]))])]
        }
        fixture.apply(surfaces("{item}"), vars: Self.vars)
        let old = fixture.surface("bar").root
        fixture.apply(surfaces("{item}!"), vars: Self.vars)
        let root = fixture.surface("bar").root
        #expect(ShellRuntime.same(root, old))
        #expect(root.map { $0.arguments[0].value } == [.string("a!"), .string("b!")])
    }

    @Test("Geänderter define-Rumpf gleicht Laufzeit-use ab, Instanz bleibt")
    func defineBodyChanged() {
        let fixture = ShellFixture()
        func define(_ text: String) -> DefineIR {
            DefineIR(name: "card", parameters: [ParameterIR(name: "title")], body: [T.text("0", IR.value(text, locals: ["title"]))], span: IR.span(40))
        }
        let surfaces = [T.surface("panel", "bar", children: [.dynamicUse(DynamicUseIR(key: "0", name: IR.string("card"), arguments: ["title": IR.string("T")]))])]
        fixture.apply(surfaces, defines: [define("{title}")])
        let old = fixture.surface("bar").root[0]
        fixture.apply(surfaces, defines: [define("{title}!")])
        #expect(fixture.surface("bar").root[0] === old)
        #expect(old.arguments[0].value == .string("T!"))
    }
}

extension ElementInstance {
    func instance<V>(ir path: KeyPath<ElementIR, V>) -> V {
        ir[keyPath: path]
    }
}
