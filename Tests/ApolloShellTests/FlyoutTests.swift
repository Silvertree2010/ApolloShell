import Testing
import Foundation
import AppKit
import SwiftUI
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Render: flyout (blocks.md 4.7)", .serialized)
struct FlyoutTests {
    @Test("Lage: mittig am Anker, im Bereich geklemmt, Keim 30 pt auf Ankerhöhe")
    func geometry() {
        let container = CGSize(width: 60, height: 400)
        let anchor = CGRect(x: 10, y: 20, width: 40, height: 40)
        let rect = FlyoutGeometry.rect(side: .right, anchor: anchor, size: CGSize(width: 200, height: 100), container: container, joined: true)
        #expect(rect == CGRect(x: 60, y: 0, width: 200, height: 100))
        let lower = FlyoutGeometry.rect(side: .right, anchor: CGRect(x: 10, y: 200, width: 40, height: 40), size: CGSize(width: 200, height: 100), container: container, joined: true)
        #expect(lower.minY == 170)
        #expect(FlyoutGeometry.rect(side: .left, anchor: anchor, size: CGSize(width: 80, height: 20), container: container, joined: false).minX == -70)
        #expect(FlyoutGeometry.seed(side: .right, anchor: anchor, container: container, joined: true) == CGRect(x: 60, y: 25, width: 0, height: 30))
        #expect(FlyoutSide.resolve(nil, surfaceAnchor: "right") == .left)
        #expect(FlyoutSide.resolve("bottom", surfaceAnchor: "left") == .bottom)
        let bulge = FlyoutBulge(key: "a", rect: rect, side: .right, radius: 25, join: 14, joined: true, open: true, container: container)
        #expect(FlyoutGeometry.extent([bulge]).trailing == 200)
        let small = CGSize(width: 40, height: 200), wider = CGSize(width: 60, height: 200), taller = CGSize(width: 40, height: 300)
        #expect(FlyoutView.thicknessChanged(small, wider, anchor: "right"))
        #expect(!FlyoutView.thicknessChanged(small, taller, anchor: "left"))
        #expect(FlyoutView.thicknessChanged(small, taller, anchor: "top"))
        #expect(!FlyoutView.thicknessChanged(small, wider, anchor: "bottom"))
        #expect(FlyoutView.thicknessChanged(small, taller, anchor: "center"))
    }

    static let config = """
    var open #true
    panel "bar" anchor="left" shape="fused" {
        stack id="hook" class="hook"
        flyout anchor="hook" side="right" open="{var.open}" class="fly" {
            on-close { set "open" #false }
            stack class="content"
        }
    }
    """
    static let css = """
    #bar { width: 40px; height: 200px; background: #0000ff; align-items: start; }
    .hook { width: 40px; height: 40px; margin: 80px 0 0 0; }
    .fly { border-radius: 10px; -apollo-join-radius: 8px; padding: 10px; background: #ff0000; }
    .content { width: 60px; height: 40px; background: #00ff00; }
    """

    @Test("verschmolzene Form: Oberfläche und offener Flyout sind eine Fläche mit Einwärtsbögen")
    func fused() throws {
        let shot = try RenderProbe.render(Self.config, css: Self.css)
        #expect(shot.size.width >= 120)
        #expect(shot.pixel(20, 100).near(.blue))
        #expect(shot.pixel(45, 100).near(.blue))
        #expect(shot.pixel(90, 100).near(.green))
        #expect(!shot.pixel(115, 100).near(.red))
        #expect(shot.pixel(41, 68).near(.blue, tolerance: 60))
        #expect(!shot.pixel(47, 62).near(.blue, tolerance: 60))
        #expect(!shot.pixel(90, 30).near(.blue))
    }

