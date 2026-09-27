import Testing
import Foundation
import AppKit
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Render: riesige Zahlen in Zähl-Eigenschaften", .serialized)
struct HugeCountRenderTests {
    func panel(_ child: String) throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(child)\n}", css: "#t { width: 120px; height: 60px; }\n.d { width: 40px; height: 40px; color: #ff0000; }\n")
    }

    @Test("gauge ticks, graph capacity, grid columns, text lines, scallop count mit 1e20 rendern ohne Absturz")
    func hugeCounts() throws {
        _ = try panel("gauge class=\"d\" value=0.5 ticks=1e20")
        _ = try panel("graph class=\"d\" kind=\"line\" capacity=1e20 values=\"{[1, 0.5]}\"")
        _ = try panel("grid columns=1e20 { text \"a\" }")
        _ = try panel("text \"a\" lines=1e20")
        _ = try panel("shape \"scallop\" class=\"d\" count=1e20")
    }

    @Test("Zahl als Text: riesige und unendliche Zahlen stürzen nicht ab")
    func plainText() {
        #expect(Value.number(1e20).plainText == "1e+20")
        #expect(Value.number(.infinity).plainText == "inf")
        #expect(Value.number(42).plainText == "42")
    }
}
