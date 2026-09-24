import ApolloShellCore
import Testing
@testable import ApolloStyle

private let sidebarCSS = """
:root { accent-color: var(--apollo-accent-color, -apple-system-control-accent); }
.session-mark { color: var(--apollo-accent-color, -apple-system-control-accent); }

#sidebar {
  width: var(--apollo-bar-width, 44px);
  height: 100%;
  -apollo-join-radius: 14px;
}
#sidebar.bg-material { background: material(regular); }
#sidebar.bg-glass { background: glass(regular); }
#sidebar.bg-tinted-glass { background: glass(regular, rgb(from -apple-system-window-background r g b / 0.7)); }
#sidebar.bg-fixed-glass { background: glass(clear), -apple-system-window-background; }
#sidebar.themed { background: var(--apollo-bar-fill), glass(regular); }

.sidebar-modules {
  gap: var(--apollo-bar-item-spacing, 8px);
  padding: var(--apollo-bar-padding, 10px) 0;
  align-items: center;
  transition: all 500ms spatial;
}

.sidebar-icon {
  width: 32px;
  height: 32px;
  border-radius: 9px;
  color: var(--apollo-bar-icon-color, -apple-system-label);
  transition: background 120ms ease-out;
}
.sidebar-icon:hover { background: rgb(from -apple-system-label r g b / 0.14); }
.sidebar-glyph { font-size: 14px; font-weight: 600; width: 18px; height: 18px; -apollo-font-scale: none; }
.power-glyph { font-size: 15px; }

.status-capsule {
  gap: 2px;
  padding: 4px 0;
  border-radius: 9999px;
  background: rgb(from -apple-system-label r g b / 0.08);
}
.status-icon:checked { background: rgb(from -apple-system-label r g b / 0.14); }
.battery-glyph { transform: rotate(-90deg); font-size: 13px; }

.sidebar-divider {
  width: 20px;
  height: 2px;
  border-radius: 9999px;
  background: rgb(from -apple-system-label r g b / 0.18);
}
"""

@Suite("Beispiel: Sidebar aus der Default-Config")
struct SidebarSampleTests {
    private let styles: StyleEngine = {
        let config = StyleSheet.parse(sidebarCSS, file: "style.css", origin: .config).0
        return StyleEngine(sheets: [BaseStyleSheet.sheet, config])
    }()

    private func environment(_ themeCSS: String?, _ appearance: Appearance = .light) -> StyleEnvironment {
        let theme = themeCSS.map { Theme.make(identifier: "t", styleSheet: ThemeStyleSheetParser.parse($0)) } ?? .standard
        return StyleEnvironment(appearance: appearance, reduceMotion: false, reduceTransparency: false,
                                tokens: ThemeTokenBridge.environment(for: theme, appearance: appearance))
    }

    private func sidebar(_ classes: [String], _ environment: StyleEnvironment) -> ComputedStyle {
        styles.computedStyle(for: StyleSubject(kind: "panel", id: "sidebar", classes: classes), ancestors: [], parent: nil,
                             inline: [], environment: environment).0
    }

    private func child(_ subject: StyleSubject, _ environment: StyleEnvironment) -> ComputedStyle {
        let panel = StyleSubject(kind: "panel", id: "sidebar", classes: ["bg-glass"])
        let root = sidebar(["bg-glass"], environment)
        return styles.computedStyle(for: subject, ancestors: [panel], parent: root, inline: [], environment: environment).0
    }

    @Test("das Stylesheet lädt ohne Diagnose")
    func loadsClean() {
        #expect(StyleSheet.parse(sidebarCSS, file: "style.css", origin: .config).1.isEmpty)
    }

    @Test("ohne Theme: Glas, 44 pt, Systemakzent, Systemschrift 13 pt")
    func noTheme() {
        let style = sidebar(["bg-glass"], environment(nil))
        #expect(style["background"] == .layers([.glass(.regular, tint: nil)]))
        #expect(style["width"] == .length(CSSLength(44, .points)))
        #expect(style["accent-color"] == .color(.system(name: "-apple-system-control-accent", alpha: 1)))
        #expect(style["font-size"] == .length(CSSLength(13, .points)))
        #expect(style["-apollo-join-radius"] == .length(CSSLength(14, .points)))
    }