    @Test("geschlossen: keine Fläche neben der Oberfläche, Inhalt nicht sichtbar; on-close setzt open zurück")
    func closed() async throws {
        let shot = try RenderProbe.render(Self.config.replacingOccurrences(of: "var open #true", with: "var open #false"), css: Self.css)
        #expect(shot.size.width == 40)
        #expect(shot.count { $0.near(.green) } == 0)
        let mounted = try Mounted.mount(Self.config, css: Self.css)
        let surface = try #require(mounted.session.surfaces.first)
        let flyout = try #require(FlyoutCollector.collect(surface.root).first)
        #expect(mounted.session.context.fire("on-close", flyout.element))
        await mounted.settle()
        #expect(mounted.variable("open") == .bool(false))
    }

    static let resizeConfig = """
    var open #true
    var wide #false
    var tall #false
    panel "bar" anchor="left" shape="fused" {
        stack id="hook" class="hook"
        stack class="{var.wide ? 'w60' : 'w40'} {var.tall ? 'h300' : 'h200'}"
        flyout anchor="hook" side="right" open="{var.open}" class="fly" {
            on-close { set "open" #false }
            button id="inside" class="content" { on-click { set "open" #true } }
        }
    }
    """
    static let resizeCSS = """
    #bar { background: #0000ff; align-items: start; }
    .hook { width: 40px; height: 40px; }
    .w40 { width: 40px; } .w60 { width: 60px; } .h200 { height: 200px; } .h300 { height: 300px; }
    .fly { padding: 10px; background: #ff0000; }
    .content { width: 60px; height: 40px; background: #00ff00; }
    """

    @Test("Klick-ausserhalb-Monitor: ein globaler Monitor je Start, Mausklick ruft on-close, stop entfernt ihn")
    func outsideMonitor() async throws {
        var installed: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []
        var removed = 0
        let monitor = FlyoutOutsideMonitor(install: { mask, handler in
            installed.append((mask, handler))
            return installed.count
        }, remove: { _ in removed += 1 })
        var closed = 0
        monitor.start { closed += 1 }
        monitor.start { closed += 1 }
        #expect(installed.count == 2)
        #expect(removed == 1)
        #expect(installed[1].0 == [.leftMouseDown, .rightMouseDown, .otherMouseDown])
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        installed[1].1(click)
        for _ in 0..<5 { await Task.yield() }
        #expect(closed == 1)
        monitor.stop()
        monitor.stop()
        #expect(removed == 2)
    }

    @Test("Grössenänderung der Oberfläche: nur die Dicke quer zur verankerten Kante schliesst (Fund 46)")
    func closesOnThicknessOnly() async throws {
        let mounted = try Mounted.mount(Self.resizeConfig, css: Self.resizeCSS)
        let runtime = try #require(mounted.session.context.runtime)
        #expect(mounted.variable("open") == .bool(true))
        runtime.setVariable("tall", .bool(true))
        mounted.session.flush()
        mounted.pump()
        await mounted.settle()
        #expect(mounted.variable("open") == .bool(true))
        runtime.setVariable("wide", .bool(true))
        mounted.session.flush()
        mounted.pump()
        await mounted.settle()
        #expect(mounted.variable("open") == .bool(false))
    }

    @Test("geschlossener Flyout fängt keine Klicks und zählt nicht als Trefferfläche")
    func closedIsInert() async throws {
        let mounted = try Mounted.mount(Self.resizeConfig, css: Self.resizeCSS)
        let inside = try #require(mounted.catchers.first { $0.element?.property("id").plainText == "inside" })
        let key = try #require(mounted.session.surfaces.first).id + "@render"
        #expect(inside.config.claims(.left))
        #expect(mounted.session.context.hits.regions(for: key).contains { $0.identity == inside.element?.identity })
        mounted.session.context.runtime?.setVariable("open", .bool(false))
        mounted.session.flush()
        mounted.pump()
        #expect(!inside.config.claims(.left))
        #expect(!mounted.session.context.hits.regions(for: key).contains { $0.identity == inside.element?.identity })
        if let window = inside.window {
            let point = inside.convert(NSPoint(x: inside.bounds.midX, y: inside.bounds.midY), to: nil)
            #expect(ElementMouseView.winner(at: point, in: window, kind: .left) !== inside)
        }
    }
}
