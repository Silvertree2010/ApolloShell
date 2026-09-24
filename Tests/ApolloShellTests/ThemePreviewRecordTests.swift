import Testing
import AppKit
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("theme-preview mit Record baut das Theme aus css, geprüft wie installierte (11-12)")
struct ThemePreviewRecordTests {
    static let kdl = """
    panel "t" anchor="left" {
        column {
            each item in="{marketplace.items}" key="{item.id}" {
                theme-preview theme="{item}" appearance="light"
            }
        }
    }
    """

    static func fixture(_ css: String) -> String {
        "fixture {\n    marketplace status=\"loaded\" {\n        items {\n            - id=\"t1\" slug=\"red\" css=\"\(css)\"\n        }\n    }\n}\n"
    }

    static let css = "theme-preview { width: 160px; height: 100px; }"

    static func red(_ pixel: RGBA) -> Bool { pixel.r > 200 && pixel.g < 60 && pixel.b < 60 }

    @Test("Akzent aus dem Record erscheint in der Vorschau, Standard-Theme zeigt ihn nicht")
    func rendersRecordTheme() throws {
        let themed = try RenderProbe.render(Self.kdl, css: Self.css, fixture: Self.fixture(":root { --apollo-accent-color: #ff0000; }"))
        let plain = try RenderProbe.render(Self.kdl, css: Self.css, fixture: Self.fixture(""))
        #expect(themed.count(where: Self.red) > 20)
        #expect(plain.count(where: Self.red) == 0)
    }

    @Test("Record-css durchläuft die Theme-Prüfung: zu grosse Datei fällt auf Standardwerte mit Fund zurück")
    func checked() {
        let limits = ThemeLimits.standard
        let big = ":root { --apollo-accent-color: #ff0000; }" + String(repeating: " ", count: limits.maxStyleSheetBytes)
        let theme = ThemeLoader.load(css: big, identifier: "big")
        #expect(!theme.issues.isEmpty)
        #expect(theme.value("--apollo-accent-color") == nil || theme.value("--apollo-accent-color") == Theme.standard.value("--apollo-accent-color"))
    }
}
