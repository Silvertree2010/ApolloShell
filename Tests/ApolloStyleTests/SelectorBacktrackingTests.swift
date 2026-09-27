import Testing
import Foundation
@testable import ApolloStyle

@Suite("CSS: Selektoren mit vielen * backtracken nicht exponentiell")
struct SelectorBacktrackingTests {
    @Test("16 × * über 40 Vorfahren ohne Treffer bleibt schnell, Treffer bleiben Treffer")
    func manyUniversalDescendants() throws {
        let stars = Array(repeating: "*", count: 16).joined(separator: " ")
        let parsed = SelectorParser.parse(CSSComponentParser.parse(text: ".a \(stars) .b"))
        let selector = try #require(parsed.selectors.first)
        let ancestors = Array(repeating: StyleSubject(kind: "row"), count: 40)
        let subject = StyleSubject(kind: "text", classes: ["b"])
        let start = Date()
        #expect(!selector.matches(subject, ancestors: ancestors))
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(selector.matches(subject, ancestors: [StyleSubject(kind: "row", classes: ["a"])] + ancestors))
        #expect(!selector.matches(subject, ancestors: [StyleSubject(kind: "row", classes: ["a"])] + ancestors.prefix(15)))
        #expect(selector.matches(subject, ancestors: [StyleSubject(kind: "row", classes: ["a"])] + ancestors.prefix(16)))
    }
}
