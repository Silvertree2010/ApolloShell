import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Where the bars of a screen stand and what room they keep")
struct EdgeBarGeometryTests {
    // A MacBook screen: 1728 x 1117, menu bar 33.
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visibleTop: CGFloat = 1084

    @Test("Nothing on: the sidebar runs from the bottom to the menu bar, nothing reserved but its width")
    func nothing() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44, bars: [:])
        #expect(r.frames.isEmpty)
        #expect(r.sidebarMinY == 0 && r.sidebarMaxY == 1084)
        #expect(r.reserved == ReservedInsets(left: 44))
    }

    @Test("A top bar over the menu bar is never thinner than it, and keeps no extra room")
    func topCovering() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                       bars: [.top: .init(thickness: 28)])
        #expect(r.frames[.top] == CGRect(x: 0, y: 1084, width: 1728, height: 33))
        #expect(r.sidebarMaxY == 1084)
        #expect(r.reserved.top == 0)
    }

    @Test("A thick top bar over the menu bar reaches below it and keeps that room")
    func topCoveringThick() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: nil,
                                       bars: [.top: .init(thickness: 44)])
        #expect(r.frames[.top] == CGRect(x: 0, y: 1073, width: 1728, height: 44))
        #expect(r.sidebarMaxY == 1073)
        #expect(r.reserved.top == 44)
    }

    @Test("Below the menu bar the bar starts under it")
    func topBelow() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                       bars: [.top: .init(thickness: 34, coversMenuBar: false)])
        #expect(r.frames[.top] == CGRect(x: 0, y: 1050, width: 1728, height: 34))
        #expect(r.sidebarMaxY == 1050)
        #expect(r.reserved.top == 67)
    }

    @Test("Islands add their gap to the edge")
    func islands() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: nil,
                                       bars: [.bottom: .init(thickness: 34, style: .islands)])
        #expect(r.frames[.bottom] == CGRect(x: 0, y: 0, width: 1728, height: 40))
        #expect(r.reserved.bottom == 40)
    }

    @Test("All bars: top and bottom run the full width, sidebar and right bar fit between")
    func all() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44, bars: [
            .top: .init(thickness: 34, coversMenuBar: false),
            .bottom: .init(thickness: 30),
            .right: .init(thickness: 40),
        ])
        #expect(r.frames[.bottom] == CGRect(x: 0, y: 0, width: 1728, height: 30))
        #expect(r.frames[.right] == CGRect(x: 1688, y: 30, width: 40, height: 1020))
        #expect(r.sidebarMinY == 30 && r.sidebarMaxY == 1050)
        #expect(r.reserved == ReservedInsets(top: 67, left: 44, bottom: 30, right: 40))
    }

    @Test("A second screen to the right with its own origin")
    func offsetScreen() {
        let second = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let r = EdgeBarGeometry.layout(screen: second, visibleTop: 880, sidebarWidth: nil,
                                       bars: [.right: .init(thickness: 34), .bottom: .init(thickness: 34)])
        #expect(r.frames[.bottom] == CGRect(x: 1728, y: -200, width: 1920, height: 34))
        #expect(r.frames[.right] == CGRect(x: 3614, y: -166, width: 34, height: 1046))
    }

    @Test("Menu bar hidden: the top bar sits at the very top")
    func hiddenMenuBar() {
        let r = EdgeBarGeometry.layout(screen: screen, visibleTop: 1117, sidebarWidth: nil,
                                       bars: [.top: .init(thickness: 34)])
        #expect(r.frames[.top] == CGRect(x: 0, y: 1083, width: 1728, height: 34))
        #expect(r.reserved.top == 34)
    }
}
