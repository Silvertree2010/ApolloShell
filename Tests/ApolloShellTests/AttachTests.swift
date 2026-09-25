import Testing
import AppKit
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("popup attach/side: neben einem Element einer anderen Oberfläche (blocks.md 2)")
struct AttachTests {
    @Test("Geometrie je Seite, im sichtbaren Bereich gehalten")
    func geometry() {
        let rect = CGRect(x: 100, y: 500, width: 40, height: 20)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let size = CGSize(width: 200, height: 100)
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .right, offset: .zero, visible: visible) == CGRect(x: 140, y: 420, width: 200, height: 100))
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .bottom, offset: .zero, visible: visible) == CGRect(x: 100, y: 400, width: 200, height: 100))
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .top, offset: CGPoint(x: 5, y: 3), visible: visible) == CGRect(x: 105, y: 523, width: 200, height: 100))
        #expect(SurfacePlacement.attached(size: size, to: CGRect(x: 300, y: 420, width: 40, height: 100), side: .left, offset: CGPoint(x: 10, y: 0), visible: visible).minX == 90)
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .right, offset: CGPoint(x: 10, y: 0), visible: visible).minX == 150)
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .bottom, offset: CGPoint(x: 0, y: 10), visible: visible).minY == 390)
        #expect(SurfacePlacement.attached(size: size, to: rect, side: .left, offset: .zero, visible: visible).minX == 0)
    }

    @Test("Host setzt das Popup an den gemeldeten Element-Rahmen und folgt ihm")
    func followsElement() throws {
        let fixture = try HostFixture("""
        panel "bar" anchor="top" { row { text "a" id="clock" } }
        popup "menu" attach="bar#clock" side="bottom" { column { text "m" } }
        """)
        fixture.assembly.runtime.open("menu", screenKey: nil)
        fixture.flush()
        let bar = try #require(fixture.window("bar")), menu = try #require(fixture.window("menu"))
        let context = try #require(fixture.host.context)
        context.elementFrames.update(["clock": CGRect(x: 10, y: 5, width: 40, height: 20)], surfaceKey: SurfaceHost.key("bar", HostFixture.screen.key))
        fixture.flush()
        #expect(menu.frame.minX == bar.frame.minX + 10)
        #expect(menu.frame.maxY == bar.frame.maxY - 25)
        context.elementFrames.update(["clock": CGRect(x: 300, y: 5, width: 40, height: 20)], surfaceKey: SurfaceHost.key("bar", HostFixture.screen.key))
        fixture.flush()
        #expect(menu.frame.minX == bar.frame.minX + 300)
    }
}
