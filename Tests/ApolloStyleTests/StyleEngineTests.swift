import ApolloBase
import ApolloShellCore
import Testing
@testable import ApolloStyle

private let plain = StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false, tokens: .empty)
private let red = CSSColor.rgba(red: 1, green: 0, blue: 0, alpha: 1)
private let blue = CSSColor.rgba(red: 0, green: 0, blue: 1, alpha: 1)

private func engine(_ sheets: [(String, StyleOrigin)]) -> StyleEngine {
    StyleEngine(sheets: sheets.enumerated().map { index, sheet in
        StyleSheet.parse(sheet.0, file: "s\(index).css", origin: sheet.1).0
    })
}

private func compute(_ engine: StyleEngine, _ subject: StyleSubject, ancestors: [StyleSubject] = [],
                     parent: ComputedStyle? = nil, inline: String? = nil,
                     environment: StyleEnvironment = plain) -> (ComputedStyle, [Diagnostic]) {
    let declarations = inline.map { StyleEngine.parseInline($0, span: .synthetic("inline")).0 } ?? []
    return engine.computedStyle(for: subject, ancestors: ancestors, parent: parent, inline: declarations, environment: environment)
}

private func width(_ style: ComputedStyle) -> Double? {
    if case let .length(length)? = style["width"] { return length.value }
    return nil
}

private func themed(_ css: String, _ appearance: Appearance = .light) -> TokenEnvironment {
    ThemeTokenBridge.environment(for: Theme.make(identifier: "t", styleSheet: ThemeStyleSheetParser.parse(css)), appearance: appearance)
}

@Suite("Kaskade")
struct StyleEngineTests {
    private let x = StyleSubject(kind: "text", classes: ["x"])

    @Test("Spezifität schlägt die Reihenfolge")
    func specificity() {
        let styles = engine([("#a { width: 10px } .b { width: 20px } text { width: 30px }", .config)])
        #expect(width(compute(styles, StyleSubject(kind: "text", id: "a", classes: ["b"])).0) == 10)
        #expect(width(compute(styles, StyleSubject(kind: "text", classes: ["b"])).0) == 20)
    }

    @Test("bei gleicher Spezifität gewinnt die spätere Regel, auch über Dateien")
    func order() {
        #expect(width(compute(engine([(".x { width: 1px } .x { width: 2px }", .config)]), x).0) == 2)
        #expect(width(compute(engine([(".x { width: 1px }", .config), (".x { width: 2px }", .config)]), x).0) == 2)
    }

    @Test("Stufen: Grundstylesheet < Config < user.css < style=, unabhängig von der Spezifität")
    func origins() {
        let styles = engine([
            ("#i.x.y { width: 1px }", .base),
            (".x { width: 2px }", .config),
            ("text { width: 3px }", .user),
        ])
        let subject = StyleSubject(kind: "text", id: "i", classes: ["x", "y"])
        #expect(width(compute(styles, subject, inline: "width: 4px").0) == 4)
        #expect(width(compute(styles, subject).0) == 3)
        #expect(width(compute(engine([("#i.x.y { width: 1px }", .base), (".x { width: 2px }", .config)]), subject).0) == 2)
    }

    @Test("!important schlägt jede normale Deklaration, unter wichtigen gilt die Stufe")
    func important() {
        let styles = engine([(".x { width: 1px !important }", .base), (".x { width: 2px !important }", .config), (".x { width: 3px }", .user)])
        #expect(width(compute(styles, x, inline: "width: 4px").0) == 2)
        #expect(width(compute(styles, x, inline: "width: 5px !important").0) == 5)
    }

    @Test("Vererbung: color erbt, width nicht")
    func inheritance() {
        let styles = engine([(":root { color: red; width: 5px }", .config)])
        let root = compute(styles, StyleSubject(kind: "panel")).0
        let child = compute(styles, StyleSubject(kind: "text"), ancestors: [StyleSubject(kind: "panel")], parent: root).0
        #expect(root["color"] == .color(red))
        #expect(child["color"] == .color(red))
        #expect(child["width"] == nil)
    }

    @Test("inherit, initial und unset")
    func wideKeywords() {
        let styles = engine([(":root { color: red; width: 5px; accent-color: blue } .c { width: inherit; accent-color: initial; color: unset }", .config)])
        let panel = StyleSubject(kind: "panel")
        let root = compute(styles, panel).0
        let child = compute(styles, StyleSubject(kind: "text", classes: ["c"]), ancestors: [panel], parent: root).0
        #expect(width(child) == 5)
        #expect(child["accent-color"] == .color(.system(name: "-apple-system-control-accent", alpha: 1)))
        #expect(child["color"] == .color(red))
    }

    @Test("Vorgaben aus der Spec stehen im berechneten Stil")
    func initialValues() {
        let style = compute(engine([]), x).0
        #expect(style["accent-color"] == .color(.system(name: "-apple-system-control-accent", alpha: 1)))
        #expect(style["-apollo-corner-shape"] == .keyword("continuous"))
        #expect(style["-apollo-font-scale"] == .keyword("auto"))
        #expect(style["-apollo-image-rendering"] == .keyword("original"))
        #expect(style["-apollo-sweep-angle"] == .angle(360))
        #expect(style["-apollo-start-angle"] == .angle(-90))
        #expect(style["width"] == nil)
    }

