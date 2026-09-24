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

    @Test("geschlossen: keine Fläche neben der Oberfläche, Inhalt nicht sichtbar; Grössenänderung ruft on-close")
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
}
