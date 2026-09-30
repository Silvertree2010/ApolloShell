import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: Engine-Lücken", .serialized)
struct EngineGapTests {
    func box(_ css: String, children: String) throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(children)\n}", css: "#t { width: 100px; height: 60px; align-items: start; }\n" + css)
    }

    @Test("margin an Kindern eines stack verschiebt sie gegen die Kante und in der Mitte")
    func stackChildMargin() throws {
        let p = "#t { width: 100px; height: 100px; } .p { width: 80px; height: 80px; } .h { width: 4px; height: 40px; background: #ff0000; }"
        let top = try box(p, children: "stack class=\"p\" { stack class=\"h\" style=\"margin: 5px 0 0 10px; align-self: start; justify-self: start\" }")
        #expect(top.bounds { $0.near(.red) } == CGRect(x: 10, y: 5, width: 4, height: 40))
        let below = try box(p, children: "stack class=\"p\" { stack class=\"h\" style=\"margin-top: 40px\" }")
        #expect(below.bounds { $0.near(.red) } == CGRect(x: 38, y: 40, width: 4, height: 40))
        let above = try box(p, children: "stack class=\"p\" { stack class=\"h\" style=\"margin-bottom: 40px\" }")
        #expect(above.bounds { $0.near(.red) } == CGRect(x: 38, y: 0, width: 4, height: 40))
        let end = try box(p, children: "stack class=\"p\" { stack class=\"h\" style=\"margin: 0 10px 10px 0; align-self: end; justify-self: end\" }")
        #expect(end.bounds { $0.near(.red) } == CGRect(x: 66, y: 30, width: 4, height: 40))
    }

    @Test("border-radius 9999px wird auf die halbe kürzere Seite begrenzt")
    func hugeRadius() throws {
        let css = "#t { width: 120px; height: 120px; } .a { width: 90px; height: 90px; border-radius: 9999px; background: #ff0000; } .b { width: 90px; height: 40px; border-radius: 9999px; background: #0000ff; }"
        let circle = try box(css, children: "stack class=\"a\"")
        #expect(!circle.pixel(3, 3).near(.red))
        #expect(circle.pixel(45, 45).near(.red))
        #expect(circle.pixel(45, 2).near(.red))
        let pill = try box(css, children: "stack class=\"b\"")
        #expect(!pill.pixel(3, 3).near(.blue))
        #expect(pill.pixel(45, 20).near(.blue))
        #expect(pill.pixel(25, 1).near(.blue))
    }

    func cascade(_ kdl: String, _ files: [String: String]) throws -> Snapshot {
        try RenderProbe.render(kdl, css: "", files: files.mapValues { Data($0.utf8) })
    }

    @Test("gleiche Spezifität: die später eingebundene Datei gewinnt, eine früher eingebundene verliert")
    func includeOrder() throws {
        let panel = "panel \"t\" anchor=\"left\" { stack class=\"card\" }\n"
        let early = try cascade("include \"w.kdl\"\nstyle \"late.css\"\n" + panel, [
            "w.kdl": "style \"w.css\"\n", "w.css": ".card { width: 20px; height: 20px; background: #0000ff; }",
            "late.css": ".card { background: #ff0000; }",
        ])
        #expect(early.pixel(10, 10).near(.red))
        let late = try cascade("style \"first.css\"\ninclude \"w.kdl\"\n" + panel, [
            "w.kdl": "style \"w.css\"\n", "w.css": ".card { width: 20px; height: 20px; background: #0000ff; }",
            "first.css": ".card { background: #ff0000; }",
        ])
        #expect(late.pixel(10, 10).near(.blue))
    }
}
