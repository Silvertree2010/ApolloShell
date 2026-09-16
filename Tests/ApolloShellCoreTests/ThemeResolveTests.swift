import ApolloShellCore
import Testing

@Suite("Themes: Werte zusammenfuehren")
struct ThemeResolveTests {
    private func theme(_ css: String, identifier: String = "test") -> Theme {
        Theme.make(identifier: identifier, styleSheet: ThemeStyleSheetParser.parse(css))
    }

    private func hasKind(_ theme: Theme, _ match: (ThemeIssue.Kind) -> Bool) -> Bool {
        theme.issues.contains { match($0.kind) }
    }

    @Test("fehlendes Token: Vorgabe")
    func missingToken() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.number(.barWidth) == ThemeNumberToken.barWidth.defaultValue())
        #expect(theme.color(.surface) == ThemeColorToken.surface.defaultValue())
        #expect(theme.flag(.animations) == true)
        #expect(theme.option(.backgroundFit) == "fill")
        #expect(theme.issues.isEmpty)
    }

    @Test("unbekanntes Token: ignorieren, aber melden - mit Zeilennummer")
    func unknownToken() {
        let theme = theme(":root {\n  --apollo-gibt-es-nicht: red;\n}")
        #expect(theme.issues == [ThemeIssue(.unknownToken("--apollo-gibt-es-nicht"), line: 2)])
    }

    @Test("ein fremder Namensraum bleibt still")
    func foreignNamespace() {
        #expect(theme(":root { --my-blue: #00f; }").issues.isEmpty)
    }

    @Test("unlesbarer Wert: Vorgabe und ein Hinweis mit Zeilennummer")
    func unreadableValue() {
        let theme = theme(":root {\n  --apollo-accent-color: nonsense;\n}")
        #expect(theme.color(.accent) == ThemeColorToken.accent.defaultValue())
        #expect(theme.issues == [ThemeIssue(.unreadableValue(token: "--apollo-accent-color", value: "nonsense"),
                                            line: 2)])
    }

    @Test("ein unlesbarer Wert kippt den lesbaren davor nicht um")
    func lastReadableWins() {
        let theme = theme(":root { --apollo-bar-width: 40px; --apollo-bar-width: keine-ahnung; }")
        #expect(theme.number(.barWidth) == 40)
    }

    @Test("Zahlen ausserhalb des Bereichs werden geklemmt und gemeldet")
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

    @Test("zu langer Text wird gekuerzt")
    func textIsCapped() {
        let long = String(repeating: "a", count: 500)
        let theme = theme(":root { --apollo-theme-name: \"\(long)\"; }")
        #expect(theme.text(.themeName).count == ThemeLimits.standard.maxTextLength)
        #expect(hasKind(theme) { if case .clamped = $0 { true } else { false } })
    }

    @Test("dunkel erbt, was in :root steht")
    func darkInheritsLight() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.accent, dark: true) == ThemeColor(hex: 0xFF0000))
    }

    @Test("ohne Angabe gilt im Dunkeln die dunkle Vorgabe")
    func darkDefaults() {
        let theme = theme(":root { --apollo-accent-color: #ff0000; }")
        #expect(theme.color(.surface, dark: true) == ThemeColorToken.surface.defaultValue(dark: true))
        #expect(theme.color(.surface, dark: true) != theme.color(.surface))
    }

    @Test("der @media-Block gilt nur im Dunkeln")
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

    @Test("Kontrast: eine unlesbare Schriftfarbe wird zurechtgerueckt")
    func contrastGuard() {
        let theme = theme(":root { --apollo-text-color: #fbfbfb; }")
        let text = theme.color(.text)
        let surface = theme.color(.surface)
        #expect(text != ThemeColor(hex: 0xFBFBFB))
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
        #expect(hasKind(theme) { if case .contrastAdjusted = $0 { true } else { false } })
    }

    @Test("Kontrast: lesbare Farben bleiben genau, wie sie sind")
    func contrastLeavesGoodColorsAlone() {
        // Mit dunkler Abweichung, sonst stuende die dunkle Schrift im
        // dunklen Erscheinungsbild auf dunklem Grund - und genau das wuerde
        // die Kontrastgrenze (zu Recht) anfassen.
        let theme = theme("""
        :root { --apollo-text-color: #102030; }
        @media (prefers-color-scheme: dark) { :root { --apollo-text-color: #e8e8ea; } }
        """)
        #expect(theme.color(.text) == ThemeColor(hex: 0x102030))
        #expect(theme.color(.text, dark: true) == ThemeColor(hex: 0xE8E8EA))
        #expect(theme.issues.isEmpty)
    }

    @Test("Kontrast: eine helle Schrift ohne dunkle Abweichung faellt im Dunkeln auf")
    func contrastReportsTheAppearance() {
        let theme = theme(":root { --apollo-text-color: #102030; }")
        #expect(theme.color(.text) == ThemeColor(hex: 0x102030))
        #expect(theme.color(.text, dark: true) != ThemeColor(hex: 0x102030))
        #expect(theme.issues.contains(where: {
            if case let .contrastAdjusted(_, _, _, dark) = $0.kind { dark } else { false }
        }))
        #expect(!theme.issues.contains(where: {
            if case let .contrastAdjusted(_, _, _, dark) = $0.kind { !dark } else { false }
        }))
    }

    @Test("riesige Zahlen werden geklemmt, ohne abzustuerzen")
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

    @Test("Zahlen ausserhalb von Int lassen sich schreiben")
    func cssTextBeyondInt() {
        #expect(!ThemeUnit.scalar.cssText(1e23).isEmpty)
        #expect(!ThemeUnit.points.cssText(-1e307).isEmpty)
        #expect(ThemeUnit.points.cssText(12) == "12px")
        #expect(ThemeUnit.ratio.cssText(0.5) == "0.5")
    }

    @Test("Kontrast: auf mittelhellem Grund wird abgedunkelt, nicht durch Schwarz ersetzt")
    func contrastOnMidBackground() {
        let background = ThemeColor(hex: 0xAAAAAA)
        let fixed = ThemeGuards.readable(ThemeColor(hex: 0xB0B0B0), on: background, minimum: 4.5)
        #expect(ThemeColor.contrast(fixed, background) >= 4.5)
        #expect(fixed != ThemeColor(hex: 0x000000))
    }

    @Test("Kontrast: gemessen wird auf dem Untergrund, den das Theme setzt")
    func contrastUsesThemeBackground() {
        let theme = theme(":root { --apollo-surface-color: #000000; --apollo-text-color: #111111; }")
        let text = theme.color(.text)
        #expect(text.luminance > ThemeColor(hex: 0x111111).luminance)
        #expect(ThemeColor.contrast(text, ThemeColor(hex: 0x000000)) >= 4.5)
    }

    @Test("Kontrast: fast durchsichtige Schrift wird notfalls deckend")
    func contrastWithAlpha() {
        let theme = theme(":root { --apollo-text-color: rgba(0, 0, 0, 0.02); }")
        let text = theme.color(.text)
        let surface = theme.color(.surface)
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
    }

    @Test("Kontrast wird in beiden Erscheinungsbildern erzwungen")
    func contrastInBothAppearances() {
        let theme = theme("@media (prefers-color-scheme: dark) { :root { --apollo-text-color: #1d1d1d; } }")
        let text = theme.color(.text, dark: true)
        let surface = theme.color(.surface, dark: true)
        #expect(ThemeColor.contrast(text.composited(over: surface), surface) >= 4.5)
    }

    @Test("hoehere Formatnummer: lesen, Unbekanntes ueberspringen, Hinweis zeigen")
    func newerFormat() {
        let theme = theme("""
        :root {
          --apollo-theme-format: 7;
          --apollo-accent-color: #ff0000;
          --apollo-kommt-erst-spaeter: 12px;
        }
        """)
        #expect(theme.formatVersion == 7)
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.contains(ThemeIssue(.newerFormat(found: 7, known: ThemeFormat.current))))
        #expect(theme.issues.contains(ThemeIssue(.unknownToken("--apollo-kommt-erst-spaeter"), line: 4)))
    }

    @Test("ohne Angabe ist die Formatnummer die dieser Fassung")
    func defaultFormat() {
        #expect(theme("").formatVersion == ThemeFormat.current)
        #expect(theme(":root { --apollo-theme-format: 0; }").formatVersion == 1)
        #expect(theme(":root { --apollo-theme-format: abc; }").formatVersion == 1)
    }

    @Test("Kennung und Kurzname")
    func identifiers() {
        #expect(Theme.make(identifier: "My Theme", styleSheet: ThemeStyleSheet()).slug == "my-theme")
        #expect(Theme.make(identifier: "  ", styleSheet: ThemeStyleSheet()).identifier == "theme")
        #expect(Theme.make(identifier: "...", styleSheet: ThemeStyleSheet()).identifier == "theme")
        #expect(Theme.make(identifier: "Grün & Blau!", styleSheet: ThemeStyleSheet()).slug == "gr-n-blau")
    }

    @Test("Titel: der Name aus dem Theme, sonst die Kennung")
    func title() {
        #expect(Theme.make(identifier: "Sunset", styleSheet: ThemeStyleSheet()).title == "Sunset")
        let named = theme(":root { --apollo-theme-name: \"Abendrot\"; }", identifier: "Sunset")
        #expect(named.title == "Abendrot")
        #expect(named.identifier == "Sunset")
    }

    @Test("Bilder ohne Theme-Ordner: kein Bild, aber ein Hinweis")
    func assetsNeedFolder() {
        let theme = theme(":root { --apollo-background-image: url(\"bg.png\"); }")
        #expect(theme.file(.backgroundImage) == nil)
        #expect(theme.issues.contains(ThemeIssue(.rejectedAsset(reference: "bg.png", reason: .needsThemeFolder),
                                                 line: 1)))
    }

    @Test("nach dem Lesen hat jedes Token einen Wert - hell wie dunkel")
    func everyTokenHasAValue() {
        let theme = theme(":root { --apollo-accent-color: red; }")
        for token in ThemeTokenCatalog.standard.tokens {
            #expect(theme.value(token.name) != nil, "\(token.name)")
            #expect(theme.value(token.name, dark: true) != nil, "\(token.name)")
        }
    }

    @Test("ein leeres Blatt ergibt genau das eingebaute Theme")
    func emptySheetEqualsStandard() {
        let theme = Theme.make(identifier: "default", styleSheet: ThemeStyleSheet())
        #expect(theme == Theme.standard)
    }
}
