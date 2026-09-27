import Testing
@testable import ApolloBase

@Suite("Quelltext-Positionen")
struct SourceLocatorTests {
    @Test("Zeilen und Spalten in reinem ASCII")
    func ascii() {
        let locator = SourceLocator("ab\ncd")
        #expect(locator.position(atByteOffset: 0) == SourcePosition(offset: 0, line: 1, column: 1))
        #expect(locator.position(atByteOffset: 4) == SourcePosition(offset: 4, line: 2, column: 2))
        #expect(locator.lineCount == 2)
        #expect(locator.lineText(2) == "cd")
        #expect(locator.lineText(3) == nil)
    }

    @Test("Emoji mit ZWJ, Flaggen und Umlaute zählen als ein Zeichen")
    func graphemes() {
        let text = "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} b \u{1F1E8}\u{1F1ED} \u{E4} u\u{308} x"
        let locator = SourceLocator(text)
        #expect(locator.position(atByteOffset: 20).column == 4)
        #expect(locator.position(atByteOffset: 22).column == 6)
        #expect(locator.position(atByteOffset: 31).column == 8)
        #expect(locator.position(atByteOffset: 34).column == 10)
        #expect(locator.position(atByteOffset: 38).column == 12)
    }

    @Test("Tab zählt als ein Zeichen")
    func tab() {
        let locator = SourceLocator("\t\tx")
        #expect(locator.position(atByteOffset: 2).column == 3)
    }

    @Test("CRLF, CR, NEL, LS, PS und FF beenden eine Zeile, VT nicht")
    func lineBreaks() {
        let locator = SourceLocator("a\r\nb\rc\u{85}d\u{2028}e\u{2029}f\u{0C}g\u{0B}h")
        #expect(locator.position(atByteOffset: 3) == SourcePosition(offset: 3, line: 2, column: 1))
        #expect(locator.position(atByteOffset: 5).line == 3)
        #expect(locator.position(atByteOffset: 8).line == 4)
        #expect(locator.position(atByteOffset: 12).line == 5)
        #expect(locator.position(atByteOffset: 16).line == 6)
        #expect(locator.position(atByteOffset: 20) == SourcePosition(offset: 20, line: 7, column: 3))
        #expect(locator.lineText(1) == "a")
        #expect(locator.lineCount == 7)
    }

    @Test("Offset mitten im CRLF zeigt hinter das Zeilenende")
    func insideCRLF() {
        let locator = SourceLocator("ab\r\ncd")
        #expect(locator.position(atByteOffset: 3) == SourcePosition(offset: 3, line: 1, column: 3))
    }

    @Test("Sehr lange Zeile: Spalte stimmt, Sammelabfrage gleicht Einzelabfrage")
    func longLine() {
        let text = String(repeating: "x", count: 100_000) + "\u{1F389}y\nz"
        let locator = SourceLocator(text)
        #expect(locator.position(atByteOffset: 100_004).column == 100_002)
        #expect(locator.position(atByteOffset: 100_006) == SourcePosition(offset: 100_006, line: 2, column: 1))
        let offsets = [0, 7, 99_999, 100_000, 100_004, 100_005, 100_006]
        let batch = locator.positions(atByteOffsets: offsets)
        for offset in offsets {
            #expect(batch[offset] == locator.position(atByteOffset: offset))
        }
    }

    @Test("Sammelabfrage gleicht Einzelabfrage für jeden Offset mit gemischtem Unicode")
    func batchMatchesSingle() {
        let text = "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\tb\r\n\u{FC}\u{2028}\u{1F1E8}\u{1F1ED} c\n"
        let locator = SourceLocator(text)
        let offsets = Array(0...text.utf8.count)
        let batch = locator.positions(atByteOffsets: offsets)
        for offset in offsets {
            #expect(batch[offset] == locator.position(atByteOffset: offset))
        }
    }

    @Test("Synthetischer Ort hat Zeile 0, Positionen ordnen nach Offset")
    func synthetic() {
        let span = SourceSpan.synthetic()
        #expect(span.file == "<generated>")
        #expect(span.isSynthetic)
        #expect(SourceSpan.synthetic("x.kdl").file == "x.kdl")
        #expect(SourcePosition(offset: 1, line: 1, column: 2) < SourcePosition(offset: 2, line: 1, column: 3))
    }

    @Test("Byte-Scan der Zeilen gleicht der Zeichen-Referenz auf Zufallstexten")
    func byteScanMatchesCharacterReference() {
        let pieces = ["a", "\n", "\r", "\r\n", "\u{85}", "\u{2028}", "\u{2029}", "\u{0C}", "\u{0B}", "\u{308}", "\u{1F1E8}\u{1F1ED}", "\u{E4}", "\u{2027}", "\u{C0}", "\t", " "]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for _ in 0..<500 {
            var text = ""
            for _ in 0..<40 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                text += pieces[Int(state >> 33) % pieces.count]
            }
            var line = 1
            var column = 1
            var offset = 0
            var expected: [Int: SourcePosition] = [:]
            for character in text {
                expected[offset] = SourcePosition(offset: offset, line: line, column: column)
                offset += character.utf8.count
                if character.unicodeScalars.contains(where: { [0x0A, 0x0D, 0x0C, 0x85, 0x2028, 0x2029].contains($0.value) }) {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
            }
            let locator = SourceLocator(text)
            #expect(locator.lineCount == line, "\(text.debugDescription)")
            for (offset, position) in expected {
                #expect(locator.position(atByteOffset: offset) == position, "\(text.debugDescription) @ \(offset)")
            }
            #expect(locator.positions(atByteOffsets: Array(expected.keys)) == expected)
        }
    }
}