    @Test("jede Hintergrundvariante der Sidebar")
    func variants() {
        let env = environment(nil)
        #expect(sidebar(["bg-material"], env)["background"] == .layers([.material(.regular)]))
        #expect(sidebar(["bg-tinted-glass"], env)["background"]
            == .layers([.glass(.regular, tint: .system(name: "-apple-system-window-background", alpha: 0.7))]))
        #expect(sidebar(["bg-fixed-glass"], env)["background"]
            == .layers([.glass(.clear, tint: nil), .color(.system(name: "-apple-system-window-background", alpha: 1))]))
    }

    @Test("Theme mit Leistenfarbe und Deckkraft: abgeleitete Füllung über Glas, Breite aus dem Theme")
    func themedBar() {
        let env = environment(":root { --apollo-bar-color: #202020; --apollo-bar-opacity: 0.5; --apollo-bar-width: 60px; --apollo-accent-color: #ff0000; }")
        let style = sidebar(["themed"], env)
        #expect(style["background"] == .layers([.color(CSSColorParser.rgba(ThemeColor(hex: 0x202020, alpha: 0.5))), .glass(.regular, tint: nil)]))
        #expect(style["width"] == .length(CSSLength(60, .points)))
        #expect(style["accent-color"] == .color(.rgba(red: 1, green: 0, blue: 0, alpha: 1)))
        let noGlass = environment(":root { --apollo-bar-color: #202020; --apollo-glass: false; }")
        #expect(sidebar(["themed"], noGlass)["background"] == .layers([.color(CSSColorParser.rgba(ThemeColor(hex: 0x202020)))]))
    }

    @Test("Symbol im Hover, Übergang, Farbe aus dem Token oder label")
    func icon() {
        let env = environment(nil)
        let style = child(StyleSubject(kind: "button", classes: ["sidebar-icon"], pseudo: [.hover]), env)
        #expect(style["background"] == .layers([.color(.system(name: "-apple-system-label", alpha: 0.14))]))
        #expect(style["transition"] == .transitions([Transition(property: "background", duration: 0.12, curve: .cubicBezier(0, 0, 0.58, 1))]))
        #expect(style["color"] == .color(.system(name: "-apple-system-label", alpha: 1)))
        #expect(style["border-radius"] == .lengths(Array(repeating: CSSLength(9, .points), count: 4)))
    }

    @Test("Schriftskalierung: Glyphe der Leiste bleibt, Akku-Glyphe skaliert und dreht sich")
    func fontScale() {
        let env = environment(":root { --apollo-font-size: 15px; }")
        let glyph = child(StyleSubject(kind: "icon", classes: ["sidebar-glyph"]), env)
        #expect(glyph["font-size"] == .length(CSSLength(14, .points)))
        #expect(glyph["font-weight"] == .number(600))
        let battery = child(StyleSubject(kind: "icon", classes: ["battery-glyph"]), env)
        #expect(battery["font-size"] == .length(CSSLength(13 * (15.0 / 13.0), .points)))
        #expect(battery["transform"] == .transform([.rotate(-90)]))
    }

    @Test("Abstände aus Tokens, Kapsel, Trenner; hell und dunkel bleiben symbolisch gleich")
    func modules() {
        let env = environment(":root { --apollo-bar-padding: 12px; --apollo-bar-item-spacing: 6px; }")
        let modules = child(StyleSubject(kind: "column", classes: ["sidebar-modules"]), env)
        #expect(modules["padding"] == .lengths([CSSLength(12, .points), CSSLength(0, .points), CSSLength(12, .points), CSSLength(0, .points)]))
        #expect(modules["gap"] == .length(CSSLength(6, .points)))
        #expect(modules["transition"] == .transitions([Transition(property: "all", duration: 0.5, curve: .cubicBezier(0.38, 1.21, 0.22, 1))]))
        let light = child(StyleSubject(kind: "shape", classes: ["sidebar-divider"]), environment(nil, .light))
        let dark = child(StyleSubject(kind: "shape", classes: ["sidebar-divider"]), environment(nil, .dark))
        #expect(light == dark)
        #expect(light["background"] == .layers([.color(.system(name: "-apple-system-label", alpha: 0.18))]))
    }
}
