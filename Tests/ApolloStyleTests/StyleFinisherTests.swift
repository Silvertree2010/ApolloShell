import ApolloBase
import Testing
@testable import ApolloStyle

private let red = CSSColor.rgba(red: 1, green: 0, blue: 0, alpha: 1)
private let blue = CSSColor.rgba(red: 0, green: 0, blue: 1, alpha: 1)

@Suite("Berechneter Stil: Zusammensetzen und Schalter")
struct StyleFinisherTests {
    private let x = StyleSubject(kind: "text", classes: ["x", "y"])

    private func style(_ css: String, tokens: [String: String] = [:], motion: Bool = false, transparency: Bool = false,
                       parent: ComputedStyle? = nil, subject: StyleSubject? = nil) -> ComputedStyle {
        let sheet = StyleSheet.parse(css, file: "style.css", origin: .config).0
        let environment = StyleEnvironment(appearance: .light, reduceMotion: motion, reduceTransparency: transparency,
                                           tokens: TokenEnvironment(values: tokens))
        return StyleEngine(sheets: [sheet]).computedStyle(for: subject ?? x, ancestors: parent == nil ? [] : [StyleSubject(kind: "panel")],
                                                          parent: parent, inline: [], environment: environment).0
    }

    @Test("background-color wird unterste Schicht, wenn es stärker ist; background setzt es sonst zurück")
    func backgroundComposition() {
        #expect(style(".x { background: glass(regular) } .x.y { background-color: red }")["background"]
            == .layers([.glass(.regular, tint: nil), .color(red)]))
        #expect(style(".x.y { background: glass(regular) } .x { background-color: red }")["background"]
            == .layers([.glass(.regular, tint: nil)]))
        #expect(style(".x { background-color: red }")["background"] == .layers([.color(red)]))
        #expect(style(".x { background-color: red }")["background-color"] == nil)
        #expect(style(".x { width: 1px }")["background"] == nil)
    }

    @Test("padding und margin: Längsform und Kurzform, die spätere bzw. stärkere Deklaration gewinnt je Seite")
    func sideLonghands() {
        let pt = { (values: [Double]) in CSSValue.lengths(values.map { CSSLength($0, .points) }) }
        #expect(style(".x { padding: 4px; padding-top: 10px }")["padding"] == pt([10, 4, 4, 4]))
        #expect(style(".x { padding-top: 10px; padding: 4px }")["padding"] == pt([4, 4, 4, 4]))
        #expect(style(".x { padding-left: 3px }")["padding"] == pt([0, 0, 0, 3]))
        #expect(style(".x.y { padding: 4px } .x { padding-right: 9px }")["padding"] == pt([4, 4, 4, 4]))
        #expect(style(".x { padding: 4px } .x { padding-bottom: 7px }")["padding"] == pt([4, 4, 7, 4]))
        #expect(style(".x { padding-bottom: 7px } .x { padding: 1px 2px }")["padding"] == pt([1, 2, 1, 2]))
        #expect(style(".x { margin: 1px 2px 3px 4px; margin-right: -5px; margin-top: 6px }")["margin"] == pt([6, -5, 3, 4]))
        #expect(style(".x { margin-left: 2px } .x { margin: 0 }")["margin"] == pt([0, 0, 0, 0]))
        #expect(style(".x { padding-top: 1px !important; padding: 4px }")["padding"] == pt([1, 4, 4, 4]))
        #expect(style(".x { padding: 4px; padding-top: bad }")["padding"] == pt([4, 4, 4, 4]))
        #expect(style(".x { padding-top: 10px }")["padding-top"] == nil)
        #expect(style(".x { width: 1px }")["padding"] == nil)
        #expect(style(".x { width: 1px }")["margin"] == nil)
    }

    @Test("border setzt sich aus Kurzschreibweise und Einzelwerten nach Rang zusammen")
    func borderComposition() {
        #expect(style(".x { border: 1px solid red } .x.y { border-color: blue }")["border"] == .border(width: 1, dashed: false, color: blue))
        #expect(style(".x.y { border: 2px dashed red } .x { border-width: 5px }")["border"] == .border(width: 2, dashed: true, color: red))
        #expect(style(".x { border-width: 2px }")["border"] == .border(width: 2, dashed: false, color: .currentColor))
        #expect(style(".x { border: none }")["border"] == nil)
        #expect(style(".x { border-color: red }")["border"] == nil)
        #expect(style(".x { border: 1px solid red }")["border-width"] == nil)
        #expect(style(".x { border: 1px solid red }")["border-color"] == nil)
    }

    @Test("Schriftskalierung mit --apollo-font-size, ausser -apollo-font-scale: none")
    func fontScale() {
        let tokens = ["--apollo-font-size": "15px"]
        #expect(style(".x { font-size: 13px }", tokens: tokens)["font-size"] == .length(CSSLength(13 * (15.0 / 13.0), .points)))
        #expect(style(".x { font-size: 13px }")["font-size"] == .length(CSSLength(13, .points)))
        #expect(style(".x { font-size: 13px; -apollo-font-scale: none }", tokens: tokens)["font-size"] == .length(CSSLength(13, .points)))
        let parent = ComputedStyle(values: ["font-size": .length(CSSLength(15, .points))])
        #expect(style(".z { width: 1px }", tokens: tokens, parent: parent)["font-size"] == .length(CSSLength(15, .points)))
        let unscaledParent = ComputedStyle(values: ["-apollo-font-scale": .keyword("none")])
        #expect(style(".x { font-size: 13px }", tokens: tokens, parent: unscaledParent)["font-size"] == .length(CSSLength(13, .points)))
    }

    @Test("--apollo-animations: false setzt jede Dauer auf 0 und hält Animationen an")
    func animationsOff() {
        let css = ".x { transition: all 200ms linear; -apollo-appear: fade 300ms; animation: spin 1s infinite; animation-delay: -0.5s }"
        let off = style(css, tokens: ["--apollo-animations": "false"])
        #expect(off["transition"] == .transitions([Transition(property: "all", duration: 0, curve: .linear)]))
        #expect(off["-apollo-appear"] == .appear([AppearTransition(effects: [.fade], duration: 0, curve: .cubicBezier(0.25, 0.1, 0.25, 1))]))
        #expect(off["animation"] == .keyword("none"))
        #expect(off["animation-delay"] == .duration(0))
        let zero = style(css, tokens: ["--apollo-animation-speed": "0"])
        #expect(zero["animation"] == .keyword("none"))
    }

    @Test("--apollo-animation-speed teilt jede Dauer")
    func animationSpeed() {
        let css = ".x { transition: all 200ms linear; -apollo-disappear: fade 300ms linear; animation: pulse 1s; animation-delay: -0.5s }"
        let fast = style(css, tokens: ["--apollo-animation-speed": "2"])
        #expect(fast["transition"] == .transitions([Transition(property: "all", duration: 0.1, curve: .linear)]))
        #expect(fast["-apollo-disappear"] == .appear([AppearTransition(effects: [.fade], duration: 0.15, curve: .linear)]))
        #expect(fast["animation"] == .animation(name: "pulse", duration: 0.5, repeatCount: 1))
        #expect(fast["animation-delay"] == .duration(-0.25))
    }

    @Test("Bewegung reduzieren: Blenden statt Bewegung")
    func reduceMotion() {
        let css = """
        .x { -apollo-appear: scale(0.6) slide(bottom) 200ms linear; animation: spin 1s infinite;
             transition: match 300ms linear, size 200ms linear, transform 1s linear, background 100ms linear }
        .y.x { width: 1px }
        """
        let reduced = style(css, motion: true)
        #expect(reduced["-apollo-appear"] == .appear([AppearTransition(effects: [.fade], duration: 0.2, curve: .linear)]))
        #expect(reduced["animation"] == .keyword("none"))
        #expect(reduced["transition"] == .transitions([Transition(property: "background", duration: 0.1, curve: .linear)]))
        #expect(style(".x { animation: pulse 1s infinite }", motion: true)["animation"] == .animation(name: "pulse", duration: 1, repeatCount: nil))
    }

    @Test("--apollo-glass: false lässt Glas weg, Material bleibt")
    func glassOff() {
        let css = ".x { background: glass(regular, red), material(thin), blue }"
        #expect(style(css, tokens: ["--apollo-glass": "false"])["background"] == .layers([.material(.thin), .color(blue)]))
        #expect(style(css)["background"] == .layers([.glass(.regular, tint: red), .material(.thin), .color(blue)]))
    }

    @Test("prefers-reduced-transparency ersetzt Glas und Material durch den Fensterhintergrund")
    func reduceTransparency() {
        let window = BackgroundLayer.color(.system(name: "-apple-system-window-background", alpha: 1))
        let css = ".x { background: glass(regular), material(thin), blue }"
        #expect(style(css, transparency: true)["background"] == .layers([window, window, .color(blue)]))
        #expect(style(css, tokens: ["--apollo-glass": "false"], transparency: true)["background"] == .layers([window, window, .color(blue)]))
    }

    @Test("--apollo-shadows: false leert box-shadow und den Schatten des Griffs, drop-shadow bleibt")
    func shadowsOff() {
        let css = ".x { box-shadow: 0 1px 2px red; -apollo-thumb-shadow: 0 1px 2px red; filter: drop-shadow(0 1px 1px red) }"
        let off = style(css, tokens: ["--apollo-shadows": "false"])
        #expect(off["box-shadow"] == .shadows([]))
        #expect(off["-apollo-thumb-shadow"] == .shadows([]))
        #expect(off["filter"] == .filters([.dropShadow(Shadow(x: 0, y: 1, blur: 1, spread: 0, color: red))]))
    }
}
