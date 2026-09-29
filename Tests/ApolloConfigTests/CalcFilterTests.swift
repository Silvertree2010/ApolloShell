import Testing
import Foundation
@testable import ApolloConfig

@Suite("Filter calc")
struct CalcFilterTests {
    static let cases: [FilterCase] = [
        .ok("calc", .string("2*(3+4)"), [], .string("14")),
        .ok("calc", .string("1/3"), [], .string("0.3333333333")),
        .ok("calc", .string("2^3^2"), [], .string("512")),
        .ok("calc", .string("50%"), [], .string("0.5")),
        .ok("calc", .string("3 × 4 ÷ 2 − 1"), [], .string("5")),
        .ok("calc", .string("sqrt(16) + abs(-2)"), [], .string("6")),
        .ok("calc", .string("1,5 + 1"), [], .string("2.5")),
        .ok("calc", .string("2*("), [], .null),
        .ok("calc", .string("1/0"), [], .null),
        .ok("calc", .string(""), [], .null),
        .ok("calc", .number(7), [], .string("7")),
        .ok("calc", .null, [], .null),
        .ok("calc", .string(String(repeating: "(", count: 600) + "1"), [], .null),
        .fails("calc", .list([]), []),
    ]

    @Test("rechnet wie der Launcher-Rechner des alten 0.2, unfertig ergibt null", arguments: CalcFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }
}
