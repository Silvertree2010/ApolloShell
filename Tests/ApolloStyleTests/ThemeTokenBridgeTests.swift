import ApolloBase
import ApolloShellCore
import Testing
@testable import ApolloStyle

@Suite("Tokens aus dem Theme")
struct ThemeTokenBridgeTests {
    private func theme(_ css: String) -> Theme {
        Theme.make(identifier: "test", styleSheet: ThemeStyleSheetParser.parse(css))
    }

    private func tokens(_ css: String, _ appearance: Appearance = .light) -> TokenEnvironment {
        ThemeTokenBridge.environment(for: theme(css), appearance: appearance)
    }

    @Test("ohne Theme ist kein Token gesetzt und jeder Schalter steht auf Vorgabe")
    func noTheme() {
        let environment = ThemeTokenBridge.environment(for: .standard, appearance: .light)
        #expect(environment.value("--apollo-bar-color") == nil)
        #expect(environment.value("--apollo-bar-fill") == nil)
        #expect(environment.setTokens.isEmpty)
        #expect(environment.fontScale == 1)
        #expect(environment.animationsEnabled)
        #expect(environment.animationSpeed == 1)
        #expect(environment.glassEnabled)
        #expect(environment.shadowsEnabled)
        #expect(!environment.iconsMonochrome)
        #expect(environment.forcedAppearance == nil)
    }

    @Test("eine Farbe aus dem Theme kommt als CSS-Text und zählt als gesetzt")
    func colorToken() {
        let environment = tokens(":root { --apollo-bar-color: #112233; }")
        #expect(environment.value("--apollo-bar-color") == "#112233")
        #expect(environment.value("--Apollo-Bar-Color") == "#112233")
        #expect(environment.setTokens == ["--apollo-bar-color"])
    }

    @Test("Längen, Anteile, Zahlen, Optionen, Schalter und Texte behalten ihre Schreibweise")
    func tokenKinds() {
        let environment = tokens("""
        :root {
          --apollo-bar-width: 40px;
          --apollo-bar-opacity: 50%;
          --apollo-font-weight: 500;
          --apollo-icon-style: monochrome;
          --apollo-glass: false;
          --apollo-font-family: "SF Pro \\"Rounded\\"";
        }
        """)
        #expect(environment.value("--apollo-bar-width") == "40px")
        #expect(environment.value("--apollo-bar-opacity") == "0.5")
        #expect(environment.value("--apollo-font-weight") == "500")
        #expect(environment.value("--apollo-icon-style") == "monochrome")
        #expect(environment.value("--apollo-glass") == "false")
        #expect(environment.value("--apollo-font-family") == "\"SF Pro \\\"Rounded\\\"\"")
    }

    @Test("der Dunkel-Block gilt nur im dunklen Erscheinungsbild")
    func darkBlock() {
        let css = """
        :root { --apollo-accent-color: #ff0000; }
        @media (prefers-color-scheme: dark) { :root { --apollo-accent-color: #00ff00; } }
        """
        #expect(tokens(css, .light).value("--apollo-accent-color") == "#ff0000")
        #expect(tokens(css, .dark).value("--apollo-accent-color") == "#00ff00")
    }

    @Test("ein Verlauf none zählt als nicht gesetzt")
    func gradientNone() {
        let environment = tokens(":root { --apollo-bar-gradient: none; }")
        #expect(environment.value("--apollo-bar-gradient") == nil)
        #expect(!environment.setTokens.contains("--apollo-bar-gradient"))
        #expect(environment.value("--apollo-bar-fill") == nil)
    }

