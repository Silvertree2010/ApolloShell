import Testing
import Foundation
import ApolloKDL
@testable import ApolloConfig

@Suite("ValueKDLMapping Rundlauf")
struct ValueKDLMappingTests {
    static func roundtrip(_ value: Value) -> Value {
        ValueKDLMapping.value(from: ValueKDLMapping.node(named: "field", value: value))
    }

    @Test("Skalare ueberleben den Rundlauf")
    func scalarsRoundtrip() {
        #expect(Self.roundtrip(.null) == .null)
        #expect(Self.roundtrip(.bool(true)) == .bool(true))
        #expect(Self.roundtrip(.bool(false)) == .bool(false))
        #expect(Self.roundtrip(.number(46.85)) == .number(46.85))
        #expect(Self.roundtrip(.number(-3)) == .number(-3))
        #expect(Self.roundtrip(.string("Chur")) == .string("Chur"))
        #expect(Self.roundtrip(.string("")) == .string(""))
    }

    @Test("Record ueberlebt den Rundlauf")
    func recordRoundtrips() {
        let record = Value.record(Record([("name", .string("Chur")), ("latitude", .number(46.85)), ("longitude", .number(9.53))]))
        #expect(Self.roundtrip(record) == record)
    }

    @Test("Liste ueberlebt den Rundlauf")
    func listRoundtrips() {
        let list = Value.list([.string("mountain"), .string("resort")])
        #expect(Self.roundtrip(list) == list)
    }

    @Test("Verschachtelte Struktur ueberlebt den Rundlauf")
    func nestedStructureRoundtrips() {
        let nested = Value.list([
            .record(Record([
                ("kind", .string("weather")),
                ("places", .list([
                    .record(Record([("name", .string("Chur")), ("latitude", .number(46.85))])),
                    .record(Record([("name", .string("Bad Ragaz")), ("latitude", .number(47.0))])),
                ])),
            ])),
        ])
        #expect(Self.roundtrip(nested) == nested)
    }

    @Test("Record mit Schluessel '-' wird nicht als Liste missverstanden")
    func recordWithDashKeyIsNotConfusedWithList() {
        let record = Value.record(Record([("-", .string("dash")), ("name", .string("x"))]))
        #expect(Self.roundtrip(record) == record)
    }

    @Test("Leerer Record ueberlebt den Rundlauf")
    func emptyRecordRoundtrips() {
        #expect(Self.roundtrip(.record(Record())) == .record(Record()))
    }

    @Test("Liste mit einem Eintrag ueberlebt den Rundlauf")
    func singleElementListRoundtrips() {
        #expect(Self.roundtrip(.list([.string("mountain")])) == .list([.string("mountain")]))
    }

    @Test("KDL-Knoten fuer Skalar")
    func nodeForScalar() {
        let node = ValueKDLMapping.node(named: "clock-format", value: .string("HH:mm"))
        #expect(node.name == "clock-format")
        #expect(node.arguments.count == 1)
        if case .string(let text) = node.arguments[0].scalar {
            #expect(text == "HH:mm")
        } else {
            Issue.record("expected a string argument")
        }
    }

    @Test("KDL-Knoten fuer Liste nutzt '-' Kinder")
    func nodeForListUsesDashChildren() {
        let node = ValueKDLMapping.node(named: "pinned-toggles", value: .list([.string("keep-awake"), .string("dark-mode")]))
        #expect(node.children?.count == 2)
        #expect(node.children?.allSatisfy { $0.name == "-" } == true)
    }

    @Test("KDL-Knoten fuer Record nutzt Properties")
    func nodeForRecordUsesProperties() {
        let node = ValueKDLMapping.node(named: "location", value: .record(Record([("name", .string("Chur")), ("latitude", .number(46.85))])))
        #expect(node.property("name") != nil)
        #expect(node.property("latitude") != nil)
        #expect(node.children == nil)
    }

    @Test("NaN und unendlich werden beim Lesen zu null")
    func nanAndInfiniteBecomeNull() {
        let node = KDLNode(name: "value", arguments: [KDLValue(.number(.nan, raw: "#nan"))])
        #expect(ValueKDLMapping.value(from: node) == .null)
        let infNode = KDLNode(name: "value", arguments: [KDLValue(.number(.infinity, raw: "#inf"))])
        #expect(ValueKDLMapping.value(from: infNode) == .null)
    }

    @Test("NaN und unendlich werden beim Schreiben nie erzeugt")
    func nanAndInfiniteAreNeverWritten() {
        let node = ValueKDLMapping.node(named: "value", value: .number(.nan))
        if case .null = node.arguments[0].scalar {
        } else {
            Issue.record("expected #null instead of NaN")
        }
    }

    @Test("Zahlen mit Originaltext werden gelesen")
    func numbersWithOriginalTextAreRead() throws {
        let document = try KDLDocument.parse("value 1e3", file: "test.kdl")
        #expect(ValueKDLMapping.value(from: document.nodes[0]) == .number(1000))
        let hex = try KDLDocument.parse("value 0x10", file: "test.kdl")
        #expect(ValueKDLMapping.value(from: hex.nodes[0]) == .number(16))
    }
}
