import Testing
import AppKit
import ApolloBase
import ApolloProviders
@testable import ApolloShell

@MainActor
@Suite("Default-Config gezeichnet wie 0.1.4.2 (9b Paket 2)")
struct DefaultRenderTests {
    static let resources = PackageResources.root.appendingPathComponent("Resources")

    static func shot(_ id: String, state: String? = nil, theme: String? = nil, themeURL: URL? = nil, dark: Bool = false) throws -> Snapshot {
        let config = state.map { resources.appendingPathComponent("render/\($0)") } ?? resources.appendingPathComponent("configs/apolloshell-default")
        let fixture = state.map { resources.appendingPathComponent("render/\($0)/fixture.kdl") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? resources.appendingPathComponent("render/fixture.kdl")
        let session = try RenderSession(config: config, resources: resources, fixture: ProviderFixture.load(fixture),
                                        fixtureRoot: fixture.deletingLastPathComponent(), dark: dark, scale: 1,
                                        theme: themeURL ?? theme.map { PackageResources.root.appendingPathComponent("examples/themes/\($0)") })
        let surface = try #require(session.surface(id))
        return Snapshot(rep: try #require(NSBitmapImageRep(data: try session.capture(surface, name: id))), scale: 1)
    }

    @Test("Desktop-Uhr: Zeile mit Zeit, Strich und Datum, 24 pt Schattenraum, Schatten sichtbar auf hellem Grund")
    func desktopClock() throws {
        let shot = try Self.shot("desktop-clock")
        #expect(abs(shot.size.width - 479) <= 4)
        #expect(abs(shot.size.height - 163) <= 4)
        let shadow = try #require(shot.bounds { $0.r < 200 })
        #expect(shadow.minX < 40 && shadow.maxX > 200, "\(shadow)")
        #expect(shadow.height < 140)
    }

    @Test("OSD: Regler 30 × 150 mittig in 52 × 182, Füllung bei 0,35 bis 52,5 pt")
    func osd() throws {
        let shot = try Self.shot("volume")
        #expect(shot.size == CGSize(width: 52, height: 182))
        let fill = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(abs(fill.minX - 11) <= 1 && abs(fill.width - 30) <= 1)
        #expect(abs(fill.height - 52.5) <= 1.5)
    }

    @Test("OSD stumm: Füllung nur so lang wie die Spur breit, obwohl die Lautstärke 0,35 ist", arguments: ["osd-muted", "osd-0"])
    func osdMuted(state: String) throws {
        let shot = try Self.shot("volume", state: state)
        let fill = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(abs(fill.height - 30) <= 1.5)
    }

    @Test("Sitzungsmenü: 102 × 496, Kacheln 80 × 80 links bündig, Emblem in der Mitte am Beginn der Begrüssung")
    func session() throws {
        let shot = try Self.shot("session")
        #expect(abs(shot.size.width - 102) <= 1 && abs(shot.size.height - 496) <= 1)
        let emblem = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(emblem.minY > 208 && emblem.maxY < 288)
        #expect(emblem.width < 60)
    }

    @Test("Sitzungsmenü: Emblem bleibt System-Akzent, auch wenn ein Theme den Akzent setzt (9b-P2-5)")
    func sessionEmblemIgnoresThemeAccent() throws {
        let source = try String(contentsOf: PackageResources.root.appendingPathComponent("examples/themes/minimal.css"), encoding: .utf8)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("emblem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let theme = folder.appendingPathComponent("green.css")
        try source.replacingOccurrences(of: "#ff6b35", with: "#00ff00").replacingOccurrences(of: "#ff8354", with: "#00ff00")
            .write(to: theme, atomically: true, encoding: .utf8)
        let green: (RGBA) -> Bool = { $0.g > 200 && $0.r < 80 && $0.b < 80 }
        #expect(try Self.shot("session", themeURL: theme).bounds(where: green) == nil)
        #expect(try Self.shot("volume", themeURL: theme).bounds(where: green) != nil)
    }

    @Test("Sitzungsmenü-Vergleich ohne Theme-Fläche: Render-Zustand sessionmenu-idle lässt die Fläche von full weg (9b-P2-6)")
    func sessionStateWithoutThemeFill() throws {
        let plain = try Self.shot("session", state: "sessionmenu-idle", theme: "full/theme.css", dark: true)
        let themed = try Self.shot("session", theme: "full/theme.css", dark: true)
        let bare = try Self.shot("session", dark: true)
        #expect(plain.size == themed.size)
        #expect(plain.pixel(8, 8).near(bare.pixel(8, 8)))
        #expect(!themed.pixel(8, 8).near(bare.pixel(8, 8)))
    }

    @Test("Launcher: Liste aus apps.all, angeheftete zuerst, oben bündig mit 46 pt Zeilenabstand")
    func launcherList() throws {
        let shot = try Self.shot("launcher", state: "launcher-empty")
        #expect(shot.size == CGSize(width: 560, height: 520))
        let safari = try #require(shot.bounds { $0.b > 180 && $0.g > 170 && $0.r < 40 })
        let finder = try #require(shot.bounds { $0.b > 230 && $0.g > 100 && $0.g < 160 && $0.r < 40 })
        #expect(abs(safari.minY - 66) <= 1 && abs(safari.minX - 18) <= 1, "\(safari) \(finder)")
        #expect(abs(finder.minY - safari.minY - 92) <= 2)
    }

    @Test("scroll mit justify-content: start füllt seinen Platz und legt den Inhalt oben an, ohne hält es sich an den Inhalt")
    func scrollFillsWithJustifyStart() throws {
        let kdl = "panel \"p\" anchor=\"left\" { column class=\"c\" { scroll class=\"s\" { stack class=\"box\" } } }"
        let base = "#p { width: 100px; height: 200px; } .c { width: 100px; height: 200px; } .box { width: 100px; height: 20px; background: rgb(255 0 0); } .s { flex-grow: 1; "
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 60 && $0.b < 60 }
        let filled = try #require(try RenderProbe.render(kdl, css: base + "justify-content: start; }").bounds(where: red))
        let hugging = try #require(try RenderProbe.render(kdl, css: base + "}").bounds(where: red))
        #expect(abs(filled.minY) <= 1)
        #expect(hugging.minY > 50)
    }

    @Test("Fixture-Abschnitt vars setzt Variablen nach on-open: Auswahl Zeile 1 wie die Referenz (9b-P2-10) und Suche ohne Treffer")
    func fixtureVars() throws {
        let fixture = ProviderFixture.parse("fixture {\n    vars launcher-selection=2 launcher-query=\"x\"\n}", file: "f.kdl")
        #expect(fixture.vars["launcher-selection"] == .number(2))
        #expect(fixture.diagnostics.isEmpty)
        let selected = try Self.shot("launcher", state: "launcher-selected-row-3")
        #expect(!selected.pixel(300, 82).near(.white, tolerance: 6))
        #expect(selected.pixel(300, 174).near(.white))
        let empty = try Self.shot("launcher", state: "launcher-no-results")
        #expect(empty.bounds { $0.b > 230 && $0.g > 100 && $0.g < 160 && $0.r < 40 } == nil)
    }

    @Test("Einführung Schritt 0: Kachel 60 pt oben bei 40 pt, Seite oben bündig in 620 × 560")
    func onboardingWelcome() throws {
        let shot = try Self.shot("onboarding", state: "onboarding-0")
        #expect(shot.size == CGSize(width: 620, height: 560))
        let tile = try #require(shot.bounds { $0.b > 200 && $0.r < 140 && $0.g < 130 && $0.b - $0.r > 100 })
        #expect(abs(tile.minY - 40) <= 1.5, "\(tile)")
        #expect(shot.pixel(310, 96).b - shot.pixel(310, 96).r > 100)
        #expect(shot.pixel(310, 104).b - shot.pixel(310, 104).r < 40)
    }

    @Test("Gestreckter Text folgt text-align: start links, center mittig, end rechts")
    func stretchedTextFollowsTextAlign() throws {
        let kdl = "panel \"p\" anchor=\"left\" { column class=\"c\" { text \"MMMM\" class=\"t\" } }"
        let base = "#p { width: 200px; height: 40px; } .c { width: 200px; height: 40px; align-items: stretch; } .t { font-size: 20px; color: rgb(255 0 0); "
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 90 && $0.b < 90 }
        let start = try #require(try RenderProbe.render(kdl, css: base + "}").bounds(where: red))
        let center = try #require(try RenderProbe.render(kdl, css: base + "text-align: center; }").bounds(where: red))
        let end = try #require(try RenderProbe.render(kdl, css: base + "text-align: end; }").bounds(where: red))
        #expect(start.minX < 6, "\(start)")
        #expect(abs(center.midX - 100) <= 2, "\(center)")
        #expect(end.maxX > 194, "\(end)")
    }

    @Test("Einführung Schritte 1–3 wie 0.1.4.2: Kachel oben bei 40 pt, Karte ab 204 pt über die Breite 44–576", arguments: [1, 2, 3])
    func onboardingSteps(step: Int) throws {
        let shot = try Self.shot("onboarding", state: "onboarding-\(step)")
        #expect(shot.size == CGSize(width: 620, height: 560))
        let tile = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 && $0.b > 150 || $0.g > 150 && $0.r < 120 && $0.b < 150 })
        #expect(abs(tile.minY - 40) <= 1.5, "\(tile)")
        #expect(!shot.pixel(60, 215).near(.white, tolerance: 4))
        #expect(shot.pixel(30, 215).near(.white, tolerance: 4))
    }

    @Test("icon: fehlt der Name im Theme und als SF-Symbol, gilt ein builtin-Fallback (blocks.md 4.1)")
    func iconFallsBackToBuiltin() throws {
        let css = "#p { width: 80px; height: 80px; } .i { font-size: 40px; color: rgb(255 0 0); }"
        let red: (RGBA) -> Bool = { $0.r > 200 && $0.g < 90 && $0.b < 90 }
        let direct = try #require(try RenderProbe.render("panel \"p\" anchor=\"left\" { icon \"builtin:bluetooth-rune\" class=\"i\" }", css: css).bounds(where: red))
        let viaFallback = try #require(try RenderProbe.render("panel \"p\" anchor=\"left\" { icon \"status-bluetooth-off\" fallback=\"builtin:bluetooth-rune\" class=\"i\" }", css: css).bounds(where: red))
        #expect(viaFallback == direct, "\(viaFallback) \(direct)")
        #expect(IconElement.builtinTarget("wifi", fallback: "builtin:bluetooth-rune") == nil)
    }

    @Test("Fixture-Abschnitt shell setzt shell-Felder im Render: Schalter der Einführung Schritt 3 aktiv wie die Referenz")
    func fixtureShell() throws {
        let fixture = ProviderFixture.parse("fixture {\n shell login-item=#false login-item-available=#true\n}", file: "f.kdl")
        #expect(fixture.shell["login-item-available"] == .bool(true))
        #expect(fixture.diagnostics.isEmpty)
        let enabled = try RenderProbe.render("panel \"p\" anchor=\"left\" { toggle checked=#false disabled=\"{!shell.login-item-available}\" }", css: "#p { width: 60px; height: 30px; }",
                                            fixture: "fixture {\n shell login-item-available=#true\n}")
        let disabled = try RenderProbe.render("panel \"p\" anchor=\"left\" { toggle checked=#false disabled=\"{!shell.login-item-available}\" }", css: "#p { width: 60px; height: 30px; }")
        #expect(enabled.count { $0.r > 250 && $0.g > 250 && $0.b > 250 } != disabled.count { $0.r > 250 && $0.g > 250 && $0.b > 250 })
    }
}
