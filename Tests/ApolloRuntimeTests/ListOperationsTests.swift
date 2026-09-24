import Testing
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@Suite("ListOperations")
struct ListOperationsTests {
    func record(_ id: String) -> Value {
        .record(Record([("id", .string(id))]))
    }

    func list(_ ids: [String]) -> Value {
        .list(ids.map(record))
    }

    func ids(_ value: Value) -> [String] {
        guard case .list(let items) = value else { return [] }
        return items.map { item -> String in
            guard case .record(let record) = item, case .string(let id)? = record["id"] else { return "" }
            return id
        }
    }

    @Test("insert hängt ohne at hinten an")
    func insertAppendsWithoutAt() {
        let result = ListOperations.apply(.insert(item: record("d"), at: nil, idFrom: nil), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "b", "c", "d"])
    }

    @Test("insert an einem Index schiebt die Folgenden nach hinten")
    func insertAtIndex() {
        let result = ListOperations.apply(.insert(item: record("x"), at: 1, idFrom: nil), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "x", "b", "c"])
    }

    @Test("insert ausserhalb des Bereichs ist eine Diagnose ohne Änderung")
    func insertOutOfRangeFails() {
        let result = ListOperations.apply(.insert(item: record("x"), at: 5, idFrom: nil), to: list(["a", "b", "c"]))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("id-from vergibt den Basiswert, wenn frei")
    func idFromUsesBaseWhenFree() {
        let item = Value.record(Record([("title", .string("clock"))]))
        let result = ListOperations.apply(.insert(item: item, at: nil, idFrom: "title"), to: .list([]))
        let value = try! result.get()
        #expect(ids(value) == ["clock"])
    }

    @Test("id-from wie BlockList.uniqueID: clock, clock-2, clock-3")
    func idFromFollowsBlockListUniqueID() {
        let base = Value.list([record("clock"), record("clock-2")])
        let item = Value.record(Record([("title", .string("clock"))]))
        let result = ListOperations.apply(.insert(item: item, at: nil, idFrom: "title"), to: base)
        #expect(ids(try! result.get()) == ["clock", "clock-2", "clock-3"])
    }

    @Test("id-from ohne Record-Item ist eine Diagnose")
    func idFromRequiresRecordItem() {
        let result = ListOperations.apply(.insert(item: .string("x"), at: nil, idFrom: "title"), to: .list([]))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("remove per at entfernt den Eintrag")
    func removeAtIndex() {
        let result = ListOperations.apply(.remove(at: .index(1)), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "c"])
    }

    @Test("remove per key entfernt den Eintrag mit passendem id")
    func removeByKey() {
        let result = ListOperations.apply(.remove(at: .entry("b")), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "c"])
    }

    @Test("remove mit unbekanntem Schlüssel ist eine Diagnose ohne Änderung")
    func removeUnknownKeyFails() {
        let result = ListOperations.apply(.remove(at: .entry("z")), to: list(["a", "b", "c"]))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("move: to gleich Länge verschiebt ans Ende")
    func moveToEndOfList() {
        let result = ListOperations.apply(.move(from: .index(0), to: 3), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["b", "c", "a"])
    }

    @Test("move: to gleich from ist ein No-op")
    func moveToSameIndexIsNoOp() {
        let result = ListOperations.apply(.move(from: .index(1), to: 1), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "b", "c"])
    }

    @Test("move: to gleich from+1 ist ein No-op")
    func moveToFromPlusOneIsNoOp() {
        let result = ListOperations.apply(.move(from: .index(1), to: 2), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["a", "b", "c"])
    }

    @Test("move per key verschiebt anhand des id")
    func moveByKey() {
        let result = ListOperations.apply(.move(from: .entry("c"), to: 0), to: list(["a", "b", "c"]))
        #expect(ids(try! result.get()) == ["c", "a", "b"])
    }

    @Test("negative Indizes sind ein Fehler, kein Zählen von hinten")
    func negativeIndexIsAnError() {
        let result = ListOperations.apply(.remove(at: .index(-1)), to: list(["a", "b", "c"]))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("update mischt Felder in den Record am Index")
    func updateMergesFieldsAtIndex() {
        let value = Value.list([.record(Record([("id", .string("a")), ("count", .number(1))]))])
        let result = ListOperations.apply(.update(at: .index(0), fields: Record([("count", .number(2))])), to: value)
        guard case .list(let items) = try! result.get(), case .record(let record) = items[0] else {
            Issue.record("expected updated record")
            return
        }
        #expect(record["count"] == .number(2))
        #expect(record["id"] == .string("a"))
    }

    @Test("update auf einem Nicht-Record ist eine Diagnose")
    func updateOnNonRecordFails() {
        let result = ListOperations.apply(.update(at: .index(0), fields: Record()), to: .list([.string("a")]))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("falscher Typ statt Liste ist eine Diagnose ohne Absturz")
    func wrongTypeInsteadOfListFails() {
        let result = ListOperations.apply(.remove(at: .index(0)), to: .string("not a list"))
        #expect(throws: (any Error).self) { try result.get() }
    }

    @Test("riesige Liste stürzt nicht ab")
    func hugeListDoesNotCrash() {
        let huge = Value.list((0..<50_000).map { .number(Double($0)) })
        let result = ListOperations.apply(.remove(at: .index(49_999)), to: huge)
        guard case .list(let items) = try! result.get() else {
            Issue.record("expected list")
            return
        }
        #expect(items.count == 49_999)
    }

    @Test("in= mit Index wirkt auf das Feld eines Eintrags")
    func locatorByIndexOperatesOnField() {
        let entry = Value.record(Record([("id", .string("page")), ("widgets", list(["a", "b"]))]))
        let base = Value.list([entry])
        let locator = ListLocator(entry: .index(0), field: "widgets")
        let result = ListOperations.apply(.insert(item: record("c"), at: nil, idFrom: nil), to: base, locator: locator)
        guard case .list(let items) = try! result.get(), case .record(let record) = items[0], case .list(let widgets)? = record["widgets"] else {
            Issue.record("expected nested widgets list")
            return
        }
        #expect(ids(.list(widgets)) == ["a", "b", "c"])
    }

    @Test("in= mit Schlüssel wirkt auf das Feld des passenden Eintrags")
    func locatorByKeyOperatesOnField() {
        let pageA = Value.record(Record([("id", .string("a")), ("widgets", list(["x"]))]))
        let pageB = Value.record(Record([("id", .string("b")), ("widgets", list(["y"]))]))
        let base = Value.list([pageA, pageB])
        let locator = ListLocator(entry: .entry("b"), field: "widgets")
        let result = ListOperations.apply(.remove(at: .index(0)), to: base, locator: locator)
        guard case .list(let items) = try! result.get() else {
            Issue.record("expected list")
            return
        }
        guard case .record(let recordA) = items[0], case .list(let widgetsA)? = recordA["widgets"] else {
            Issue.record("expected widgets a")
            return
        }
        guard case .record(let recordB) = items[1], case .list(let widgetsB)? = recordB["widgets"] else {
            Issue.record("expected widgets b")
            return
        }
        #expect(ids(.list(widgetsA)) == ["x"])
        #expect(widgetsB.isEmpty)
    }

    @Test("swap in derselben Liste tauscht zwei Einträge")
    func swapWithinSameList() {
        let result = ListOperations.swap(list(["a", "b", "c"]), .index(0), .index(2))
        #expect(ids(try! result.get()) == ["c", "b", "a"])
    }

    @Test("swap über zwei Listen tauscht Einträge zwischen ihnen")
    func swapAcrossTwoLists() {
        let result = ListOperations.swap(list(["a", "b"]), .index(0), list(["x", "y"]), .index(1))
        let (a, b) = try! result.get()
        #expect(ids(a) == ["y", "b"])
        #expect(ids(b) == ["x", "a"])
    }

    @Test("move-to verschiebt einen Eintrag aus einer Liste in eine andere")
    func moveToAcrossLists() {
        let result = ListOperations.moveTo(from: list(["a", "b"]), at: .index(0), to: list(["x", "y"]), index: 1)
        let (source, destination) = try! result.get()
        #expect(ids(source) == ["b"])
        #expect(ids(destination) == ["x", "a", "y"])
    }

    @Test("move-to mit ungültigem Ziel ist eine Diagnose")
    func moveToInvalidDestinationFails() {
        let result = ListOperations.moveTo(from: list(["a"]), at: .index(0), to: list(["x"]), index: 5)
        #expect(throws: (any Error).self) { try result.get() }
    }
}
