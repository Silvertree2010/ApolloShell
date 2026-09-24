import Testing
import ApolloBase
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("theme-preview: Cache ohne Hash über das ganze CSS, reicht für eine Marketplace-Seite")
struct PreviewCacheTests {
    static func record(_ slug: String, css: String, version: Int = 1) -> Value {
        .record(Record([("slug", .string(slug)), ("version", .number(Double(version))), ("css", .string(css))]))
    }

    @Test("40 Karten zweimal gezeichnet: jedes Theme wird nur einmal geparst")
    func pageFits() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { text \"x\" }", css: "")
        let context = session.context
        let cards = (0..<40).map { Self.record("t\($0)", css: ":root { --apollo-theme-format: 1; --apollo-theme-name: \"T\($0)\"; }") }
        for _ in 0..<2 { for card in cards { _ = context.previewTheme(card) } }
        #expect(context.previewParses == 40)
    }

    @Test("Gleicher Slug, gleiche Länge, anderes CSS: neu geparst")
    func contentChangeRebuilds() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { text \"x\" }", css: "")
        let context = session.context
        let first = context.previewTheme(Self.record("a", css: ":root { --apollo-theme-name: \"AAAA\"; }"))
        let second = context.previewTheme(Self.record("a", css: ":root { --apollo-theme-name: \"BBBB\"; }"))
        #expect(context.previewParses == 2)
        #expect(first != second)
    }
}
