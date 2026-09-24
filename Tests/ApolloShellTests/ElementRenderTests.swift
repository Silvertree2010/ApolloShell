import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: Elemente aus blocks.md 3 und 4.1", .serialized)
struct ElementRenderTests {
    func panel(_ children: String, _ css: String = "", size: String = "width: 120px; height: 60px;", files: [String: Data] = [:]) throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(children)\n}", css: "#t { \(size) align-items: start; }\n" + css, files: files)
    }

    static func png(_ color: NSColor, size: CGFloat = 4) -> Data {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    @Test("text zeichnet in color, font-size vergrössert")
    func text() throws {
        let small = try panel("text \"Hello\" class=\"a\"", ".a { color: #ff0000; font-size: 13px; }")
        let large = try panel("text \"Hello\" class=\"a\"", ".a { color: #ff0000; font-size: 26px; }")
        let a = try #require(small.ink()), b = try #require(large.ink())
        #expect(b.width > a.width * 1.7)
        #expect(small.count { $0.r > 200 && $0.g < 80 && $0.b < 80 } > 10)
    }

    @Test("text lines=1 schneidet ab, lines=0 bricht um")
    func lines() throws {
        let long = String(repeating: "word ", count: 20)
        let one = try panel("text \"\(long)\" class=\"a\"", ".a { width: 100px; }", size: "width: 120px; height: 120px;")
        let many = try panel("text \"\(long)\" class=\"a\" lines=0", ".a { width: 100px; }", size: "width: 120px; height: 120px;")
        let manyInk = try #require(many.ink()), oneInk = try #require(one.ink())
        #expect(manyInk.height > oneInk.height * 2)
    }

    @Test("icon: SF-Symbol in color, fallback bei unbekanntem Namen, builtin")
    func icon() throws {
        let symbol = try panel("icon \"star.fill\" class=\"i\"", ".i { color: #0000ff; font-size: 20px; }")
        #expect(symbol.count { $0.near(.blue, tolerance: 40) } > 20)
        let fallback = try panel("icon \"no-such-icon\" fallback=\"star.fill\" class=\"i\"", ".i { color: #0000ff; font-size: 20px; }")
        #expect(fallback.count { $0.near(.blue, tolerance: 40) } == symbol.count { $0.near(.blue, tolerance: 40) })
        for name in ["builtin:bluetooth-rune", "builtin:apollo-mark", "builtin:file-manager-folder"] {
            let shot = try panel("icon \"\(name)\" class=\"i\"", ".i { color: #0000ff; font-size: 20px; }")
            #expect(shot.ink() != nil, "\(name)")
        }
    }

    @Test("image aus dem Config-Ordner, Platzhalter sonst")
    func image() throws {
        let shot = try panel("image \"img/g.png\" class=\"m\"", ".m { width: 20px; height: 20px; }",
                             files: ["img/g.png": Self.png(NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))])
        #expect(shot.pixel(10, 10).near(.green, tolerance: 30))
        let missing = try panel("image \"img/none.png\" placeholder=\"star.fill\" class=\"m\"", ".m { width: 20px; height: 20px; color: #0000ff; }")
        #expect(missing.count { $0.near(.blue, tolerance: 40) } > 10)
    }

    @Test("shape circle und scallop füllen ihre Form")
    func shape() throws {
        let circle = try panel("shape \"circle\" class=\"s\"", ".s { width: 40px; height: 40px; background: #ff0000; }")
        #expect(circle.pixel(20, 20).near(.red))
        #expect(circle.pixel(2, 2) == .white)
        let square = try panel("stack class=\"s\"", ".s { width: 40px; height: 40px; background: #ff0000; }")
        let scallop = try panel("shape \"scallop\" count=8 depth=0.3 class=\"s\"", ".s { width: 40px; height: 40px; background: #ff0000; }")
        let red: (RGBA) -> Bool = { $0.near(.red) }
        #expect(scallop.count(where: red) < circle.count(where: red))
        #expect(circle.count(where: red) < square.count(where: red))
    }

    @Test("spacer schiebt das nächste Kind ans Ende, size= ist fest")
    func spacer() throws {
        let css = ".r { width: 100px; } .x { width: 10px; height: 10px; background: #00ff00; }"
        let grow = try panel("row class=\"r\" { spacer; stack class=\"x\" }", css)
        #expect(grow.bounds { $0.near(.green) } == CGRect(x: 90, y: 0, width: 10, height: 10))
        let fixed = try panel("row class=\"r\" { spacer size=30; stack class=\"x\" }", css)
        #expect(fixed.bounds { $0.near(.green) } == CGRect(x: 30, y: 0, width: 10, height: 10))
    }

    @Test("grid mit columns und span")
    func grid() throws {
        let shot = try panel("""
            grid class="g" columns=2 {
                stack class="a"
                stack class="b"
                stack class="c"
            }
            """, """
            .g { width: 100px; gap: 10px; }
            .a { height: 10px; background: #ff0000; }
            .b { height: 10px; background: #0000ff; }
            .c { height: 10px; background: #00ff00; grid-column: span 2; }
            """)
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 0, y: 0, width: 45, height: 10))
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 55, y: 0, width: 45, height: 10))
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 0, y: 20, width: 100, height: 10))
    }

    @Test("app-icon zeichnet das Fixture-Symbol mit Plakette")
    func appIcon() throws {
        let shot = try panel("app-icon \"com.apple.Safari\" badge=\"2\" class=\"i\"",
                             ".i { width: 30px; height: 30px; margin: 10px; -apollo-badge-color: #0000ff; -apollo-badge-offset: 4px -4px; }")
        #expect(shot.pixel(25, 25).near(RGBA(r: 0, g: 200, b: 210, a: 255), tolerance: 80))
        let badge = try #require(shot.bounds { $0.near(.blue, tolerance: 30) })
        #expect(badge.maxX > 40)
    }

    @Test("theme-preview und mark zeichnen etwas")
    func previewAndMark() throws {
        let preview = try panel("theme-preview theme=\"default\" class=\"p\"", ".p { width: 96px; height: 60px; }", size: "width: 100px; height: 64px;")
        #expect(try #require(preview.ink()).width > 80)
        let mark = try panel("mark class=\"m\" color=\"#ff0000\"", ".m { width: 50px; height: 50px; }")
        #expect(mark.count { $0.r > 180 && $0.g < 120 && $0.b < 120 } > 20)
    }

    @Test("mark state folgt einem Ausdruck ohne Neuaufbau (Entscheid 9b-1)")
    func markStateExpression() async throws {
        let mounted = try Mounted.mount("""
        var mood "idle"
        panel "t" anchor="left" { mark id="m" state="{var.mood}" class="m" }
        """, css: "#t { width: 60px; height: 60px; } .m { width: 50px; height: 50px; }")
        let surface = try #require(mounted.session.surfaces.first)
        let mark = try #require(surface.root.first)
        #expect(mark.property("state") == .string("idle"))
        mounted.session.context.runtime?.setVariable("mood", .string("sleep"))
        await mounted.settle()
        let after = try #require(mounted.session.surfaces.first?.root.first)
        #expect(after === mark)
        #expect(mark.property("state") == .string("sleep"))
    }

    @Test("mark state wechselt das gezeichnete Emblem, ohne das Element neu aufzubauen")
    func markStateDrawn() async throws {
        let config = """
        var mood "idle"
        var appeared 0
        panel "t" anchor="left" { mark id="m" state="{var.mood}" greet=#false class="m" color="#ff0000" { on-appear { set "appeared" "{var.appeared + 1}" } } }
        """
        let css = "#t { width: 60px; height: 60px; background: #ffffff; } .m { width: 50px; height: 50px; }"
        let mounted = try Mounted.mount(config, css: css)
        let canvas = mounted.session.canvas
        let before = try canvas.snapshot(mounted.view, name: "idle")
        mounted.session.context.runtime?.setVariable("mood", .string("sleep"))
        await mounted.settle()
        mounted.pump()
        let after = try canvas.snapshot(mounted.view, name: "sleep")
        let reference = try Mounted.mount(config.replacingOccurrences(of: "var mood \"idle\"", with: "var mood \"sleep\""), css: css)
        let fresh = try reference.session.canvas.snapshot(reference.view, name: "fresh")
        let shots = try [before, after, fresh].map { Snapshot(rep: try #require(NSBitmapImageRep(data: $0)), scale: 1) }
        func differing(_ a: Snapshot, _ b: Snapshot) -> Int {
            var count = 0
            for y in 0..<60 { for x in 0..<60 where !a.pixel(CGFloat(x), CGFloat(y)).near(b.pixel(CGFloat(x), CGFloat(y)), tolerance: 24) { count += 1 } }
            return count
        }
        let changed = differing(shots[0], shots[1])
        #expect(changed > 200)
        #expect(differing(shots[1], shots[2]) * 10 < changed)
        #expect(mounted.variable("appeared") == .number(1))
    }

    @Test("Fixture liefert die Werte, die 0.1.4.2 zeigt (Benutzer, Laufzeit, macOS, Chip, Kerne)")
    func fixtureSystemValues() throws {
        let mounted = try Mounted.mount("""
        panel "t" anchor="left" { text "{system.user-name}|{system.uptime}|{system.macos-version}|{system.chip}|{perf.chip}|{perf.cores}|{perf.gpu-cores}" }
        """, css: "#t { width: 200px; height: 20px; }")
        let text = try #require(mounted.session.surfaces.first?.root.first)
        #expect(text.arguments.first?.value.stringified == "Andrin Example|11520|26.6.2|Apple M4 Pro|Apple M4 Pro|14|20")
    }
}
