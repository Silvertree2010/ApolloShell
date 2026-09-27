import Testing
@testable import ApolloKDL

@Suite("KDL: Quelle, Zeichen und Zahlen")
struct KDLLexicalTests {
    @Test("gültige Zahlen", arguments: [
        ("0", 0.0), ("+10", 10), ("-10", -10), ("1_000", 1000), ("1_2_3_4", 1234), ("011", 11),
        ("1.5", 1.5), ("1_1.0", 11), ("1.0_2", 1.02), ("1e10", 1e10), ("1.0E-10", 1e-10), ("1.0e-10_0", 1e-100),
        ("0x10", 16), ("0xABC_def_0123", 737_894_400_291), ("0x123abc_", 1_194_684), ("0o76543210", 16_434_824),
        ("0o012_3456_7", 342_391), ("0b10_", 2), ("0b1_0", 2), ("-0o7", -7), ("#inf", .infinity), ("#-inf", -.infinity),
        ("0", 0), ("007", 7), ("-42", -42), ("+42", 42), ("123456789012345", 123_456_789_012_345),
        ("1234567890123456", 1_234_567_890_123_456), ("99999999999999999999", 1e20), ("1_000", 1000),
    ] as [(String, Double)])
    func validNumbers(raw: String, expected: Double) {
        #expect(KDLNumberLiteral.value(of: raw) == expected)
    }

    @Test("grosse Zahlen werden korrekt gerundet")
    func bigNumbers() {
        #expect(KDLNumberLiteral.value(of: "0xABCDEF0123456789abcdef") == Double("207698809136909011942886895"))
        #expect(KDLNumberLiteral.value(of: "0xabcdef1234567890") == Double("12379813812177893520"))
        #expect(KDLNumberLiteral.value(of: "1.23E+1000") == .infinity)
        #expect(KDLNumberLiteral.value(of: "1.23E-1000") == 0)
        #expect(KDLNumberLiteral.value(of: "#nan")?.isNaN == true)
    }

    @Test("ungültige Zahlen", arguments: [
        "1.", "1.e7", "1._7", ".1", "0x", "0x_10", "0xx10", "0x10g10", "0bx01", "0o45678",
        "1.0.0", "1.0E10e10", "1e", "+", "0n", "", "0X10", "1e_5", "#", "#infinity", "12a", "-",
    ])
    func invalidNumbers(raw: String) {
        #expect(KDLNumberLiteral.value(of: raw) == nil)
    }

    @Test("Zeilenumbrüche nach 2.0.0, VT ist Leerraum")
    func newlines() {
        for value: UInt32 in [0x0A, 0x0C, 0x0D, 0x85, 0x2028, 0x2029] {
            #expect(KDLCharacters.isNewline(Unicode.Scalar(value)!))
        }
        #expect(!KDLCharacters.isNewline("\u{0B}"))
        #expect(KDLCharacters.isUnicodeSpace("\u{0B}"))
        #expect(KDLCharacters.isUnicodeSpace("\u{3000}"))
        #expect(KDLCharacters.isUnicodeSpace("\t"))
        #expect(!KDLCharacters.isUnicodeSpace("\u{200B}"))
    }

    @Test("verbotene Codepoints")
    func disallowed() {
        for value: UInt32 in [0x00, 0x08, 0x0E, 0x19, 0x7F, 0x200E, 0x200F, 0x202A, 0x202E, 0x2066, 0x2069, 0xFEFF] {
            #expect(KDLCharacters.isDisallowed(Unicode.Scalar(value)!))
        }
        #expect(!KDLCharacters.isDisallowed("\t"))
        #expect(!KDLCharacters.isDisallowed("\u{2028}"))
    }

    @Test("Zeichen in Bezeichnern")
    func identifierCharacters() {
        for scalar: Unicode.Scalar in ["(", ")", "{", "}", "[", "]", "/", "\\", "\"", "#", ";", "=", " ", "\n", "\u{0B}"] {
            #expect(!KDLCharacters.isIdentifierCharacter(scalar))
        }
        for scalar: Unicode.Scalar in ["<", ",", "?", "_", "-", ".", "\u{1F389}", "\u{308}"] {
            #expect(KDLCharacters.isIdentifierCharacter(scalar))
        }
    }

