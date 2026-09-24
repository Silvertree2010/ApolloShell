import Testing
import AppKit
import SwiftUI
import ApolloConfig
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Lage der Oberflächen-Fenster")
struct SurfacePlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)

    @Test("Bezugsrechtecke full, below-menubar, visible")
    func areas() {
        #expect(SurfacePlacement.areaRect(.full, frame: screen, visible: visible) == screen)
        #expect(SurfacePlacement.areaRect(.belowMenubar, frame: screen, visible: visible) == CGRect(x: 0, y: 0, width: 1440, height: 870))
        #expect(SurfacePlacement.areaRect(.visible, frame: screen, visible: visible) == visible)
    }

    @Test("Dock links, 44×300, senkrecht mittig unter der Menüleiste")
    func dockLeft() {
        let placement = SurfacePlacement(anchor: .left, width: CSSLength(44, .points), height: CSSLength(300, .points))
        #expect(placement.frame(screen: screen, visible: visible, fitting: .zero) == CGRect(x: 0, y: 285, width: 44, height: 300))
    }

    @Test("Prozent vom Bezugsrechteck, Rand und Versatz von der Kante weg")
    func percentMarginOffset() {
        let placement = SurfacePlacement(anchor: .right, width: CSSLength(10, .percent), height: CSSLength(100, .percent),
                                         margin: EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 8), offsetX: 2)
        #expect(placement.frame(screen: screen, visible: visible, fitting: .zero) == CGRect(x: 1286, y: 1, width: 144, height: 870))
    }

    @Test("Ecken, fill und Grösse aus dem Inhalt")
    func cornersFillFitting() {
        let top = SurfacePlacement(anchor: .topLeft, area: .full, offsetY: 10)
        #expect(top.frame(screen: screen, visible: visible, fitting: CGSize(width: 50, height: 20)) == CGRect(x: 0, y: 870, width: 50, height: 20))
        let bottom = SurfacePlacement(anchor: .bottomRight, area: .visible)
        #expect(bottom.frame(screen: screen, visible: visible, fitting: CGSize(width: 50, height: 20)) == CGRect(x: 1390, y: 70, width: 50, height: 20))
        let fill = SurfacePlacement(anchor: .fill, area: .full, margin: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        #expect(fill.frame(screen: screen, visible: visible, fitting: .zero) == CGRect(x: 2, y: 3, width: 1434, height: 896))
    }

    @Test("Properties und Stil der Dock-Oberfläche ergeben die Lage")
    func fromDockSurface() throws {
        let (_, surface) = try DockSlice.build()
        let ir = try #require(ConfigSource.load(PackageResources.dockRender, builtinConfigs: PackageResources.configs, id: "render-dock").ir)
        let resolver = StyleResolver(sheets: StyleSheets.load(ir).0, environment: StyleSheets.environment(dark: false))
        let style = resolver.resolve(StyleResolver.subject(for: surface), ancestors: [], parent: nil)
        let placement = SurfacePlacement(property: surface.property, style: style)
        #expect(placement == SurfacePlacement(anchor: .left, width: CSSLength(44, .points), height: CSSLength(300, .points)))
        #expect(surface.isVisible)
        #expect(SurfaceWindowSpec(surface: surface).sticky)
    }

    @Test("Ebene und Collection Behavior je Art nach blocks.md 2.8/2.9")
    func levels() {
        #expect(SurfaceWindowKind.level(nil, kind: "panel") == .floating)
        #expect(SurfaceWindowKind.level("status", kind: "panel") == .statusBar)
        #expect(SurfaceWindowKind.level(nil, kind: "overlay").rawValue == NSWindow.Level.popUpMenu.rawValue + 2)
        #expect(SurfaceWindowKind.behavior(kind: "panel") == [.canJoinAllSpaces, .stationary, .ignoresCycle])
        #expect(SurfaceWindowKind.behavior(kind: "toast") == [.canJoinAllSpaces, .transient, .ignoresCycle])
    }

    @Test("Start-Optionen: ohne --config aktive Config aus settings.kdl, Ressourcen im Bundle")
    func launchOptions() {
        let exe = URL(fileURLWithPath: "/Apps/ApolloShell.app/Contents/MacOS/ApolloShell")
        let plain = LiveShell.options(["x"], executable: exe)
        #expect(plain.config == nil)
        #expect(plain.resources.path == "/Apps/ApolloShell.app/Contents/Resources")
        #expect(plain.fixture == nil)
        let fixture = LiveShell.options(["x", "--fixture", "/tmp/f.kdl", "--config", "/tmp/c"], executable: exe)
        #expect(fixture.fixture?.path == "/tmp/f.kdl")
        #expect(fixture.config?.path == "/tmp/c")
    }
}
