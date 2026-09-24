import Testing
import Foundation
@testable import ApolloConfig

@Suite("Zahlenfilter")
struct NumberFilterTests {
    static let cases: [FilterCase] = [
        .ok("round", .number(3.14159), [], .number(3)),
        .ok("round", .number(3.14159), [.number(2)], .number(3.14)),
        .ok("round", .number(2.5), [], .number(3)),
        .ok("round", .number(-2.5), [], .number(-3)),
        .ok("round", .number(-0.2), [], .number(0)),
        .ok("round", .null, [], .null),
        .ok("round", .number(1), [.null], .number(1)),
        .fails("round", .string("a"), []),
        .fails("round", .number(1), [.number(1.5)]),
        .fails("round", .number(1), [.number(16)]),
        .fails("round", .number(1), [.number(1), .number(2)]),
        .fails("round", .number(1), [.string("x")]),
        .ok("floor", .number(2.7), [], .number(2)),
        .ok("floor", .number(-2.2), [], .number(-3)),
        .fails("floor", .string("a"), []),
        .ok("ceil", .number(2.1), [], .number(3)),
        .fails("ceil", .bool(true), []),
        .ok("abs", .number(-4), [], .number(4)),
        .fails("abs", .list([.number(1)]), []),
        .fails("abs", .number(1), [.number(1)]),
        .ok("fixed", .number(3.14159), [.number(2)], .string("3.14")),
        .ok("fixed", .number(2), [.number(1)], .string("2.0")),
        .ok("fixed", .number(-0.04), [.number(1)], .string("0.0")),
        .ok("fixed", .number(0.05), [.number(1)], .string("0.1")),
        .ok("fixed", .number(1234.5), [.number(0)], .string("1235")),
        .fails("fixed", .number(1), []),
        .fails("fixed", .number(1), [.number(-1)]),
        .fails("fixed", .string("1"), [.number(1)]),
        .ok("clamp", .number(12), [.number(0), .number(9)], .number(9)),
        .ok("clamp", .number(-1), [.number(0), .number(9)], .number(0)),
        .ok("clamp", .number(5), [.number(0), .number(9)], .number(5)),
        .fails("clamp", .number(1), [.number(9), .number(0)]),
        .fails("clamp", .number(1), [.number(0)]),
        .fails("clamp", .number(1), [.number(0), .string("9")]),
        .ok("min", .number(5), [.number(3)], .number(3)),
        .ok("max", .number(5), [.number(3)], .number(5)),
        .fails("min", .string("a"), [.number(1)]),
        .fails("max", .number(1), [.string("b")]),
        .ok("scale", .number(5), [.number(0), .number(10), .number(0), .number(100)], .number(50)),
        .ok("scale", .number(0.5), [.number(0), .number(1), .number(100), .number(200)], .number(150)),
        .ok("scale", .number(2), [.number(0), .number(1), .number(0), .number(10)], .number(20)),
        .fails("scale", .number(1), [.number(0), .number(0), .number(0), .number(1)]),
        .fails("scale", .number(1), [.number(0), .number(1), .number(2)]),
        .ok("percent", .number(0.42), [], .string("42%")),
        .ok("percent", .number(0.4256), [.number(1)], .string("42.6%")),
        .ok("percent", .number(1), [], .string("100%")),
        .ok("percent", .number(0.29), [], .string("29%")),
        .fails("percent", .string("x"), []),
        .fails("percent", .number(0.5), [.number(-1)]),
        .ok("grouped", .number(1_234_567), [], .string("1,234,567")),
        .ok("grouped", .number(1234.5), [.number(1)], .string("1,234.5")),
        .ok("grouped", .number(12), [], .string("12")),
        .fails("grouped", .list([]), []),
        .fails("grouped", .number(1), [.string("2")]),
    ]

    @Test("jeder Zahlenfilter mit gültigen und ungültigen Eingaben", arguments: NumberFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("grouped folgt der Locale, fixed und percent nicht")
    func locale() {
        var context = FilterHarness.context
        context.locale = Locale(identifier: "de_DE")
        FilterHarness.check(.ok("grouped", .number(1_234_567), [], .string("1.234.567")), context: context)
        FilterHarness.check(.ok("grouped", .number(1234.5), [.number(1)], .string("1.234,5")), context: context)
        FilterHarness.check(.ok("fixed", .number(2.5), [.number(1)], .string("2.5")), context: context)
        FilterHarness.check(.ok("percent", .number(0.4256), [.number(1)], .string("42.6%")), context: context)
    }

    @Test("riesige Zahlen stürzen nicht ab")
    func hugeNumbers() {
        FilterHarness.check(.ok("round", .number(1e300), [.number(15)], .number(1e300)))
        FilterHarness.check(.ok("clamp", .number(1e300), [.number(0), .number(9)], .number(9)))
    }
}
