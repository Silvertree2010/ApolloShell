import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Template-Cache pro Ladevorgang")
struct TemplateCacheTests {
    @Test("liefert dasselbe wie der Parser, auch für Fehler, und trennt gleiche Texte an anderen Stellen", arguments: ["{a + 1}", "x {b | upper} y", "{", "{{literal}}", "{a ? 'x' : }"])
    func matchesParser(_ text: String) {
        let cache = TemplateCache()
        let first = SourceSpan(file: "/c/a.kdl", start: SourcePosition(offset: 4, line: 1, column: 5), end: SourcePosition(offset: 4 + text.utf8.count + 2, line: 1, column: 7 + text.count))
        var second = first
        second.file = "/c/b.kdl"
        for span in [first, second, first] {
            #expect(cache.template(text, span: span) == ExpressionParser.parseTemplate(text, span: span))
            #expect(cache.occurrences(in: text, span: span).mapValues { $0.map(\.root) } == NameLocator.occurrences(in: text, span: span).mapValues { $0.map(\.root) })
        }
    }
}
