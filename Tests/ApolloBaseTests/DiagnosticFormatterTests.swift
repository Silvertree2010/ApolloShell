import Testing
@testable import ApolloBase

@Suite("Diagnosen als Text")
struct DiagnosticFormatterTests {
    @Test("Form aus config-language.md 11.2")
    func specExample() {
        let file = "~/.config/apolloshell/sidebar.kdl"
        let source = String(repeating: "\n", count: 13) + "        on-clik { toggle \"session\" }\n"
        let span = SourceSpan(
            file: file,
            start: SourcePosition(offset: 21, line: 14, column: 9),
            end: SourcePosition(offset: 28, line: 14, column: 16)
        )
        let diagnostic = Diagnostic(.error, "unknown property 'on-clik' on 'button'", span: span, help: "did you mean 'on-click'?")
        let expected = """
        ~/.config/apolloshell/sidebar.kdl:14:9: error: unknown property 'on-clik' on 'button'
           14 |         on-clik { toggle "session" }
              |         ^^^^^^^
              = help: did you mean 'on-click'?
        """
        #expect(DiagnosticFormatter.format(diagnostic, sourceText: { $0 == file ? source : nil }) == expected)
    }

    @Test("Tabs werden gespiegelt, ein Emoji ist eine Spalte")
    func tabAndEmoji() {
        let source = "\t\u{1F389} name=1\n"
        let span = SourceSpan(
            file: "a.kdl",
            start: SourcePosition(offset: 6, line: 1, column: 4),
            end: SourcePosition(offset: 10, line: 1, column: 8)
        )
        let text = DiagnosticFormatter.format(Diagnostic(.warning, "odd", span: span), sourceText: { _ in source })
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines == [
            "a.kdl:1:4: warning: odd",
            "    1 | \t\u{1F389} name=1",
            "      | \t  ^^^^",
        ])
    }

    @Test("ohne Ort nur Kopfzeile und Hilfe")
    func withoutSpan() {
        let text = DiagnosticFormatter.format(Diagnostic(.note, "skipped", help: "enable it"), sourceText: { _ in nil })
        #expect(text == "note: skipped\n      = help: enable it")
    }

    @Test("Notizen mit Ort stehen in Klammern")
    func notes() {
        let include = SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 0, line: 3, column: 1),
            end: SourcePosition(offset: 7, line: 3, column: 8)
        )
        let diagnostic = Diagnostic(.error, "bad", notes: [DiagnosticNote("included from here", span: include), DiagnosticNote("plain")])
        let text = DiagnosticFormatter.format(diagnostic, sourceText: { _ in nil })
        #expect(text == "error: bad\n      = note: included from here (shell.kdl:3:1)\n      = note: plain")
    }

    @Test("synthetischer Ort zeigt nur den Dateinamen")
    func syntheticSpan() {
        let text = DiagnosticFormatter.format(Diagnostic(.error, "broken", span: .synthetic()), sourceText: { _ in "x" })
        #expect(text == "<generated>: error: broken")
    }

    @Test("fehlende Quelle: nur Kopfzeile")
    func missingSource() {
        let span = SourceSpan(
            file: "gone.kdl",
            start: SourcePosition(offset: 0, line: 2, column: 5),
            end: SourcePosition(offset: 1, line: 2, column: 6)
        )
        #expect(DiagnosticFormatter.format(Diagnostic(.error, "x", span: span), sourceText: { _ in nil }) == "gone.kdl:2:5: error: x")
    }

    @Test("mehrzeiliger Bereich wird bis zum Zeilenende markiert")
    func multiLineSpan() {
        let span = SourceSpan(
            file: "m.kdl",
            start: SourcePosition(offset: 2, line: 1, column: 3),
            end: SourcePosition(offset: 9, line: 2, column: 2)
        )
        let text = DiagnosticFormatter.format(Diagnostic(.error, "x", span: span), sourceText: { _ in "a bcd\ne\n" })
        #expect(text == "m.kdl:1:3: error: x\n    1 | a bcd\n      |   ^^^")
    }

    @Test("Zeilennummer mit sechs Stellen verbreitert das Feld")
    func wideGutter() {
        let source = String(repeating: "\n", count: 123_455) + "x"
        let span = SourceSpan(
            file: "w.kdl",
            start: SourcePosition(offset: 123_455, line: 123_456, column: 1),
            end: SourcePosition(offset: 123_456, line: 123_456, column: 2)
        )
        let text = DiagnosticFormatter.format(Diagnostic(.error, "x", span: span, help: "h"), sourceText: { _ in source })
        #expect(text == "w.kdl:123456:1: error: x\n123456 | x\n       | ^\n       = help: h")
    }

    @Test("Stufen sind geordnet")
    func severityOrder() {
        #expect(Severity.note < Severity.warning)
        #expect(Severity.warning < Severity.error)
        #expect(Severity.error.label == "error")
    }
}
