import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: berechnete Stile", .serialized)
struct StyleRenderTests {
    func box(_ css: String, children: String = "stack class=\"a\"") throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(children)\n}", css: "#t { width: 100px; height: 60px; align-items: start; }\n" + css)
    }

    @Test("Breite, Höhe, Hintergrundfarbe, margin")
    func sizeAndMargin() throws {
        let shot = try box(".a { width: 40px; height: 20px; margin: 5px 0 0 10px; background: #ff0000; }")
        #expect(shot.size == CGSize(width: 100, height: 60))
        let red = try #require(shot.bounds { $0.near(.red) })
        #expect(red == CGRect(x: 10, y: 5, width: 40, height: 20))
    }

    @Test("padding vergrössert die Fläche um den Inhalt")
    func padding() throws {
        let shot = try box(".a { padding: 4px; background: #0000ff; } .b { width: 10px; height: 10px; background: #ff0000; }",
                           children: "stack class=\"a\" { stack class=\"b\" }")
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 0, y: 0, width: 18, height: 18))
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 4, y: 4, width: 10, height: 10))
    }

    @Test("padding-left und margin-top wirken wie die Kurzform")
    func sideLonghands() throws {
        let shot = try box(".a { padding: 4px; padding-left: 8px; margin-top: 3px; background: #0000ff; } .b { width: 10px; height: 10px; background: #ff0000; }",
                           children: "stack class=\"a\" { stack class=\"b\" }")
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 0, y: 3, width: 22, height: 18))
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 8, y: 7, width: 10, height: 10))
    }

    @Test("row: flex-grow teilt den Rest, Prozentbreite vom Elternelement")
    func flex() throws {
        let shot = try box("""
            .r { width: 100px; height: 10px; }
            .f { flex-grow: 1; height: 10px; background: #ff0000; }
            .p { width: 50%; height: 10px; background: #0000ff; }
            .x { width: 10px; height: 10px; background: #00ff00; }
            """, children: "row class=\"r\" { stack class=\"p\"; stack class=\"f\"; stack class=\"x\" }")
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 0, y: 0, width: 50, height: 10))
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 50, y: 0, width: 40, height: 10))
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 90, y: 0, width: 10, height: 10))
    }

    @Test("justify-content und align-items in column")
    func justify() throws {
        let shot = try box("""
            .c { width: 100px; height: 60px; justify-content: end; align-items: end; }
            .x { width: 10px; height: 10px; background: #00ff00; }
            """, children: "column class=\"c\" { stack class=\"x\" }")
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 90, y: 50, width: 10, height: 10))
    }

    @Test("space-between verteilt den Rest zwischen die Kinder")
    func spaceBetween() throws {
        let shot = try box("""
            .r { width: 100px; justify-content: space-between; }
            .x { width: 10px; height: 10px; background: #00ff00; }
            """, children: "row class=\"r\" { stack class=\"x\"; stack class=\"x\" }")
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 0, y: 0, width: 100, height: 10))
        #expect(shot.pixel(50, 5) == .white)
    }

    @Test("Radius lässt die Ecke frei, Rahmen zeichnet die Kante")
    func radiusAndBorder() throws {
        let shot = try box(".a { width: 40px; height: 40px; border-radius: 20px; background: #ff0000; border: 2px solid #0000ff; }")
        #expect(shot.pixel(1, 1) == .white)
        #expect(shot.pixel(20, 20).near(.red))
        #expect(shot.pixel(20, 1).near(.blue, tolerance: 40))
    }

    @Test("opacity und Verlauf")
    func opacityAndGradient() throws {
        let shot = try box("""
            .a { width: 40px; height: 20px; background: #000000; opacity: 0.5; }
            .g { width: 40px; height: 20px; background: linear-gradient(90deg, #ff0000, #0000ff); }
            """, children: "stack class=\"a\"\nstack class=\"g\"")
        let half = shot.pixel(20, 10)
        #expect(abs(half.r - 128) <= 3)
        let left = shot.pixel(1, 30), right = shot.pixel(39, 30)
        #expect(left.r > 200 && left.b < 60)
        #expect(right.b > 200 && right.r < 60)
    }

    @Test("transform verschiebt, overflow: hidden schneidet ab")
    func transformAndClip() throws {
        let shot = try box("""
            .a { width: 20px; height: 20px; overflow: hidden; background: #0000ff; }
            .b { width: 40px; height: 10px; background: #ff0000; transform: translate(10px, 0); }
            """, children: "stack class=\"a\" { stack class=\"b\" }")
        #expect(shot.bounds { $0.near(.red) }?.maxX == 20)
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test("box-shadow liegt ausserhalb der Fläche")
    func shadow() throws {
        let shot = try box(".a { width: 20px; height: 20px; margin: 10px; background: #ffffff; box-shadow: 4px 4px 0 #000000; }")
        #expect(shot.pixel(32, 32).near(.black, tolerance: 30))
        #expect(shot.pixel(20, 20) == .white)
    }

    @Test("z-index legt ein Kind im stack nach oben")
    func zIndex() throws {
        let shot = try box("""
            .a { width: 20px; height: 20px; }
            .top { width: 20px; height: 20px; background: #ff0000; z-index: 2; }
            .under { width: 20px; height: 20px; background: #0000ff; }
            """, children: "stack class=\"a\" { stack class=\"top\"; stack class=\"under\" }")
        #expect(shot.pixel(10, 10).near(.red))
    }

    @Test("url() zeichnet ein Bild aus dem Config-Ordner")
    func image() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let shot = try RenderProbe.render("panel \"t\" anchor=\"left\" { stack class=\"a\" }",
                                          css: "#t { width: 30px; height: 30px; } .a { width: 20px; height: 20px; background: url(\"img/g.png\"); }",
                                          files: ["img/g.png": png])
        #expect(shot.pixel(10, 10).near(.green, tolerance: 30))
    }

    @Test("Glas im Render-Modus: Stand-in wie SidebarRoot 0.1.4.2 (weiss 0,95 hell, 0,17 dunkel), per --render-glass: clear leer")
    func glassStandIn() throws {
        let kdl = "panel \"t\" anchor=\"left\" { stack class=\"g\" }"
        let css = "#t { width: 40px; height: 40px; } .g { width: 40px; height: 40px; background: glass(regular); }"
        let light = try RenderProbe.render(kdl, css: css)
        let dark = try RenderProbe.render(kdl, css: css, dark: true)
        #expect(light.pixel(20, 20).near(RGBA(r: 242, g: 242, b: 242, a: 255), tolerance: 1), "\(light.pixel(20, 20))")
        #expect(dark.pixel(20, 20).near(RGBA(r: 43, g: 43, b: 43, a: 255), tolerance: 1), "\(dark.pixel(20, 20))")
        let clear = try RenderProbe.render(kdl, css: css + " .g { --render-glass: clear; }")
        #expect(clear.pixel(20, 20) == .white, "\(clear.pixel(20, 20))")
    }
}