    @Test("@media hell/dunkel und erzwungenes Erscheinungsbild")
    func appearance() {
        let styles = engine([(".x { width: 1px } @media (prefers-color-scheme: dark) { .x { width: 2px } }", .config)])
        func environment(_ appearance: Appearance, _ forced: String?) -> StyleEnvironment {
            let tokens = forced.map { TokenEnvironment(values: ["--apollo-theme-appearance": $0]) } ?? .empty
            return StyleEnvironment(appearance: appearance, reduceMotion: false, reduceTransparency: false, tokens: tokens)
        }
        #expect(width(compute(styles, x, environment: environment(.light, nil)).0) == 1)
        #expect(width(compute(styles, x, environment: environment(.dark, nil)).0) == 2)
        #expect(width(compute(styles, x, environment: environment(.light, "dark")).0) == 2)
        #expect(width(compute(styles, x, environment: environment(.dark, "light")).0) == 1)
        #expect(width(compute(styles, x, environment: environment(.dark, "auto")).0) == 2)
    }

    @Test("prefers-reduced-motion und prefers-reduced-transparency")
    func reducedPreferences() {
        let styles = engine([("""
        .x { width: 1px }
        @media (prefers-reduced-motion: reduce) { .x { width: 2px } }
        @media (prefers-reduced-transparency: reduce) { .x { height: 3px } }
        """, .config)])
        let reduced = StyleEnvironment(appearance: .light, reduceMotion: true, reduceTransparency: true, tokens: .empty)
        let style = compute(styles, x, environment: reduced).0
        #expect(width(style) == 2)
        #expect(style["height"] == .length(CSSLength(3, .points)))
        #expect(compute(styles, x).0["height"] == nil)
    }

    @Test("var(): Token nicht gesetzt ergibt den Ersatz, Theme setzt es, Verlauf none zählt nicht")
    func tokens() {
        let styles = engine([(".x { color: var(--apollo-accent-color, -apple-system-control-accent); background: var(--apollo-bar-gradient, red) }", .config)])
        let none = compute(styles, x).0
        #expect(none["color"] == .color(.system(name: "-apple-system-control-accent", alpha: 1)))
        let theme = themed(":root { --apollo-accent-color: #0000ff; --apollo-bar-gradient: none; }")
        let set = compute(styles, x, environment: StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false, tokens: theme)).0
        #expect(set["color"] == .color(blue))
        #expect(set["background"] == .layers([.color(red)]))
    }

    @Test("Custom Properties werden geerbt; ein fremder Theme-Name ersetzt die :root-Deklaration, wenn die Config ihn deklariert")
    func customProperties() {
        let (sheet, _) = StyleSheet.parse(":root { --gap: 4px } row { gap: var(--gap) }", file: "style.css", origin: .config)
        let styles = StyleEngine(sheets: [sheet])
        let panel = StyleSubject(kind: "panel")
        let row = StyleSubject(kind: "row")

        let root = compute(styles, panel).0
        #expect(root.customProperties["--gap"] == "4px")
        #expect(compute(styles, row, ancestors: [panel], parent: root).0["gap"] == .length(CSSLength(4, .points)))

        let theme = themed(":root { --gap: 9px; }")
        let declared = StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false,
                                        tokens: theme.declaring(sheet.declaredCustomProperties))
        let themedRoot = compute(styles, panel, environment: declared).0
        #expect(compute(styles, row, ancestors: [panel], parent: themedRoot, environment: declared).0["gap"] == .length(CSSLength(9, .points)))

        let undeclared = StyleEnvironment(appearance: .light, reduceMotion: false, reduceTransparency: false, tokens: theme)
        let plainRoot = compute(styles, panel, environment: undeclared).0
        #expect(plainRoot.customProperties["--gap"] == "4px")
    }

    @Test("ungültig nach var(): Warnung mit Zeile, der nächste Kandidat gilt")
    func invalidAfterSubstitution() {
        let styles = engine([(".a { width: 10px }\n.a.b { width: var(--nope) }", .config)])
        let (style, diagnostics) = compute(styles, StyleSubject(kind: "text", classes: ["a", "b"]))
        #expect(width(style) == 10)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.span?.start.line == 2)
        #expect(diagnostics.first?.message.contains("--nope") == true)
    }

    @Test("ein Zyklus in Custom Properties endet mit Warnungen und dem Ersatzwert")
    func cycle() {
        let styles = engine([(".x { --p: var(--q); --q: var(--p); width: var(--p, 3px) }", .config)])
        let (style, diagnostics) = compute(styles, x)
        #expect(width(style) == 3)
        #expect(diagnostics.count == 2)
    }

    @Test("style= am Element: Deklarationen und Warnungen mit dem Ort des Attributs")
    func inlineStyles() {
        let span = SourceSpan.synthetic("shell.kdl")
        let (declarations, diagnostics) = StyleEngine.parseInline("height: 20px; colr: red; --apollo-bar-color: red; background: url(a.png)", span: span)
        #expect(declarations.map(\.property) == ["height"])
        #expect(diagnostics.count == 3)
        #expect(diagnostics.allSatisfy { $0.span == span })
    }

    @Test("gleiche Eingabe ergibt denselben Stil")
    func deterministic() {
        let styles = engine([(".x { width: 1px; color: red; transition: all 200ms }", .config)])
        #expect(compute(styles, x).0 == compute(styles, x).0)
    }
}