    @Test("nackte Wörter werden eingeordnet")
    func classify() {
        #expect(KDLCharacters.classify("node") == .identifier)
        #expect(KDLCharacters.classify("_15") == .identifier)
        #expect(KDLCharacters.classify("?15") == .identifier)
        #expect(KDLCharacters.classify("-") == .identifier)
        #expect(KDLCharacters.classify("--") == .identifier)
        #expect(KDLCharacters.classify("-.") == .identifier)
        #expect(KDLCharacters.classify(".") == .identifier)
        #expect(KDLCharacters.classify("1a") == .number)
        #expect(KDLCharacters.classify("-1em") == .number)
        #expect(KDLCharacters.classify("+0n") == .number)
        guard case .invalid(let dot) = KDLCharacters.classify(".5") else {
            Issue.record("'.5' muss ungültig sein")
            return
        }
        #expect(dot.contains("0.5"))
        guard case .invalid(let signedDot) = KDLCharacters.classify("-.5") else {
            Issue.record("'-.5' muss ungültig sein")
            return
        }
        #expect(signedDot.contains("decimal point"))
        guard case .invalid(let keyword) = KDLCharacters.classify("true") else {
            Issue.record("'true' muss ungültig sein")
            return
        }
        #expect(keyword.contains("#true"))
        #expect(keyword.contains("KDL v2"))
        guard case .invalid(let reserved) = KDLCharacters.classify("-inf") else {
            Issue.record("'-inf' muss ungültig sein")
            return
        }
        #expect(reserved.contains("#-inf"))
    }

    @Test("gültige nackte Bezeichner für den Writer")
    func bareIdentifiers() {
        #expect(KDLCharacters.isValidBareIdentifier("auto-check"))
        #expect(KDLCharacters.isValidBareIdentifier("gr\u{FC}\u{DF}e"))
        #expect(KDLCharacters.isValidBareIdentifier("-"))
        #expect(!KDLCharacters.isValidBareIdentifier(""))
        #expect(!KDLCharacters.isValidBareIdentifier("with space"))
        #expect(!KDLCharacters.isValidBareIdentifier("0node"))
        #expect(!KDLCharacters.isValidBareIdentifier("a=b"))
        #expect(!KDLCharacters.isValidBareIdentifier("null"))
    }

    @Test("Quelle dekodiert UTF-8 und erkennt Zeilenumbrüche")
    func source() {
        let source = KDLSource("a\u{E4}\u{1F389}\r\nb\u{85}c\u{2028}d\u{0B}e")
        #expect(source.decoded(at: 1)?.scalar == "\u{E4}")
        #expect(source.decoded(at: 1)?.length == 2)
        #expect(source.decoded(at: 3)?.scalar == "\u{1F389}")
        #expect(source.newlineLength(at: 7) == 2)
        #expect(source.newlineLength(at: 8) == 1)
        #expect(source.newlineLength(at: 10) == 2)
        #expect(source.newlineLength(at: 13) == 3)
        #expect(source.newlineLength(at: 17) == nil)
        #expect(source.hasPrefix("\r\n", at: 7))
        #expect(!source.hasPrefix("\r\n", at: 8))
        #expect(source.string(from: 1, to: 7) == "\u{E4}\u{1F389}")
        #expect(source.decoded(at: source.count) == nil)
    }

    @Test("Zeilenanfang rückwärts, auch bei NEL, LS, BOM und Folgebyte 0x85")
    func lineStart() {
        #expect(KDLSource("a\u{85}bc").lineStart(before: 4) == 3)
        #expect(KDLSource("x\u{2028}y").lineStart(before: 4) == 4)
        #expect(KDLSource("a\r\nb").lineStart(before: 3) == 3)
        #expect(KDLSource("\u{FEFF}ab").lineStart(before: 4) == 3)
        #expect(KDLSource("\u{FEFF}ab").bomLength == 3)
        #expect(KDLSource("\u{145}z").lineStart(before: 2) == 0)
        #expect(KDLSource("ab").lineStart(before: 2) == 0)
    }
}