    @Test("abgeleitete Tokens, jede Kombination",
          arguments: [
              ("--apollo-bar-fill", "--apollo-bar-color", "--apollo-bar-gradient", "--apollo-bar-opacity"),
              ("--apollo-panel-fill", "--apollo-panel-color", "--apollo-panel-gradient", "--apollo-panel-opacity"),
              ("--apollo-card-fill", "--apollo-card-color", "--apollo-card-gradient", ""),
              ("--apollo-surface-fill", "--apollo-surface-color", "--apollo-surface-gradient", "--apollo-surface-opacity"),
              ("--apollo-accent-fill", "--apollo-accent-color", "--apollo-accent-gradient", ""),
              ("--apollo-toast-fill", "--apollo-toast-color", "--apollo-toast-gradient", ""),
              ("--apollo-launcher-highlight-fill", "--apollo-launcher-highlight-color", "--apollo-launcher-highlight-gradient", ""),
              ("--apollo-background-fill", "--apollo-background-color", "--apollo-background-gradient", ""),
          ])
    func derivedFill(fill: String, color: String, gradient: String, opacity: String) {
        let hasOpacity = !opacity.isEmpty
        let opacityLine = hasOpacity ? "\(opacity): 0.5;" : ""
        let gradientText = "linear-gradient(90deg, #000000 0%, #ffffff 100%)"

        #expect(tokens(":root { }").value(fill) == nil)
        #expect(tokens(":root { \(opacityLine) }").value(fill) == nil)

        let colorOnly = tokens(":root { \(color): #ff0000; \(opacityLine) }")
        #expect(colorOnly.value(fill) == (hasOpacity ? "#ff000080" : "#ff0000"))

        let gradientOnly = tokens(":root { \(gradient): \(gradientText); \(opacityLine) }")
        #expect(gradientOnly.value(fill) == (hasOpacity
            ? "linear-gradient(90deg, #00000080 0%, #ffffff80 100%)"
            : "linear-gradient(90deg, #000000 0%, #ffffff 100%)"))

        let both = tokens(":root { \(color): #ff0000; \(gradient): \(gradientText); }")
        #expect(both.value(fill) == "linear-gradient(90deg, #000000 0%, #ffffff 100%)")

        let noneAndColor = tokens(":root { \(color): #00ff00; \(gradient): none; }")
        #expect(noneAndColor.value(fill) == "#00ff00")

        #expect(!both.setTokens.contains(fill))
    }

    @Test("Schriftskalierung folgt --apollo-font-size geteilt durch 13 pt")
    func fontScale() {
        #expect(tokens(":root { --apollo-font-size: 15px; }").fontScale == 15.0 / 13.0)
        #expect(tokens(":root { --apollo-font-size: 13px; }").fontScale == 1)
    }

    @Test("globale Schalter kommen aus den Tokens")
    func switches() {
        let environment = tokens("""
        :root {
          --apollo-animations: false;
          --apollo-animation-speed: 2;
          --apollo-glass: false;
          --apollo-shadows: false;
          --apollo-icon-style: monochrome;
        }
        """)
        #expect(!environment.animationsEnabled)
        #expect(environment.animationSpeed == 2)
        #expect(!environment.glassEnabled)
        #expect(!environment.shadowsEnabled)
        #expect(environment.iconsMonochrome)
    }

    @Test("Dauern: Tempo teilt, 0 und ausgeschaltete Bewegung ergeben 0")
    func durations() {
        #expect(TokenEnvironment(values: [:]).duration(0.3) == 0.3)
        #expect(TokenEnvironment(values: ["--apollo-animation-speed": "2"]).duration(0.3) == 0.15)
        #expect(TokenEnvironment(values: ["--apollo-animation-speed": "0"]).duration(0.3) == 0)
        #expect(TokenEnvironment(values: ["--apollo-animations": "false"]).duration(0.3) == 0)
    }

    @Test("ein erzwungenes Erscheinungsbild wählt die Werte dieses Erscheinungsbilds")
    func forcedAppearance() {
        let css = """
        :root { --apollo-theme-appearance: dark; --apollo-accent-color: #ff0000; }
        @media (prefers-color-scheme: dark) { :root { --apollo-accent-color: #00ff00; } }
        """
        let environment = tokens(css, .light)
        #expect(environment.forcedAppearance == .dark)
        #expect(environment.value("--apollo-accent-color") == "#00ff00")
        let style = StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false, tokens: environment)
        #expect(style.effectiveAppearance == .dark)
        #expect(ThemeTokenBridge.effectiveAppearance(theme: theme(css), system: .light) == .dark)
        #expect(ThemeTokenBridge.effectiveAppearance(theme: .standard, system: .dark) == .dark)
    }

    @Test("Schrift auf dem Akzent wird lesbar gemacht, zählt aber nicht als gesetzt")
    func onAccent() {
        let environment = tokens(":root { --apollo-accent-color: #ffd60a; }")
        let expected = Theme.make(identifier: "x", styleSheet: ThemeStyleSheetParser.parse(":root { --apollo-accent-color: #ffd60a; }"))
            .readableColor(.onAccent)?.cssText
        #expect(expected != nil)
        #expect(environment.value("--apollo-on-accent-color") == expected)
        #expect(!environment.setTokens.contains("--apollo-on-accent-color"))
    }

    @Test("fremde Namen gelten nur, wenn die Config sie deklariert")
    func foreignNames() {
        let source = theme(":root { --sidebar-icon-size: 40px; --my-blue: #00f; }")
        #expect(source.issues.isEmpty)
        let environment = ThemeTokenBridge.environment(for: source, appearance: .light)
        #expect(environment.value("--sidebar-icon-size") == nil)
        let declared = environment.declaring(["--sidebar-icon-size"])
        #expect(declared.value("--sidebar-icon-size") == "40px")
        #expect(declared.value("--my-blue") == nil)
        #expect(!declared.setTokens.contains("--sidebar-icon-size"))

        let notes = ThemeTokenBridge.undeclaredForeignTokens(in: source, declared: ["--sidebar-icon-size"])
        #expect(notes.count == 1)
        #expect(notes.first?.severity == .note)
        #expect(notes.first?.message.contains("--my-blue") == true)
    }

    @Test("fremde Werte mit var(), url() oder Überlänge fallen weg")
    func foreignValuesAreFiltered() {
        let long = String(repeating: "a", count: 201)
        let source = theme(":root { --a: var(--b); --c: url(\"x.png\"); --d: \(long); --e: 4px !important; }")
        #expect(source.foreignLightValues == ["--e": "4px"])
    }

    @Test("fremde Werte im Dunkel-Block legen sich über :root")
    func foreignDark() {
        let source = theme("""
        :root { --size: 10px; --gap: 2px; }
        @media (prefers-color-scheme: dark) { :root { --size: 12px; } }
        """)
        #expect(source.foreignLightValues == ["--size": "10px", "--gap": "2px"])
        #expect(source.foreignDarkValues == ["--size": "12px", "--gap": "2px"])
    }

    @Test("Datei-Tokens zählen als gesetzt, kommen aber nicht als Wert")
    func fileTokens() {
        let environment = tokens(":root { --apollo-background-image: none; }")
        #expect(environment.value("--apollo-background-image") == nil)
        #expect(!environment.setTokens.contains("--apollo-background-image"))
    }
}
