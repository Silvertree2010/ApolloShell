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

    @Test("Leiste: 48 pt breit, aktiver Schreibtisch als Kapsel im Akzent")
    func barSpaces() throws {
        let shot = try Self.shot("bar")
        #expect(abs(shot.size.width - 48) <= 1)
        let tinted = { (c: RGBA) in max(c.r, c.g, c.b) - min(c.r, c.g, c.b) > 80 }
        let mark = try #require(shot.bounds(where: tinted))
        #expect(mark.minX > 14 && mark.maxX < 34, "\(mark)")
    }

    @Test("Desktop-Uhr: grosse Zeit über dem Datum")
    func desktopClock() throws {
        let shot = try Self.shot("clock")
        #expect(abs(shot.size.width - 276) <= 6)
        #expect(abs(shot.size.height - 137) <= 6)
    }

    @Test("OSD: senkrechter Regler 34 pt breit am rechten Rand, Füllung unten bei 0,35")
    func osd() throws {
        let shot = try Self.shot("osd", state: "g2-osd")
        #expect(abs(shot.size.width - 58) <= 1 && abs(shot.size.height - 226) <= 2)
        let track = try #require(shot.bounds { $0.r < 235 && $0.r > 200 })
        #expect(abs(track.width - 34) <= 1, "\(track)")
        #expect(shot.pixel(29, 160).near(.white))
        #expect(!shot.pixel(29, 40).near(.white))
    }

    @Test("OSD stumm oder bei 0: Füllung nur so lang wie die Spur breit", arguments: ["osd-muted", "osd-0"])
    func osdMuted(state: String) throws {
        let shot = try Self.shot("osd", state: state)
        let grey = { (c: RGBA) in c.r > 215 && c.r < 232 && abs(Int(c.r) - Int(c.b)) < 3 }
        let empty = shot.count(where: grey)
        let normal = try Self.shot("osd", state: "g2-osd").count(where: grey)
        #expect(empty > normal + 34 * 30, "\(empty) \(normal)")
    }

    @Test("Sitzungsmenü: Schublade am rechten Rand, gewählte Kachel im Akzent")
    func session() throws {
        let shot = try Self.shot("sess", state: "g2-sess")
        #expect(abs(shot.size.width - 105) <= 2 && abs(shot.size.height - 640) <= 2, "\(shot.size)")
        let selected = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 80 })
        #expect(selected.width > 70 && selected.width < 86, "\(selected)")
        #expect(selected.minY > 380 && selected.maxY < 520, "\(selected)")
    }

    @Test("Sitzungsmenü und OSD folgen dem Akzent eines Themes")
    func sessionFollowsThemeAccent() throws {
        let source = try String(contentsOf: PackageResources.root.appendingPathComponent("examples/themes/minimal.css"), encoding: .utf8)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("emblem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let theme = folder.appendingPathComponent("green.css")
        try source.replacingOccurrences(of: "#ff6b35", with: "#00ff00").replacingOccurrences(of: "#ff8354", with: "#00ff00")
            .write(to: theme, atomically: true, encoding: .utf8)
        let green: (RGBA) -> Bool = { $0.g > 200 && $0.r < 80 && $0.b < 80 }
        #expect(try Self.shot("sess", state: "g2-sess", themeURL: theme).bounds(where: green) != nil)
        #expect(try Self.shot("sess", state: "g2-sess").bounds(where: green) == nil)
    }

    @Test("Sitzungsmenü: ein Theme mit Panel-Farbe färbt die Schublade, ohne Theme bleibt Glas")
    func sessionThemeFill() throws {
        let themed = try Self.shot("sess", state: "g2-sess", theme: "full/theme.css", dark: true)
        let bare = try Self.shot("sess", state: "g2-sess", dark: true)
        #expect(themed.size == bare.size)
        #expect(!themed.pixel(52, 300).near(bare.pixel(52, 300)))
    }

    @Test("Launcher: Liste aus apps.all über dem Suchfeld, Zeilen 58 pt")
    func launcherList() throws {
        let shot = try Self.shot("launcher", state: "g2-launcher")
        #expect(abs(shot.size.width - 760) <= 2)
        let safari = try #require(shot.bounds { $0.b > 180 && $0.g > 170 && $0.r < 40 })
        #expect(abs(safari.minX - 90) <= 2 && abs(safari.width - 38) <= 2, "\(safari)")
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

    @Test("Fixture-Abschnitt vars setzt Variablen nach on-open: Auswahl Zeile 3 und Suche ohne Treffer")
    func fixtureVars() throws {
        let fixture = ProviderFixture.parse("fixture {\n    vars sel=2 q=\"x\"\n}", file: "f.kdl")
        #expect(fixture.vars["sel"] == .number(2))
        #expect(fixture.diagnostics.isEmpty)
        let first = try Self.shot("launcher", state: "g2-launcher")
        let third = try Self.shot("launcher", state: "g2-launcher-sel")
        #expect(!first.pixel(400, 40).near(third.pixel(400, 40)))
        #expect(!first.pixel(400, 155).near(third.pixel(400, 155)))
        let empty = try Self.shot("launcher", state: "g2-launcher-none")
        #expect(empty.bounds { $0.b > 180 && $0.g > 170 && $0.r < 40 } == nil)
    }

    @Test("Einführung: Fenster 520 × 480")
    func onboardingWelcome() throws {
        let shot = try Self.shot("ob")
        #expect(abs(shot.size.width - 520) <= 2 && abs(shot.size.height - 480) <= 2)
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

    @Test("Einführung Schritte 1–3 behalten die Fenstergrösse", arguments: [1, 2, 3])
    func onboardingSteps(step: Int) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "include \"builtin:apolloshell-default/shell.kdl\"".write(to: folder.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        let base = try String(contentsOf: Self.resources.appendingPathComponent("render/fixture.kdl"), encoding: .utf8)
        let end = try #require(base.range(of: "}", options: .backwards))
        try (base[..<end.lowerBound] + "    vars obs=\(step)\n}\n").write(to: folder.appendingPathComponent("fixture.kdl"), atomically: true, encoding: .utf8)
        let fixture = folder.appendingPathComponent("fixture.kdl")
        let session = try RenderSession(config: folder, resources: Self.resources, fixture: ProviderFixture.load(fixture), fixtureRoot: folder, dark: false, scale: 1, theme: nil)
        let surface = try #require(session.surface("ob"))
        let shot = Snapshot(rep: try #require(NSBitmapImageRep(data: try session.capture(surface, name: "ob"))), scale: 1)
        #expect(abs(shot.size.width - 520) <= 2 && abs(shot.size.height - 480) <= 2)
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
