import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Theme in canonical form")
struct ThemeCanonicalTests {
    private func theme(_ css: String) -> Theme {
        Theme.make(identifier: "test", styleSheet: ThemeStyleSheetParser.parse(css))
    }

    private func canonical(_ css: String) -> String? {
        try? ThemeCanonical.css(for: theme(css)).get()
    }

    @Test("keeps known tokens in catalogue order and drops everything else")
    func keepsOnlyKnownTokens() throws {
        let css = try #require(canonical("""
        @import url("https://example.com/x.css");
        :root {
          --apollo-corner-radius: 14px;
          --apollo-accent-color: #FF8A3D;
          --apollo-made-up: 3;
          color: red;
        }
        body { background: url(x.png); }
        """))
        #expect(css == """
        :root {
          --apollo-accent-color: #ff8a3d;
          --apollo-corner-radius: 14px;
        }

        """)
    }

    @Test("writes only what dark mode changes into the media block")
    func darkOverridesOnly() throws {
        let css = try #require(canonical("""
        :root { --apollo-accent-color: #112233; --apollo-corner-radius: 10px; }
        @media (prefers-color-scheme: dark) {
          :root { --apollo-accent-color: #445566; --apollo-corner-radius: 10px; }
        }
        """))
        #expect(css.contains("@media (prefers-color-scheme: dark) {\n  :root {\n    --apollo-accent-color: #445566;\n  }\n}"))
        #expect(css.components(separatedBy: "--apollo-corner-radius").count == 2)
    }

    @Test("drops the author, the homepage and the format")
    func dropsAccountTokens() throws {
        let css = try #require(canonical("""
        :root {
          --apollo-theme-name: "Dusk";
          --apollo-theme-author: "Someone else";
          --apollo-theme-homepage: "https://spam.example";
          --apollo-theme-format: 1;
        }
        """))
        #expect(css == ":root {\n  --apollo-theme-name: \"Dusk\";\n}\n")
    }

    @Test("text loses quotes, backslashes and line breaks")
    func cleansText() {
        #expect(ThemeCanonical.cleanText("a\"b\\c\nd") == "abcd")
        #expect(canonical(#":root { --apollo-theme-name: "Say \"hi\""; }"#)
            == ":root {\n  --apollo-theme-name: \"Say hi\";\n}\n")
    }

    @Test("a theme with files is refused, one without tokens too")
    func refusals() {
        // A folder theme: its files resolve.
        let withFile = Theme.make(identifier: "test",
                                  styleSheet: ThemeStyleSheetParser.parse(#":root { --apollo-theme-author-image: url("me.png"); }"#),
                                  assets: ThemeAssetResolver { _ in .success(URL(fileURLWithPath: "/tmp/me.png")) })
        #expect(ThemeCanonical.css(for: withFile) == .failure(.usesFiles(["--apollo-theme-author-image"])))
        #expect(ThemeCanonical.css(for: theme(":root { color: red; }")) == .failure(.noTokens))
    }

    @Test("the canonical form reads back to the same values")
    func roundTrip() throws {
        let original = theme("""
        :root {
          --apollo-accent-color: #ff8a3d80;
          --apollo-bar-gradient: linear-gradient(180deg, #ffffff 0%, #e8ecf8 100%);
          --apollo-theme-appearance: dark;
        }
        @media (prefers-color-scheme: dark) { :root { --apollo-accent-color: #000000; } }
        """)
        let css = try ThemeCanonical.css(for: original).get()
        let again = theme(css)
        #expect(again.lightValues == original.lightValues)
        #expect(again.darkValues == original.darkValues)
        #expect(try ThemeCanonical.css(for: again).get() == css)
    }

    @Test("the manifest lists every token with its kind")
    func manifest() throws {
        let data = try ThemeTokenManifest.json()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tokens = try #require(object["tokens"] as? [[String: Any]])
        #expect(tokens.count == ThemeTokenCatalog.standard.tokens.count)
        let radius = try #require(tokens.first { $0["name"] as? String == "--apollo-corner-radius" })
        #expect(radius["kind"] as? String == "number")
        #expect(radius["unit"] as? String == "points")
    }
}
