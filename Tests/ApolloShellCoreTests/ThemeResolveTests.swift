import ApolloShellCore
import Testing

@Suite("Themes: bringing the values together")
struct ThemeResolveTests {
    private func theme(_ css: String, identifier: String = "test") -> Theme {
        Theme.make(identifier: identifier, styleSheet: ThemeStyleSheetParser.parse(css))
    }

    private func hasKind(_ theme: Theme, _ match: (ThemeIssue.Kind) -> Bool) -> Bool {
        theme.issues.contains { match($0.kind) }
    }

    @Test("Appearance: light/dark out of the theme, otherwise auto", arguments: [
        (":root { --apollo-theme-appearance: light; }", ThemeAppearance.light),
        (":root { --apollo-theme-appearance: dark; }", .dark),
        (":root { --apollo-theme-appearance: auto; }", .auto),
        (":root { --apollo-accent-color: #ff0000; }", .auto),
        (":root { --apollo-theme-appearance: sepia; }", .auto),
    ])
    func appearance(css: String, expected: ThemeAppearance) {
        #expect(ThemeAppearance(theme: theme(css)) == expected)
        #expect(ThemeAppearance(theme: .standard) == .auto)
    }

    @Test("a missing token: stays empty, and the app then takes the system values")
    func missingToken() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.number(.barWidth) == nil)
        #expect(theme.color(.surface) == nil)
        #expect(theme.flag(.animations) == nil)
        #expect(theme.option(.backgroundFit) == nil)
        #expect(theme.issues.isEmpty)
    }

    @Test("an unknown token: ignore it, but report it - with a line number")
    func unknownToken() {
        let theme = theme(":root {\n  --apollo-does-not-exist: red;\n}")
        #expect(theme.issues == [ThemeIssue(.unknownToken("--apollo-does-not-exist"), line: 2)])
    }

    @Test("another namespace stays silent")
    func foreignNamespace() {
        #expect(theme(":root { --my-blue: #00f; }").issues.isEmpty)
    }

    @Test("an unreadable value: no value and a notice with a line number")
    func unreadableValue() {
        let theme = theme(":root {\n  --apollo-accent-color: nonsense;\n}")
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues == [ThemeIssue(.unreadableValue(token: "--apollo-accent-color", value: "nonsense"),
                                            line: 2)])
    }

    @Test("one unreadable value does not topple the readable one before it")
    func lastReadableWins() {
        let theme = theme(":root { --apollo-bar-width: 40px; --apollo-bar-width: no-idea; }")
        #expect(theme.number(.barWidth) == 40)
    }

    @Test("numbers outside the range are clamped and reported")
    func clamping() {
        let cases: [(String, ThemeNumberToken, Double)] = [
            ("--apollo-bar-width: 4000px", .barWidth, 160),
            ("--apollo-bar-width: -50px", .barWidth, 36),
            ("--apollo-panel-opacity: 400%", .panelOpacity, 1),
            ("--apollo-panel-opacity: -1", .panelOpacity, 0),
            ("--apollo-font-size: 900px", .fontSize, 32),
            ("--apollo-corner-radius: 9999px", .cornerRadius, 48),
            ("--apollo-animation-speed: 100", .animationSpeed, 3),
            ("--apollo-border-width: 100px", .borderWidth, 8),
        ]
        for (declaration, token, expected) in cases {
            let theme = theme(":root { \(declaration); }")
            #expect(theme.number(token) == expected, "\(declaration)")
            #expect(hasKind(theme, { if case .clamped = $0 { true } else { false } }), "\(declaration)")
        }
    }

    @Test("text that is too long is shortened")
    func textIsCapped() {
        let long = String(repeating: "a", count: 500)
        let theme = theme(":root { --apollo-theme-name: \"\(long)\"; }")
        #expect(theme.text(.themeName)?.count == ThemeLimits.standard.maxTextLength)
        #expect(hasKind(theme) { if case .clamped = $0 { true } else { false } })
    }

    @Test("dark inherits what stands in :root")
    func darkInheritsLight() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.accent, dark: true) == ThemeColor(hex: 0xFF0000))
    }

    @Test("without an entry it stays empty in the dark too")
    func darkStaysEmpty() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.surface, dark: true) == nil)
    }

    @Test("what stands only in the dark block is missing in the light")
    func darkOnlyStaysDark() throws {
        let theme = theme("@media (prefers-color-scheme: dark) { :root { --apollo-bar-color: #101014; } }")
        #expect(theme.color(.bar) == nil)
        #expect(try #require(theme.color(.bar, dark: true)) == ThemeColor(hex: 0x101014))
    }

    @Test("the @media block only holds in the dark")
    func darkOverride() {
        let theme = theme("""
        :root { --apollo-accent-color: #ff0000; --apollo-bar-width: 40px; }
        @media (prefers-color-scheme: dark) { :root { --apollo-accent-color: #0000ff; } }
        """)
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.color(.accent, dark: true) == ThemeColor(hex: 0x0000FF))
        #expect(theme.number(.barWidth, dark: true) == 40)
        #expect(theme.issues.isEmpty)
    }

    @Test("contrast: an unreadable text color is nudged into place")
    func contrastGuard() throws {
        let theme = theme(":root { --apollo-text-color: #fbfbfb; }")
        let text = try #require(theme.color(.text))
        // Without a ground of its own the check measures on the ground of the shell.
        let surface = ThemeColorToken.surface.defaultValue()
        #expect(text != ThemeColor(hex: 0xFBFBFB))
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
        #expect(hasKind(theme) { if case .contrastAdjusted = $0 { true } else { false } })
    }

    @Test("contrast: readable colors stay exactly as they are")
    func contrastLeavesGoodColorsAlone() {
        // With a dark variant, otherwise the dark text would stand on a dark
        // ground in the dark appearance - and that is exactly what the contrast
        // limit would (rightly) touch.
        let theme = theme("""
        :root { --apollo-text-color: #102030; }
        @media (prefers-color-scheme: dark) { :root { --apollo-text-color: #e8e8ea; } }
        """)
        #expect(theme.color(.text) == ThemeColor(hex: 0x102030))
        #expect(theme.color(.text, dark: true) == ThemeColor(hex: 0xE8E8EA))
        #expect(theme.issues.isEmpty)
    }

    @Test("contrast: a light text without a dark variant stands out in the dark")
    func contrastReportsTheAppearance() throws {
        let theme = theme(":root { --apollo-text-color: #102030; }")
        #expect(theme.color(.text) == ThemeColor(hex: 0x102030))
        #expect(try #require(theme.color(.text, dark: true)) != ThemeColor(hex: 0x102030))
        #expect(theme.issues.contains(where: {
            if case let .contrastAdjusted(_, _, _, dark) = $0.kind { dark } else { false }
        }))
        #expect(!theme.issues.contains(where: {
            if case let .contrastAdjusted(_, _, _, dark) = $0.kind { !dark } else { false }
        }))
    }

    @Test("huge numbers are clamped without crashing")
    func hugeNumbers() {
        let digits20 = String(repeating: "9", count: 20)
        let digits307 = String(repeating: "9", count: 307)
        for literal in [digits20, digits307, "-" + digits307] {
            let theme = theme(":root { --apollo-bar-width: \(literal)px; --apollo-theme-format: \(literal); }")
            let width = theme.number(.barWidth)
            #expect(width == 160 || width == 36, "\(literal.prefix(3))...")
            #expect(hasKind(theme, { if case .clamped = $0 { true } else { false } }))
        }
    }

    @Test("numbers outside Int can be written")
    func cssTextBeyondInt() {
        #expect(!ThemeUnit.scalar.cssText(1e23).isEmpty)
        #expect(!ThemeUnit.points.cssText(-1e307).isEmpty)
        #expect(ThemeUnit.points.cssText(12) == "12px")
        #expect(ThemeUnit.ratio.cssText(0.5) == "0.5")
    }

    @Test("contrast: on a medium-light ground it is darkened, not replaced by black")
    func contrastOnMidBackground() {
        let background = ThemeColor(hex: 0xAAAAAA)
        let fixed = ThemeGuards.readable(ThemeColor(hex: 0xB0B0B0), on: background, minimum: 4.5)
        #expect(ThemeColor.contrast(fixed, background) >= 4.5)
        #expect(fixed != ThemeColor(hex: 0x000000))
    }

    @Test("contrast: it is measured on the ground the theme sets")
    func contrastUsesThemeBackground() throws {
        let theme = theme(":root { --apollo-surface-color: #000000; --apollo-text-color: #111111; }")
        let text = try #require(theme.color(.text))
        #expect(text.luminance > ThemeColor(hex: 0x111111).luminance)
        #expect(ThemeColor.contrast(text, ThemeColor(hex: 0x000000)) >= 4.5)
    }

    @Test("contrast: almost transparent text becomes opaque if need be")
    func contrastWithAlpha() throws {
        let theme = theme(":root { --apollo-text-color: rgba(0, 0, 0, 0.02); }")
        let text = try #require(theme.color(.text))
        let surface = ThemeColorToken.surface.defaultValue()
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
    }

    @Test("contrast is enforced in both appearances")
    func contrastInBothAppearances() throws {
        let theme = theme("@media (prefers-color-scheme: dark) { :root { --apollo-text-color: #1d1d1d; } }")
        let text = try #require(theme.color(.text, dark: true))
        let surface = ThemeColorToken.surface.defaultValue(dark: true)
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
    }

    @Test("a higher format number: read it, skip the unknown, show a notice")
    func newerFormat() {
        let theme = theme("""
        :root {
          --apollo-theme-format: 7;
          --apollo-accent-color: #ff0000;
          --apollo-comes-later: 12px;
        }
        """)
        #expect(theme.formatVersion == 7)
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.contains(ThemeIssue(.newerFormat(found: 7, known: ThemeFormat.current))))
        #expect(theme.issues.contains(ThemeIssue(.unknownToken("--apollo-comes-later"), line: 4)))
    }

    @Test("without an entry the format number is the one of this version")
    func defaultFormat() {
        #expect(theme("").formatVersion == ThemeFormat.current)
        #expect(theme(":root { --apollo-theme-format: 0; }").formatVersion == 1)
        #expect(theme(":root { --apollo-theme-format: abc; }").formatVersion == 1)
    }

    @Test("identifier and short name")
    func identifiers() {
        #expect(Theme.make(identifier: "My Theme", styleSheet: ThemeStyleSheet()).slug == "my-theme")
        #expect(Theme.make(identifier: "  ", styleSheet: ThemeStyleSheet()).identifier == "theme")
        #expect(Theme.make(identifier: "...", styleSheet: ThemeStyleSheet()).identifier == "theme")
        #expect(Theme.make(identifier: "Grün & Blau!", styleSheet: ThemeStyleSheet()).slug == "gr-n-blau")
    }

    @Test("title: the name out of the theme, otherwise the identifier")
    func title() {
        #expect(Theme.make(identifier: "Sunset", styleSheet: ThemeStyleSheet()).title == "Sunset")
        let named = theme(":root { --apollo-theme-name: \"Abendrot\"; }", identifier: "Sunset")
        #expect(named.title == "Abendrot")
        #expect(named.identifier == "Sunset")
    }

    @Test("images without a theme folder: no image, but a notice")
    func assetsNeedFolder() {
        let theme = theme(":root { --apollo-background-image: url(\"bg.png\"); }")
        #expect(theme.file(.backgroundImage) == nil)
        #expect(theme.issues.contains(ThemeIssue(.rejectedAsset(reference: "bg.png", reason: .needsThemeFolder),
                                                 line: 1)))
    }

    @Test("after reading, only a named token has a value - light as well as dark")
    func onlyDeclaredTokensHaveAValue() {
        let theme = theme(":root { --apollo-accent-color: red; }")
        for token in ThemeTokenCatalog.standard.tokens {
            let declared = token.name == ThemeColorToken.accent.name
            #expect((theme.value(token.name) != nil) == declared, "\(token.name)")
            #expect((theme.value(token.name, dark: true) != nil) == declared, "\(token.name)")
        }
    }

    @Test("the built-in theme does not have a single value")
    func standardIsEmpty() {
        #expect(Theme.standard.lightValues.isEmpty)
        #expect(Theme.standard.darkValues.isEmpty)
    }

    @Test("text on the accent: made readable as soon as the theme names the accent")
    func readableOnAccent() throws {
        // Yellow: white on it would be unreadable.
        let yellow = theme(":root { --apollo-accent-color: #ffd60a; }")
        let onYellow = try #require(yellow.readableColor(.onAccent))
        #expect(ThemeColor.contrast(onYellow, ThemeColor(hex: 0xFFD60A)) >= 3)
        #expect(onYellow != ThemeColorToken.onAccent.defaultValue())
        // Names neither accent nor text: nothing, the app stays with macOS.
        #expect(theme(":root { --apollo-bar-width: 40px; }").readableColor(.onAccent) == nil)
        // Names the text itself: exactly that applies.
        let own = theme(":root { --apollo-accent-color: #000000; --apollo-on-accent-color: #ffffff; }")
        #expect(own.readableColor(.onAccent) == ThemeColor(hex: 0xFFFFFF))
    }

    @Test("an empty sheet yields exactly the built-in theme")
    func emptySheetEqualsStandard() {
        let theme = Theme.make(identifier: "default", styleSheet: ThemeStyleSheet())
        #expect(theme == Theme.standard)
    }
}

