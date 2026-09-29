import Testing
import AppKit
import SwiftUI
import ApolloStyle
import ApolloBase
import ApolloConfig
import ApolloProviders
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Layout-Arbeit des offenen Dashboards")
struct LayoutWorkTests {
    static let resources = PackageResources.root.appendingPathComponent("Resources")

    static func mounted(_ id: String) throws -> (RenderSession, NSView) {
        let fixture = resources.appendingPathComponent("render/fixture.kdl")
        let session = try RenderSession(config: resources.appendingPathComponent("configs/apolloshell-default"), resources: resources,
                                        fixture: ProviderFixture.load(fixture), fixtureRoot: fixture.deletingLastPathComponent(), dark: true, scale: 1)
        let surface = try #require(session.surface(id))
        session.assembly.runtime.open(surface.id, screenKey: surface.screenKey)
        session.assembly.runtime.surfaceDidFinishOpening(id: surface.id, screenKey: surface.screenKey)
        session.flush()
        let view = session.mount(surface)
        for _ in 0..<10 { session.canvas.settle() }
        return (session, view)
    }

    static func measures(_ work: () -> Void) -> Int {
        let before = LayoutCounter.measures.load(ordering: .relaxed)
        work()
        return LayoutCounter.measures.load(ordering: .relaxed) - before
    }

    @Test("ohne Änderung kein Layout-Durchlauf")
    func idleNoLayout() throws {
        let (session, _) = try Self.mounted("dashboard")
        let count = Self.measures { for _ in 0..<10 { session.canvas.settle() } }
        #expect(count == 0)
    }

    @Test("CPU-Wert ändern misst jedes Layout höchstens wenige Male, nicht exponentiell über die Tiefe")
    func cpuChange() throws {
        let (session, _) = try Self.mounted("dashboard")
        var counts: [Int] = []
        for value in [0.1, 0.2, 0.3] {
            counts.append(Self.measures {
                session.assembly.store.set(DependencyPath("perf", ["cpu"]), .number(value))
                session.flush()
                for _ in 0..<5 { session.canvas.settle() }
            })
        }
        #expect(counts.allSatisfy { $0 < 800 }, "\(counts)")
    }
}

private struct AnimatedRingProbe: View {
    var value: Double
    var animated = true
    var kind = "ring"

    var body: some View {
        FlexLayout(horizontal: false, gap: 4, align: "center", justify: "start") {
            FlexLayout(horizontal: true, gap: 4, align: "center", justify: "start") {
                Text("CPU")
                Group {
                    switch kind {
                    case "gauge": GaugeView(value: value, ticks: 5, style: DisplayStyle(ComputedStyle(values: [:])))
                    default: RingView(value: value, gap: 0.05, start: -90, sweep: 360, style: DisplayStyle(ComputedStyle(values: [:])))
                    }
                }
                .frame(width: 40, height: 40)
                    .animation(animated ? .linear(duration: 0.5) : nil, value: value)
            }
            Text("Memory")
        }
    }
}

@MainActor
@Suite("Layout während Wert-Animationen")
struct AnimationLayoutTests {
    static func measures(animated: Bool, kind: String) -> (Int, Int) {
        let window = NSWindow(contentRect: NSRect(origin: OffscreenCanvas.origin, size: NSSize(width: 200, height: 200)), styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: AnimatedRingProbe(value: 0.1, animated: animated, kind: kind))
        window.contentView = hosting
        defer { window.contentView = nil }
        for _ in 0..<20 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)); hosting.layoutSubtreeIfNeeded() }
        let before = LayoutCounter.measures.load(ordering: .relaxed)
        hosting.rootView = AnimatedRingProbe(value: 0.9, animated: animated, kind: kind)
        let end = Date().addingTimeInterval(0.7)
        var frames = 0
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.016))
            hosting.layoutSubtreeIfNeeded()
            frames += 1
        }
        return (LayoutCounter.measures.load(ordering: .relaxed) - before, frames)
    }

    @Test("Ring und Gauge animieren, das Layout drumherum bleibt stehen", arguments: ["ring", "gauge"])
    func valueAnimationDoesNotRelayout(kind: String) throws {
        let still = Self.measures(animated: false, kind: kind)
        let moving = Self.measures(animated: true, kind: kind)
        #expect(moving.0 <= still.0 + 20, "\(still) \(moving)")
    }
}
