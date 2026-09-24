import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloStyle
@testable import ApolloRuntime

@MainActor
struct EachFixture {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    let shell = ShellFixture()

    init(body: [ChildIR]? = nil, indexVariable: String? = nil, itemKey: CompiledValue? = nil, items: [Value] = []) {
        let each = EachIR(key: "0", variable: "item", indexVariable: indexVariable, list: IR.value("{data.items}", line: 20), itemKey: itemKey, body: body ?? [T.text("0", IR.value("{item.name}", locals: ["item"]))])
        shell.store.set(DependencyPath("data", ["items"]), .list(items))
        shell.apply([T.surface("panel", "list", children: [.each(each)])])
        shell.flush()
    }

    static func item(_ id: String, _ name: String? = nil) -> Value {
        .record(Record([("id", .string(id)), ("name", .string(name ?? id.uppercased()))]))
    }

    static func items(_ ids: String...) -> [Value] {
        ids.map { item($0) }
    }

    func set(_ items: [Value]) {
        shell.store.set(DependencyPath("data", ["items"]), .list(items))
        shell.flush()
    }

    var entries: [ElementInstance] {
        shell.surface("list").root
    }

    var texts: [Value] {
        entries.map { $0.arguments.first?.value ?? .null }
    }

    var byKey: [String: ElementInstance] {
        var result: [String: ElementInstance] = [:]
        for entry in entries {
            result[entry.identity.components[2]] = entry
        }
        return result
    }

    var evaluations: Int {
        shell.bindings.evaluationCount
    }
}

