import ApolloShellCore
import Testing

@Suite("Themes: CSS-Teilmenge lesen")
struct ThemeStyleSheetTests {
    private func isIgnoredRule(_ issue: ThemeIssue) -> Bool {
        if case .ignoredRule = issue.kind { return true }
        return false
    }

    @Test("eine Angabe in :root")
    func single() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-accent-color: #ff0000; }")
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-accent-color", value: "#ff0000", line: 1)])
        #expect(sheet.dark.isEmpty)
        #expect(sheet.issues.isEmpty)
    }

    @Test("Zeilennummern zaehlen Kommentare und Umbrueche mit")
    func lineNumbers() {
        let css = """
        /* Ein Kommentar
           ueber zwei Zeilen */
        :root {
            --apollo-accent-color: red;

            --apollo-bar-width: 40px;
        }
        """
        let sheet = ThemeStyleSheetParser.parse(css)
        #expect(sheet.light.map(\.line) == [4, 6])
        #expect(sheet.issues.isEmpty)
    }

    @Test("Zeilenenden nach Windows-Art zaehlen gleich")
    func carriageReturns() {
        let sheet = ThemeStyleSheetParser.parse(":root {\r\n  --apollo-bar-width: 40px;\r\n}\r\n")
        #expect(sheet.light.map(\.line) == [2])
        #expect(sheet.light.first?.value == "40px")
    }

    @Test("dunkle Abweichung aus dem @media-Block")
    func darkBlock() {
        let css = """
        :root { --apollo-accent-color: red; }
        @media (prefers-color-scheme: dark) {
          :root { --apollo-accent-color: blue; }
        }
        """
        let sheet = ThemeStyleSheetParser.parse(css)
        #expect(sheet.light.map(\.value) == ["red"])
        #expect(sheet.dark == [ThemeDeclaration(name: "--apollo-accent-color", value: "blue", line: 3)])
        #expect(sheet.issues.isEmpty)
    }

    @Test("Schreibweise der Bedingung ist egal")
    func darkConditionSpelling() {
        let sheet = ThemeStyleSheetParser.parse(
            "@media(prefers-color-scheme:dark){:root{--apollo-accent-color:red}}"
        )
        #expect(sheet.dark.count == 1)
        #expect(sheet.issues.isEmpty)
    }

    @Test("Namen werden klein geschrieben abgelegt")
    func lowercasesNames() {
        let sheet = ThemeStyleSheetParser.parse(":root { --APOLLO-Accent-Color: red; }")
        #expect(sheet.light.first?.name == "--apollo-accent-color")
    }

    @Test("was nicht zur Teilmenge gehoert, wird uebersprungen und gemeldet", arguments: [
        "@import url(\"other.css\");\n:root { --apollo-bar-width: 40px; }",
        "h1 { color: red; }\n:root { --apollo-bar-width: 40px; }",
        "@media (prefers-color-scheme: light) { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        "@supports (display: grid) { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        "@media print { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        ":root:hover { --apollo-accent-color: red; }\n:root { --apollo-bar-width: 40px; }",
    ])
    func skipsForeignRules(css: String) {
        let sheet = ThemeStyleSheetParser.parse(css)
        // Die eine erlaubte Zeile kommt an, der Rest nicht - und man erfaehrt es.
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-bar-width", value: "40px", line: 2)])
        #expect(sheet.dark.isEmpty)
        #expect(sheet.issues.contains(where: isIgnoredRule))
    }

    @Test("gewoehnliche Eigenschaften in :root stoeren nicht und melden nichts")
    func plainProperties() {
        let sheet = ThemeStyleSheetParser.parse(":root { color: red; margin: 0; --apollo-bar-width: 40px; }")
        #expect(sheet.light.map(\.name) == ["--apollo-bar-width"])
        #expect(sheet.issues.isEmpty)
    }

    @Test("fremde eigene Eigenschaften bleiben erhalten, stoeren aber nicht")
    func foreignCustomProperties() {
        let sheet = ThemeStyleSheetParser.parse(":root { --my-blue: #00f; --apollo-bar-width: 40px; }")
        #expect(sheet.light.map(\.name) == ["--my-blue", "--apollo-bar-width"])
        #expect(sheet.issues.isEmpty)
    }

    @Test("die letzte Angabe darf das Semikolon weglassen, ohne den Rest zu verschlucken")
    func lastDeclarationWithoutSemicolon() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px }\nh1 { color: red }")
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-bar-width", value: "40px", line: 1)])
        #expect(sheet.issues.contains(where: isIgnoredRule))
    }

    @Test("Semikolon und Klammer in einer Zeichenkette zaehlen nicht")
    func punctuationInStrings() {
        let sheet = ThemeStyleSheetParser.parse(#":root { --apollo-background-image: url("a;b}c.png"); --apollo-bar-width: 40px; }"#)
        #expect(sheet.light.map(\.value) == [#"url("a;b}c.png")"#, "40px"])
    }

    @Test("Kommentar mitten im Wert faellt weg")
    func commentInsideValue() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: /* nanu */ 40px; }")
        #expect(sheet.light.first?.value == "40px")
    }

    @Test("dieselbe Angabe zweimal: die letzte gewinnt")
    func lastWins() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px; --apollo-bar-width: 50px; }")
        #expect(sheet.light.map(\.value) == ["40px", "50px"])
        let theme = Theme.make(identifier: "x", styleSheet: sheet)
        #expect(theme.number(.barWidth) == 50)
    }

    @Test("zwei :root-Bloecke ergaenzen sich")
    func twoRootBlocks() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px; }\n:root { --apollo-bar-radius: 4px; }")
        #expect(sheet.light.count == 2)
        #expect(sheet.issues.isEmpty)
    }

    @Test("kaputte Dateien ergeben nie einen Absturz", arguments: [
        "", " ", "{", "}", "}}}}{{{{", ":::", "@", "@media", "/*", "\"", "'abc",
        ":root {", ":root { --apollo-bar-width", ":root { --apollo-bar-width:",
        ":root { --apollo-background-image: url(\"unfertig",
        "@media (prefers-color-scheme: dark) { :root { --apollo-accent-color: red;",
        "--apollo-bar-width: 40px;", ":root { { } }", ":root { --a: }", "\u{0}\u{1}\u{2}",
        String(repeating: "{", count: 500), String(repeating: "/*", count: 500),
    ])
    func brokenInputNeverCrashes(css: String) {
        let sheet = ThemeStyleSheetParser.parse(css)
        let theme = Theme.make(identifier: "kaputt", styleSheet: sheet)
        // Immer ein benutzbares Theme, und die Hinweise bleiben zaehlbar.
        #expect(theme.color(.accent) == ThemeColorToken.accent.defaultValue())
        #expect(theme.issues.count <= ThemeLimits.standard.maxIssues + 1)
    }

    @Test("Zufallsbytes ergeben ein Theme mit den Vorgaben")
    func randomBytes() {
        // Fester Startwert: derselbe Lauf ergibt dieselben Zeichen.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }
        for _ in 0..<100 {
            let text = String(decoding: (0..<512).map { _ in next() }, as: UTF8.self)
            let theme = Theme.make(identifier: "zufall", styleSheet: ThemeStyleSheetParser.parse(text))
            #expect(theme.number(.barWidth) == ThemeNumberToken.barWidth.defaultValue())
        }
    }

    @Test("Obergrenze fuer die Zahl der Angaben")
    func declarationLimit() {
        let many = (0..<50).map { "--apollo-x\($0): red;" }.joined()
        let sheet = ThemeStyleSheetParser.parse(":root {" + many + "}", limits: ThemeLimits(maxDeclarations: 10))
        #expect(sheet.light.count == 10)
        #expect(sheet.issues.contains { if case .tooManyDeclarations = $0.kind { true } else { false } })
    }

    @Test("Obergrenze fuer die Zahl der Hinweise")
    func issueLimit() {
        let many = (0..<50).map { "h\($0) { color: red; }" }.joined(separator: "\n")
        let sheet = ThemeStyleSheetParser.parse(many, limits: ThemeLimits(maxIssues: 5))
        #expect(sheet.issues.count == 6) // fuenf Hinweise und der Vermerk
        #expect(sheet.issues.last.map { if case .moreIssues = $0.kind { true } else { false } } == true)
    }
}
