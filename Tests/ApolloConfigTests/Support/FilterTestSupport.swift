import Testing
import Foundation
@testable import ApolloConfig

struct FakeFilterServices: FilterServices {
    func appSearch(_ apps: [Value], query: String) -> [Value] {
        guard !query.isEmpty else { return apps }
        return apps.filter { app in
            guard case .record(let record) = app, case .string(let name)? = record["name"] else { return false }
            return name.lowercased().contains(query.lowercased())
        }
    }

    func monthGrid(_ date: Date, offset: Int, firstWeekday: String) -> Value {
        .string("grid \(offset) \(firstWeekday)")
    }

    func uptimeText(_ seconds: Double) -> String {
        "uptime \(Int(seconds))"
    }

    func normalizedURL(_ text: String) -> String? {
        text.contains(".") ? "https://" + text : nil
    }

    func symbolExists(_ name: String) -> Bool {
        name == "star.fill"
    }

    func chordDisplay(_ chord: String) -> String {
        "display " + chord
    }

    func hotkeyWarning(_ chord: String) -> String? {
        chord == "cmd+space" ? "taken" : nil
    }

    func temperatureText(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }
}

struct FilterCase: Sendable, CustomTestStringConvertible {
    enum Expected: Sendable {
        case value(Value)
        case failure
    }

    let filter: String
    let input: Value
    let arguments: [Value]
    let expected: Expected

    static func ok(_ filter: String, _ input: Value, _ arguments: [Value], _ expected: Value) -> FilterCase {
        FilterCase(filter: filter, input: input, arguments: arguments, expected: .value(expected))
    }

    static func fails(_ filter: String, _ input: Value, _ arguments: [Value]) -> FilterCase {
        FilterCase(filter: filter, input: input, arguments: arguments, expected: .failure)
    }

    var testDescription: String {
        "\(input) | \(filter) \(arguments)"
    }
}

enum FilterHarness {
    static let now = Date(timeIntervalSince1970: 1_790_236_800)

    static let context = FilterContext(
        now: now,
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "Europe/Zurich")!,
        services: FakeFilterServices()
    )

    static func check(_ testCase: FilterCase, context: FilterContext = context) {
        guard let function = FilterTable.builtin.function(named: testCase.filter) else {
            Issue.record("filter '\(testCase.filter)' is missing from FilterTable.builtin")
            return
        }
        let result = function(testCase.input, testCase.arguments, context)
        switch testCase.expected {
        case .value(let expected):
            #expect(result == .value(expected), "\(testCase.testDescription)")
        case .failure:
            if case .value(let value) = result {
                Issue.record("expected a failure for \(testCase.testDescription), got \(value)")
            }
        }
    }
}
