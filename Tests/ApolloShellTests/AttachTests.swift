import Testing
import AppKit
import SwiftUI
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

    @Test("align=center mittig unter dem Element, CSS-margin haelt Abstand zum Bildschirmrand")
    func alignAndMargin() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 744)
        let size = CGSize(width: 380, height: 300)
        let item = CGRect(x: 500, y: 744, width: 24, height: 24)
        #expect(SurfacePlacement.attached(size: size, to: item, side: .bottom, align: .center, offset: CGPoint(x: 0, y: 6), visible: visible) == CGRect(x: 322, y: 438, width: 380, height: 300))
        #expect(SurfacePlacement.attached(size: size, to: item, side: .bottom, align: .end, offset: .zero, visible: visible).maxX == 524)
        let edge = CGRect(x: 980, y: 744, width: 24, height: 24)
        let margin = SwiftUI.EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        #expect(SurfacePlacement.attached(size: size, to: edge, side: .bottom, align: .center, offset: .zero, visible: visible, margin: margin).maxX == 1018)
        #expect(SurfacePlacement.attached(size: size, to: edge, side: .bottom, align: .center, offset: .zero, visible: visible).maxX == 1024)
        #expect(SurfacePlacement.attached(size: CGSize(width: 100, height: 40), to: CGRect(x: 0, y: 300, width: 40, height: 100), side: .right, align: .center, offset: .zero, visible: visible).midY == 350)
        let attach = SurfacePlacement.attachment { name in
            switch name {
            case "attach": .string("item#mark")
            case "side": .string("bottom")
            case "align": .string("center")
            default: .null
            }
        }
        #expect(attach == SurfacePlacement.Attachment(surface: "item", element: "mark", side: .bottom, align: .center))
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

    @Test("Eigenes Statussymbol aus einer status-item-Oberflaeche: Rahmen und angehaengtes Popup")
    func ownStatusItemSurface() throws {
        let fixture = try HostFixture("""
        status-item "nexus-item" { button id="mark" { text "A" } }
        popup "nexus" attach="nexus-item#mark" side="bottom" align="center" { column { text "m" } }
        popup "other" { column { text "o" } }
        """)
        fixture.flush()
        let own = try #require(fixture.host.ownStatusItem())
        #expect(own.id == "nexus-item")
        #expect(own.frame == fixture.window("nexus-item")?.frame)
        #expect(fixture.host.popups(attachedTo: "nexus-item") == ["nexus"])
        #expect(fixture.host.popups(attachedTo: "other").isEmpty)
    }
}
