import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

struct StubFilterServices: FilterServices {
    func appSearch(_ apps: [Value], query: String) -> [Value] { [] }
    func monthGrid(_ date: Date, offset: Int, firstWeekday: String) -> Value { .null }
    func uptimeText(_ seconds: Double) -> String { "" }
    func normalizedURL(_ text: String) -> String? { nil }
    func symbolExists(_ name: String) -> Bool { false }
    func chordDisplay(_ chord: String) -> String { chord }
    func hotkeyWarning(_ chord: String) -> String? { nil }
    func temperatureText(_ celsius: Double) -> String { "" }
}

enum BindingTestHarness {
    static func evaluator(warn: @escaping @Sendable (Diagnostic) -> Void = { _ in }) -> Evaluator {
        let context = FilterContext(
            now: Date(timeIntervalSince1970: 1_790_236_800),
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "Europe/Zurich")!,
            services: StubFilterServices()
        )
        return Evaluator(filters: .builtin, context: { context }, warn: warn)
    }

    static func source(_ text: String, locals: Set<String> = []) -> BindingSource {
        let template = try! ExpressionParser.parseTemplate(text, span: .synthetic("test")).get()
        return BindingSource(template: template, localNames: locals, span: .synthetic("test"))
    }
}