@Suite("Themes: only what's stated applies")
struct ThemeDeclaredTests {
    private func theme(_ css: String) -> Theme {
        Theme.make(identifier: "test", styleSheet: ThemeStyleSheetParser.parse(css))
    }

    @Test("a theme names exactly the tokens from its file")
    func declaresWhatItSets() {
        let value = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(value.declares("--apollo-accent-color"))
        #expect(!value.declares("--apollo-bar-width"))
        #expect(!value.declares("--apollo-card-color"))
    }

    @Test("a token that stands only in the dark block also counts")
    func darkOnlyCounts() {
        let value = theme("""
        :root { --apollo-accent-color: #ff0000; }
        @media (prefers-color-scheme: dark) { :root { --apollo-bar-color: #101014; } }
        """)
        #expect(value.declares("--apollo-bar-color"))
    }

    @Test("case does not matter, an earlier name counts too")
    func caseAndAliases() {
        let value = theme(":root { --APOLLO-ACCENT-COLOR: #ff0000; }")
        #expect(value.declares("--apollo-accent-color"))
    }

    @Test("an unreadable value does not count as named")
    func unreadableValueIsNotDeclared() {
        let value = theme(":root { --apollo-bar-width: totally wrong; }")
        #expect(!value.declares("--apollo-bar-width"))
        #expect(!value.issues.isEmpty)
    }
}
