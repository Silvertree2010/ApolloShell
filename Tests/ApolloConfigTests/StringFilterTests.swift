import Testing
import Foundation
@testable import ApolloConfig

@Suite("Stringfilter")
struct StringFilterTests {
    static let cases: [FilterCase] = [
        .ok("string", .null, [], .string("")),
        .ok("string", .number(3), [], .string("3")),
        .ok("string", .number(2.5), [], .string("2.5")),
        .ok("string", .bool(true), [], .string("true")),
        .ok("string", .list([.number(1), .string("a")]), [], .string("[1,\"a\"]")),
        .ok("string", .record(Record([("a", .number(1))])), [], .string("{\"a\":1}")),
        .fails("string", .number(1), [.number(2)]),
        .ok("upper", .string("abc"), [], .string("ABC")),
        .ok("upper", .string("straße"), [], .string("STRASSE")),
        .ok("upper", .null, [], .null),
        .fails("upper", .list([]), []),
        .ok("lower", .string("ÄB"), [], .string("äb")),
        .fails("lower", .record(Record()), []),
        .ok("capitalize", .string("hello world"), [], .string("Hello world")),
        .ok("capitalize", .string(""), [], .string("")),
        .ok("capitalize", .string("élan"), [], .string("Élan")),
        .fails("capitalize", .date(FilterHarness.now), []),
        .ok("truncate", .string("abcdef"), [.number(3)], .string("abc…")),
        .ok("truncate", .string("abc"), [.number(3)], .string("abc")),
        .ok("truncate", .string("👍🏽ab"), [.number(1)], .string("👍🏽…")),
        .fails("truncate", .string("abc"), [.number(-1)]),
        .fails("truncate", .string("abc"), [.string("x")]),
        .ok("pad", .number(7), [.number(2), .string("0")], .string("07")),
        .ok("pad", .string("ab"), [.number(4)], .string("  ab")),
        .ok("pad", .string("abcdef"), [.number(3)], .string("abcdef")),
        .ok("pad", .string("ä"), [.number(3), .string("·")], .string("··ä")),
        .fails("pad", .string("a"), [.number(3), .string("ab")]),
        .fails("pad", .string("a"), []),
        .ok("replace", .string("a.b.c"), [.string("."), .string(",")], .string("a,b,c")),
        .ok("replace", .number(1.5), [.string("."), .string(",")], .string("1,5")),
        .fails("replace", .string("a"), [.string(""), .string("b")]),
        .fails("replace", .string("a"), [.string("a")]),
        .ok("split", .string("a,b,,c"), [.string(",")], .list([.string("a"), .string("b"), .string(""), .string("c")])),
        .ok("split", .string("abc"), [.string("")], .list([.string("a"), .string("b"), .string("c")])),
        .fails("split", .list([.string("a")]), [.string(",")]),
        .fails("split", .string("a"), [.number(1)]),
        .ok("starts-with", .string("Safari"), [.string("Saf")], .bool(true)),
        .ok("starts-with", .string("Safari"), [.string("saf")], .bool(false)),
        .ok("ends-with", .string("Safari"), [.string("x")], .bool(false)),
        .ok("ends-with", .string("Safari"), [.string("ari")], .bool(true)),
        .fails("starts-with", .list([]), [.string("a")]),
        .fails("ends-with", .string("a"), [.number(1)]),
        .ok("json", .string("{\"b\":1,\"a\":[true,null]}"), [], .record(Record([("a", .list([.bool(true), .null])), ("b", .number(1))]))),
        .ok("json", .string("not json"), [], .null),
        .ok("json", .string("3"), [], .number(3)),
        .ok("json", .string("\"x\""), [], .string("x")),
        .fails("json", .number(5), []),
        .ok("number", .string("12.5"), [], .number(12.5)),
        .ok("number", .string(" 7 "), [], .number(7)),
        .ok("number", .string("abc"), [], .null),
        .ok("number", .string("nan"), [], .null),
        .ok("number", .number(4), [], .number(4)),
        .ok("number", .date(Date(timeIntervalSince1970: 1_790_235_660)), [], .number(1_790_235_660)),
        .fails("number", .list([]), []),
    ]

    @Test("jeder Stringfilter mit gültigen und ungültigen Eingaben", arguments: StringFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("json behält die Schlüssel sortiert und liest Bools nicht als Zahlen")
    func jsonDetails() {
        let parsed = JSONValue.parse("{\"z\":false,\"m\":0,\"a\":{\"n\":1}}")
        guard case .record(let record)? = parsed else {
            Issue.record("expected a record")
            return
        }
        #expect(record.keys == ["a", "m", "z"])
        #expect(record["z"] == Value.bool(false))
        #expect(record["m"] == Value.number(0))
    }
}