@MainActor
@Suite("each Schlüssel-Diff")
struct EachDiffTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR
    typealias F = EachFixture

    @Test("Einfügen vorn, mittig, hinten, Entfernen, Verschieben, Umkehren behalten die Instanzen der übrigen", arguments: [
        ["x", "a", "b", "c", "d"],
        ["a", "b", "x", "c", "d"],
        ["a", "b", "c", "d", "x"],
        ["a", "c", "d"],
        ["d", "a", "b", "c"],
        ["b", "c", "a", "d"],
        ["d", "c", "b", "a"],
        [],
    ])
    func keepsIdentity(_ next: [String]) {
        let fixture = F(items: F.items("a", "b", "c", "d"))
        let before = fixture.byKey
        let builtBefore = fixture.shell.runtime.stats.elementsBuilt
        fixture.set(next.map { F.item($0) })
        #expect(fixture.texts == next.map { .string($0.uppercased()) })
        let after = fixture.byKey
        for id in next where id != "x" {
            #expect(after["k:string:\(id)"] === before["k:string:\(id)"])
        }
        let expectedNew = next.contains("x") ? 1 : 0
        #expect(fixture.shell.runtime.stats.elementsBuilt - builtBefore == expectedNew)
    }

    @Test("Pseudo-Zustand und self-Signale bleiben beim Verschieben am Eintrag")
    func pseudoSurvivesMove() {
        let body = [T.text("0", IR.value("{self.hover ? 'hot' : item.name}", locals: ["item"]))]
        let fixture = F(body: body, items: F.items("a", "b", "c"))
        fixture.byKey["k:string:b"]?.pseudo = [.hover]
        fixture.shell.flush()
        #expect(fixture.texts == [.string("A"), .string("hot"), .string("C")])
        fixture.set(F.items("x", "c", "b", "a"))
        #expect(fixture.texts == [.string("X"), .string("C"), .string("hot"), .string("A")])
        #expect(fixture.byKey["k:string:b"]?.pseudo == [.hover])
    }

    @Test("Gleicher Schlüssel mit neuem Wert wertet nur die Bindings seines Teilbaums aus")
    func changedValueEvaluatesOnlyItsSubtree() {
        let body = [
            T.text("0", IR.value("{item.name}", locals: ["item"])),
            T.text("1", IR.value("n-{item.id}", locals: ["item"])),
        ]
        let fixture = F(body: body, items: F.items("a", "b", "c"))
        let before = fixture.byKey
        let evaluations = fixture.evaluations
        fixture.set([F.item("a"), F.item("b", "Bee"), F.item("c")])
        #expect(fixture.evaluations - evaluations == 3)
        #expect(fixture.byKey["k:string:b"] === before["k:string:b"])
        #expect(fixture.texts == [.string("A"), .string("n-a"), .string("Bee"), .string("n-b"), .string("C"), .string("n-c")])
    }

    @Test("Mit index= wertet Einfügen vorn alle Index-Bindings aus, ohne index= nur den neuen Eintrag")
    func indexBindings() {
        let indexed = F(body: [
            T.text("0", IR.value("{i}", locals: ["i"])),
            T.text("1", IR.value("{item.name}", locals: ["item"])),
        ], indexVariable: "i", items: F.items("a", "b", "c", "d"))
        var evaluations = indexed.evaluations
        indexed.set(F.items("x", "a", "b", "c", "d"))
        #expect(indexed.evaluations - evaluations == 1 + 2 + 4)
        #expect(indexed.texts.enumerated().filter { $0.offset % 2 == 0 }.map(\.element) == (0..<5).map { .number(Double($0)) })

        let plain = F(items: F.items("a", "b", "c", "d"))
        evaluations = plain.evaluations
        plain.set(F.items("x", "a", "b", "c", "d"))
        #expect(plain.evaluations - evaluations == 1 + 1)
    }

    @Test("Doppelte Schlüssel: erstes Vorkommen behält ihn, spätere bekommen #2, eine Warnung")
    func duplicateKeys() {
        let fixture = F(items: [F.item("a", "first"), F.item("a", "second"), F.item("b"), F.item("a", "third")])
        #expect(fixture.entries.map { $0.identity.components[2] } == ["k:string:a", "k:string:a#2", "k:string:b", "k:string:a#3"])
        #expect(fixture.texts == [.string("first"), .string("second"), .string("B"), .string("third")])
        #expect(fixture.shell.warnings.filter { $0.message.contains("duplicate keys") }.count == 1)
        let second = fixture.byKey["k:string:a#2"]
        fixture.set([F.item("b"), F.item("a", "first"), F.item("a", "second")])
        #expect(fixture.byKey["k:string:a#2"] === second)
        #expect(fixture.shell.warnings.filter { $0.message.contains("duplicate keys") }.count == 1)
    }

    @Test("Schlüssel sind typisiert: 1 und \"1\" sind verschiedene Einträge")
    func typedKeys() {
        let fixture = F(body: [T.text("0", IR.value("{item}", locals: ["item"]))], itemKey: IR.value("{item}", locals: ["item"]), items: [.number(1), .string("1")])
        #expect(fixture.entries.map { $0.identity.components[2] } == ["k:number:1", "k:string:1"])
        let number = fixture.byKey["k:number:1"]
        let text = fixture.byKey["k:string:1"]
        fixture.set([.string("1"), .number(1)])
        #expect(fixture.byKey["k:number:1"] === number)
        #expect(fixture.byKey["k:string:1"] === text)
        #expect(fixture.shell.warnings.isEmpty)
    }

    @Test("Schlüssel null und fehlerhafter Schlüssel-Ausdruck fallen auf den Index zurück, mit Warnung")
    func nullAndFailingKeys() {
        let nullKey = F(itemKey: IR.value("{item.missing}", locals: ["item"]), items: F.items("a", "b"))
        #expect(nullKey.entries.map { $0.identity.components[2] } == ["i:0", "i:1"])
        #expect(nullKey.shell.warnings.filter { $0.message.contains("key is null") }.count == 1)

        let failing = F(itemKey: IR.value("{item.name | nosuchfilter}", locals: ["item"]), items: F.items("a", "b"))
        #expect(failing.entries.map { $0.identity.components[2] } == ["i:0", "i:1"])
        #expect(failing.texts == [.string("A"), .string("B")])
        #expect(!failing.shell.warnings.isEmpty)
    }

    @Test("Zwei Einträge tauschen ihre Schlüssel: Instanz folgt dem Schlüssel, Werte sind aktuell")
    func swappedKeys() {
        let fixture = F(items: [F.item("a", "Alpha"), F.item("b", "Beta")])
        let a = fixture.byKey["k:string:a"]
        let b = fixture.byKey["k:string:b"]
        fixture.set([F.item("b", "Alpha"), F.item("a", "Beta")])
        #expect(fixture.entries[0] === b)
        #expect(fixture.entries[1] === a)
        #expect(fixture.texts == [.string("Alpha"), .string("Beta")])
    }

    @Test("Ohne key= und ohne id gilt der Index; keine Liste ergibt keine Kinder mit Warnung")
    func indexFallbackAndNonList() {
        let fixture = F(body: [T.text("0", IR.value("{item}", locals: ["item"]))], items: [.string("p"), .string("q")])
        #expect(fixture.entries.map { $0.identity.components[2] } == ["i:0", "i:1"])
        let first = fixture.entries[0]
        fixture.set([.string("r"), .string("q")])
        #expect(fixture.entries[0] === first)
        #expect(fixture.texts == [.string("r"), .string("q")])
        fixture.shell.store.set(DependencyPath("data", ["items"]), .string("nope"))
        fixture.shell.flush()
        #expect(fixture.entries.isEmpty)
        #expect(fixture.shell.warnings.contains { $0.message.contains("each needs a list") })
    }

    @Test("Abbau von 5 000 Einträgen beendet alle Bindings und Abos")
    func teardownRestoresCounters() {
        let body = [T.text("0", IR.value("{item.name} {theme.accent}", locals: ["item"]))]
        let fixture = F(body: body)
        let subscriptions = fixture.shell.store.subscriptionCount
        let bindings = fixture.shell.bindings.liveBindingCount
        fixture.set((0..<5_000).map { F.item("e\($0)") })
        #expect(fixture.entries.count == 5_000)
        #expect(fixture.shell.store.subscriptionCount == subscriptions + 5_000)
        #expect(fixture.shell.store.demandCount(DependencyPath("theme", ["accent"])) == 5_000)
        fixture.set([])
        #expect(fixture.entries.isEmpty)
        #expect(fixture.shell.store.subscriptionCount == subscriptions)
        #expect(fixture.shell.bindings.liveBindingCount == bindings)
        #expect(fixture.shell.store.demandCount(DependencyPath("theme", ["accent"])) == 0)
    }

    @Test("each in each: neuer Wert des äusseren Eintrags behält die inneren Instanzen und aktualisiert sie")
    func nestedEachKeepsInnerInstances() {
        let inner = EachIR(key: "1", variable: "tag", list: IR.value("{item.tags}", locals: ["item"]), itemKey: IR.value("{tag}", locals: ["tag"]), body: [
            T.text("0", IR.value("{item.name}:{tag}", locals: ["item", "tag"])),
        ])
        let body: [ChildIR] = [T.box("0", children: [.each(inner)])]
        func group(_ name: String, _ tags: [String]) -> Value {
            .record(Record([("id", .string("g")), ("name", .string(name)), ("tags", .list(tags.map { .string($0) }))]))
        }
        let fixture = F(body: body, items: [group("G", ["x", "y"])])
        let box = fixture.entries[0]
        let tags = box.children
        #expect(tags.map { $0.arguments[0].value } == [.string("G:x"), .string("G:y")])
        fixture.set([group("H", ["x", "y"])])
        #expect(fixture.entries[0] === box)
        #expect(box.children.count == 2)
        #expect(box.children[0] === tags[0])
        #expect(box.children[1] === tags[1])
        #expect(box.children.map { $0.arguments[0].value } == [.string("H:x"), .string("H:y")])
        fixture.set([group("H", ["z", "x", "y"])])
        #expect(box.children[1] === tags[0])
        #expect(box.children.map { $0.arguments[0].value } == [.string("H:z"), .string("H:x"), .string("H:y")])
    }

    @Test("Laufzeit-use: neue Argumente behalten die Instanzen des Rumpfs")
    func dynamicUseKeepsInstances() {
        let fixture = ShellFixture()
        let card = DefineIR(name: "card", parameters: [ParameterIR(name: "title")], body: [
            T.text("0", IR.value("{title}", locals: ["title"])),
            T.text("1", IR.string("static")),
        ], span: IR.span(40))
        fixture.apply([T.surface("panel", "side", children: [
            .dynamicUse(DynamicUseIR(key: "0", name: IR.string("card", line: 41), arguments: ["title": IR.value("{var.title}")])),
        ])], vars: [IR.plainVar("title", .string, .string("one"))], defines: [card])
        let root = fixture.surface("side").root
        #expect(root.map { $0.arguments[0].value } == [.string("one"), .string("static")])
        let built = fixture.runtime.stats.elementsBuilt
        fixture.vars.set("title", .string("two"))
        fixture.flush()
        let after = fixture.surface("side").root
        #expect(after[0] === root[0])
        #expect(after[1] === root[1])
        #expect(after[0].arguments[0].value == .string("two"))
        #expect(fixture.runtime.stats.elementsBuilt == built)
    }

    @Test("id-Element wechselt den Eintrag und behält Instanz und Zustand")
    func idElementMovesBetweenEntries() {
        let body = [T.text("0", IR.value("{item.name}", locals: ["item"]), properties: ["id": IR.value("{item.owner}", locals: ["item"])])]
        func entry(_ id: String, owner: String) -> Value {
            .record(Record([("id", .string(id)), ("name", .string(id)), ("owner", .string(owner))]))
        }
        let fixture = F(body: body, items: [entry("a", owner: "focus"), entry("b", owner: "other")])
        let focus = fixture.shell.runtime.element(Identity(["list@A", "#focus"]))
        focus?.pseudo = [.focus]
        fixture.set([entry("c", owner: "focus"), entry("b", owner: "other")])
        let moved = fixture.shell.runtime.element(Identity(["list@A", "#focus"]))
        #expect(moved != nil)
        #expect(moved === focus)
        #expect(moved?.pseudo == [.focus])
        #expect(moved?.arguments[0].value == .string("c"))
        #expect(fixture.entries.count == 2)
    }

    @Test("id-Element tief im Eintrag wandert in einen neuen Eintrag und behält Instanz und Zustand")
    func nestedIDElementMovesBetweenEntries() {
        let body: [ChildIR] = [T.box("0", children: [
            T.text("0", IR.value("{item.name}", locals: ["item"]), properties: ["id": IR.value("{item.owner}", locals: ["item"])]),
        ])]
        func entry(_ id: String, owner: String) -> Value {
            .record(Record([("id", .string(id)), ("name", .string(id)), ("owner", .string(owner))]))
        }
        let fixture = F(body: body, items: [entry("a", owner: "focus"), entry("b", owner: "other")])
        let focus = fixture.shell.runtime.element(Identity(["list@A", "#focus"]))
        focus?.pseudo = [.hover]
        let oldBox = fixture.entries[0]
        fixture.set([entry("b", owner: "other"), entry("c", owner: "focus")])
        let moved = fixture.shell.runtime.element(Identity(["list@A", "#focus"]))
        #expect(moved === focus)
        #expect(moved?.pseudo == [.hover])
        #expect(moved?.arguments[0].value == .string("c"))
        #expect(fixture.entries[1] !== oldBox)
        #expect(fixture.entries[1].children.first === focus)
        #expect(fixture.shell.runtime.element(oldBox.identity) == nil)
        #expect(fixture.shell.runtime.elements.count == 4)
    }
}
