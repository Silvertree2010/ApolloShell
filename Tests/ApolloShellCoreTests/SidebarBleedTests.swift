import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Leiste: Glas ueber den Bildschirmrand")
struct SidebarBleedTests {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("allein: links und unten ueber den Rand")
    func alone() {
        let e = SidebarBleed.edges(screen: main, others: [main])
        #expect(e.left == SidebarBleed.depth)
        #expect(e.bottom == SidebarBleed.depth)
    }

    @Test("Nachbar links: dort nicht")
    func leftNeighbour() {
        let e = SidebarBleed.edges(screen: main, others: [main, CGRect(x: -1920, y: -200, width: 1920, height: 1080)])
        #expect(e.left == 0)
        #expect(e.bottom == SidebarBleed.depth)
    }

    @Test("Nachbar darunter: dort nicht")
    func belowNeighbour() {
        let e = SidebarBleed.edges(screen: main, others: [main, CGRect(x: 200, y: -1080, width: 1920, height: 1080)])
        #expect(e.left == SidebarBleed.depth)
        #expect(e.bottom == 0)
    }

    @Test("Nachbar rechts oder oben stoert nicht")
    func otherSides() {
        let e = SidebarBleed.edges(screen: main, others: [main, CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                                                          CGRect(x: 0, y: 900, width: 1440, height: 900)])
        #expect(e.left == SidebarBleed.depth)
        #expect(e.bottom == SidebarBleed.depth)
    }

    @Test("Nachbar schraeg links unten: unten nicht")
    func diagonal() {
        let e = SidebarBleed.edges(screen: main, others: [main, CGRect(x: -1920, y: -1080, width: 1920, height: 1080)])
        #expect(e.left == SidebarBleed.depth)
        #expect(e.bottom == 0)
    }
}
