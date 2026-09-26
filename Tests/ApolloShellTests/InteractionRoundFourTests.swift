import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Runde 4: Interaktion", .serialized)
struct InteractionRoundFourTests {
    @Test("tiling-tabs: zwei Tab-Leisten nebeneinander liegen je an ihrer eigenen Stelle")
    func tabBarsSideBySide() throws {
        let url = PackageResources.root.appendingPathComponent("Resources/configs/apolloshell-default/examples/tiling-tabs.kdl")
        let example = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: " | where 'screen' screen.id", with: "")
        let fixture = """
        fixture {
            wm {
                tab-bars {
                    - x=100 y=50 width=200 height=20 screen="render" active=1 {
                        tabs { - window=1 title="" app="A" }
                    }
                    - x=400 y=50 width=200 height=20 screen="render" active=2 {
                        tabs { - window=2 title="" app="B" }
                    }
                }
            }
        }
        """
        let shot = try RenderProbe.render(example, css: "#wm-tab-bars { width: 800px; height: 200px; } .wm-tab-bar { background: #ff0000; }", fixture: fixture)
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 100, y: 50, width: 500, height: 20))
        #expect(shot.pixel(100, 50).near(.red))
        #expect(shot.pixel(599, 69).near(.red))
        #expect(!shot.pixel(350, 55).near(.red))
    }
}
