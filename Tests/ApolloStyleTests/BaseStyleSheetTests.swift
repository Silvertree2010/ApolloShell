import Foundation
import Testing
@testable import ApolloStyle

@Suite("Grundstylesheet")
struct BaseStyleSheetTests {
    @Test("Resources/base.css ist dieselbe Datei wie die Konstante")
    func fileMatchesConstant() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Resources/base.css"), encoding: .utf8)
        #expect(text == BaseStyleSheet.source)
    }

    @Test("Systemschrift 13 pt und Textfarbe label, sonst nichts")
    func contents() {
        let (sheet, diagnostics) = StyleSheet.parse(BaseStyleSheet.source, file: BaseStyleSheet.file, origin: .base)
        #expect(diagnostics.isEmpty)
        #expect(BaseStyleSheet.sheet.origin == .base)
        let style = StyleEngine(sheets: [sheet]).computedStyle(
            for: StyleSubject(kind: "panel"), ancestors: [], parent: nil, inline: [],
            environment: StyleEnvironment(appearance: .dark, reduceMotion: false, reduceTransparency: false, tokens: .empty)).0
        #expect(style["font-family"] == .fontFamilies(["system-ui"]))
        #expect(style["font-size"] == .length(CSSLength(13, .points)))
        #expect(style["color"] == .color(.system(name: "-apple-system-label", alpha: 1)))
        #expect(style["background"] == nil)
        #expect(style["border"] == nil)
        #expect(style["box-shadow"] == nil)
    }
}
