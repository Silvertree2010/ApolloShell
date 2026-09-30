import Testing
import Foundation
import AppKit
@testable import ApolloShell
@testable import ApolloConfig

@MainActor
@Suite("Render: canvas", .serialized)
struct CanvasRenderTests {
    static let items = """
    var items {
        - id="a" x=0 y=0 width=20 height=20 color="#ff0000"
        - id="b" x=40 y=10 width=20 height=20 color="#0000ff"
    }
    """

    func shot(_ scale: Double) throws -> Snapshot {
        try RenderProbe.render(Self.items + """

        panel "t" anchor="left" {
            canvas scale=\(scale) class="c" {
                each item in="{var.items}" key="{item.id}" {
                    stack style="background: {item.color};"
                }
            }
        }
        """, css: "#t { width: 140px; height: 80px; align-items: start; justify-content: start; }")
    }

    @Test("Kinder stehen an x, y, width, height ihres Eintrags")
    func places() throws {
        let one = try shot(1)
        #expect(one.pixel(10, 10).near(.red, tolerance: 40))
        #expect(one.pixel(50, 20).near(.blue, tolerance: 40))
        #expect(!one.pixel(30, 10).near(.red, tolerance: 40))
        #expect(!one.pixel(50, 5).near(.blue, tolerance: 40))
    }

    @Test("scale vergrössert Rahmen und Lage")
    func scales() throws {
        let two = try shot(2)
        #expect(two.pixel(35, 35).near(.red, tolerance: 40))
        #expect(two.pixel(100, 40).near(.blue, tolerance: 40))
        #expect(!two.pixel(50, 10).near(.red, tolerance: 40))
    }

    @Test("Ziehen rastet ein, markiert :invalid und federt ohne Übernahme zurück")
    func dragging() throws {
        let (session, _) = try RenderProbe.session(Self.items + """

        panel "t" anchor="left" {
            canvas enabled=#true gap=12 snap=8 class="c" {
                each item in="{var.items}" key="{item.id}" {
                    stack
                }
            }
        }
        """, css: ".c { width: 100px; height: 40px; }")
        let surface = try #require(session.surfaces.first)
        let container = surface.root[0]
        let canvas = session.context.canvas(for: container)
        canvas.pageSize = CGSize(width: 100, height: 40)
        let b = Value.string("b")
        canvas.drag(b, dx: -5, dy: -8, resize: false, ended: false)
        #expect(canvas.live[b]?.frame == CanvasFrame(x: 32, y: 0, width: 20, height: 20))
        #expect(canvas.live[b]?.valid == true)
        canvas.drag(b, dx: -30, dy: 0, resize: false, ended: false)
        #expect(canvas.live[b]?.valid == false)
        #expect(container.children[1].pseudo.contains(.invalid))
        canvas.drag(b, dx: -30, dy: 0, resize: false, ended: true)
        #expect(canvas.live[b] == nil)
        #expect(!container.children[1].pseudo.contains(.invalid))
        canvas.drag(b, dx: 30, dy: 0, resize: true, ended: false)
        #expect(canvas.live[b]?.frame.width == 50)
    }
}
