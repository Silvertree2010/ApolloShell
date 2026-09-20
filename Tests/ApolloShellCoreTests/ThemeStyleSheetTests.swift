import ApolloShellCore
import Testing

@Suite("Themes: reading the CSS subset")
struct ThemeStyleSheetTests {
    private func isIgnoredRule(_ issue: ThemeIssue) -> Bool {
        if case .ignoredRule = issue.kind { return true }
        return false
    }

    @Test("one entry in :root")
    func single() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-accent-color: #ff0000; }")
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-accent-color", value: "#ff0000", line: 1)])
        #expect(sheet.dark.isEmpty)
        #expect(sheet.issues.isEmpty)
    }

    @Test("line numbers count comments and breaks in")
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

    @Test("Windows-style line endings count the same")
    func carriageReturns() {
        let sheet = ThemeStyleSheetParser.parse(":root {\r\n  --apollo-bar-width: 40px;\r\n}\r\n")
        #expect(sheet.light.map(\.line) == [2])
        #expect(sheet.light.first?.value == "40px")
    }

    @Test("the dark variant out of the @media block")
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

    @Test("the spelling of the condition does not matter")
    func darkConditionSpelling() {
        let sheet = ThemeStyleSheetParser.parse(
            "@media(prefers-color-scheme:dark){:root{--apollo-accent-color:red}}"
        )
        #expect(sheet.dark.count == 1)
        #expect(sheet.issues.isEmpty)
    }

    @Test("names are stored in lower case")
    func lowercasesNames() {
        let sheet = ThemeStyleSheetParser.parse(":root { --APOLLO-Accent-Color: red; }")
        #expect(sheet.light.first?.name == "--apollo-accent-color")
    }

    @Test("what does not belong to the subset is skipped and reported", arguments: [
        "@import url(\"other.css\");\n:root { --apollo-bar-width: 40px; }",
        "h1 { color: red; }\n:root { --apollo-bar-width: 40px; }",
        "@media (prefers-color-scheme: light) { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        "@supports (display: grid) { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        "@media print { :root { --apollo-accent-color: red; } }\n:root { --apollo-bar-width: 40px; }",
        ":root:hover { --apollo-accent-color: red; }\n:root { --apollo-bar-width: 40px; }",
    ])
    func skipsForeignRules(css: String) {
        let sheet = ThemeStyleSheetParser.parse(css)
        // The one allowed line arrives, the rest does not - and one learns of it.
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-bar-width", value: "40px", line: 2)])
        #expect(sheet.dark.isEmpty)
        #expect(sheet.issues.contains(where: isIgnoredRule))
    }

    @Test("ordinary properties in :root do not get in the way and report nothing")
    func plainProperties() {
        let sheet = ThemeStyleSheetParser.parse(":root { color: red; margin: 0; --apollo-bar-width: 40px; }")
        #expect(sheet.light.map(\.name) == ["--apollo-bar-width"])
        #expect(sheet.issues.isEmpty)
    }

    @Test("foreign custom properties are kept but do not get in the way")
    func foreignCustomProperties() {
        let sheet = ThemeStyleSheetParser.parse(":root { --my-blue: #00f; --apollo-bar-width: 40px; }")
        #expect(sheet.light.map(\.name) == ["--my-blue", "--apollo-bar-width"])
        #expect(sheet.issues.isEmpty)
    }

    @Test("the last entry may leave out the semicolon without swallowing the rest")
    func lastDeclarationWithoutSemicolon() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px }\nh1 { color: red }")
        #expect(sheet.light == [ThemeDeclaration(name: "--apollo-bar-width", value: "40px", line: 1)])
        #expect(sheet.issues.contains(where: isIgnoredRule))
    }

    @Test("a semicolon and a bracket in a string do not count")
    func punctuationInStrings() {
        let sheet = ThemeStyleSheetParser.parse(#":root { --apollo-background-image: url("a;b}c.png"); --apollo-bar-width: 40px; }"#)
        #expect(sheet.light.map(\.value) == [#"url("a;b}c.png")"#, "40px"])
    }

    @Test("a comment in the middle of the value falls away")
    func commentInsideValue() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: /* nanu */ 40px; }")
        #expect(sheet.light.first?.value == "40px")
    }

    @Test("the same entry twice: the last one wins")
    func lastWins() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px; --apollo-bar-width: 50px; }")
        #expect(sheet.light.map(\.value) == ["40px", "50px"])
        let theme = Theme.make(identifier: "x", styleSheet: sheet)
        #expect(theme.number(.barWidth) == 50)
    }

    @Test("two :root blocks add up")
    func twoRootBlocks() {
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-bar-width: 40px; }\n:root { --apollo-bar-radius: 4px; }")
        #expect(sheet.light.count == 2)
        #expect(sheet.issues.isEmpty)
    }

    @Test("broken files never give a crash", arguments: [
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
        // Always a usable theme, and the notices stay countable.
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues.count <= ThemeLimits.standard.maxIssues + 1)
    }

    @Test("random bytes give a theme with the defaults")
    func randomBytes() {
        // A fixed seed: the same run gives the same characters.
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8((state >> 33) & 0xFF)
        }
        for _ in 0..<100 {
            let text = String(decoding: (0..<512).map { _ in next() }, as: UTF8.self)
            let theme = Theme.make(identifier: "zufall", styleSheet: ThemeStyleSheetParser.parse(text))
            #expect(theme.number(.barWidth) == nil)
        }
    }

    @Test("an upper limit for the number of entries")
    func declarationLimit() {
        let many = (0..<50).map { "--apollo-x\($0): red;" }.joined()
        let sheet = ThemeStyleSheetParser.parse(":root {" + many + "}", limits: ThemeLimits(maxDeclarations: 10))
        #expect(sheet.light.count == 10)
        #expect(sheet.issues.contains { if case .tooManyDeclarations = $0.kind { true } else { false } })
    }

    @Test("an upper limit for the number of notices")
    func issueLimit() {
        let many = (0..<50).map { "h\($0) { color: red; }" }.joined(separator: "\n")
        let sheet = ThemeStyleSheetParser.parse(many, limits: ThemeLimits(maxIssues: 5))
        #expect(sheet.issues.count == 6) // five notices and the remark
        #expect(sheet.issues.last.map { if case .moreIssues = $0.kind { true } else { false } } == true)
    }
}
