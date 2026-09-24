import Testing
import Foundation
@testable import ApolloConfig

@Suite("Werte")
struct ValueTests {
    @Test("Wahrheitswerte nach config-language 4.3", arguments: [
        (Value.null, false),
        (Value.bool(false), false),
        (Value.bool(true), true),
        (Value.number(0), false),
        (Value.number(-0.0), false),
        (Value.number(0.1), true),
        (Value.string(""), false),
        (Value.string("0"), true),
        (Value.list([]), false),
        (Value.list([.null]), true),
        (Value.record(Record()), true),
        (Value.date(Date(timeIntervalSince1970: 0)), true),
        (Value.image(ImageRef(source: "app", id: "com.apple.Safari")), true),
    ])
    func truthiness(value: Value, expected: Bool) {
        #expect(value.isTruthy == expected)
    }

    @Test("Typnamen", arguments: [
        (Value.null, "null"),
        (Value.bool(true), "bool"),
        (Value.number(1), "number"),
        (Value.string("a"), "string"),
        (Value.list([]), "list"),
        (Value.record(Record()), "record"),
        (Value.date(Date(timeIntervalSince1970: 0)), "date"),
        (Value.image(ImageRef(source: "app", id: "x")), "image"),
    ])
    func typeNames(value: Value, expected: String) {
        #expect(value.typeName == expected)
    }

    @Test("Record behält die Reihenfolge der Schlüssel, Überschreiben lässt die Stelle stehen")
    func recordOrder() {
        var record = Record([("b", .number(1)), ("a", .number(2)), ("b", .number(3))])
        #expect(record.keys == ["b", "a"])
        #expect(record["b"] == Value.number(3))
        record["c"] = Value.null
        #expect(record.keys == ["b", "a", "c"])
        #expect(record["c"] == Value.null)
        record["b"] = nil
        #expect(record.keys == ["a", "c"])
        #expect(record.count == 2)
        #expect(record.values == [.number(2), .null])
        #expect(record["missing"] == nil)
    }

    @Test("Tiefe Gleichheit: Records ohne Rücksicht auf die Reihenfolge, Listen elementweise, Typen streng")
    func deepEquality() {
        let left = Value.record(Record([
            ("x", .number(1)),
            ("inner", .list([.record(Record([("a", .bool(true)), ("b", .null)]))])),
        ]))
        let right = Value.record(Record([
            ("inner", .list([.record(Record([("b", .null), ("a", .bool(true))]))])),
            ("x", .number(1)),
        ]))
        #expect(left == right)
        #expect(left.hashValue == right.hashValue)
        #expect(Value.list([.number(1), .number(2)]) != Value.list([.number(2), .number(1)]))
        #expect(Value.number(1) != Value.string("1"))
        #expect(Value.null == Value.null)
        #expect(Value.record(Record([("a", .number(1))])) != Value.record(Record([("a", .number(1)), ("b", .null)])))
    }

    @Test("Umwandlung in Text wie der Filter string", arguments: [
        (Value.null, ""),
        (Value.bool(true), "true"),
        (Value.number(3), "3"),
        (Value.number(-0.0), "0"),
        (Value.number(2.5), "2.5"),
        (Value.string("ä \"x\""), "ä \"x\""),
        (Value.list([.number(1), .string("a\"b"), .null]), "[1,\"a\\\"b\",null]"),
        (Value.record(Record([("b", .number(1)), ("a", .list([]))])), "{\"b\":1,\"a\":[]}"),
        (Value.date(Date(timeIntervalSince1970: 1_790_236_800)), "2026-09-24T08:00:00Z"),
        (Value.image(ImageRef(source: "app", id: "x")), ""),
        (Value.list([.string("tab\there\n")]), "[\"tab\\there\\n\"]"),
    ])
    func stringified(value: Value, expected: String) {
        #expect(value.stringified == expected)
    }
}
