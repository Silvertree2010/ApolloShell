import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: gestreckte Container mit justify-content: start", .serialized)
struct StretchStartTests {
    func box(_ css: String, children: String) throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(children)\n}", css: "#t { width: 100px; height: 60px; }\n" + css)
    }

    @Test("gestreckte row legt ihren Inhalt an den Anfang")
    func row() throws {
        let shot = try box(".r { background: #0000ff; } .x { width: 10px; height: 10px; background: #00ff00; }",
                           children: "column { row class=\"r\" { stack class=\"x\" } }")
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 10, y: 0, width: 90, height: 10))
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("gestreckte column in row legt ihren Inhalt nach oben")
    func column() throws {
        let shot = try box(".c { background: #0000ff; } .x { width: 10px; height: 10px; background: #00ff00; } .s { width: 10px; height: 60px; }",
                           children: "row style=\"height: 60px\" { stack class=\"s\"; column class=\"c\" { stack class=\"x\" } }")
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 10, y: 0, width: 10, height: 10))
    }

    @Test("gestreckter stack: align-self: start greift am Rand der Fläche")
    func stack() throws {
        let shot = try box(".s { background: #0000ff; } .x { width: 10px; height: 10px; background: #00ff00; align-self: start; }",
                           children: "column { stack class=\"s\" { stack class=\"x\" } }")
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("gestreckter button: Inhalt bleibt in der Mitte der vollen Breite")
    func button() throws {
        let shot = try box(".x { width: 10px; height: 10px; background: #00ff00; }",
                           children: "column { button { stack class=\"x\" } }")
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 45, y: 0, width: 10, height: 10))
    }
}
