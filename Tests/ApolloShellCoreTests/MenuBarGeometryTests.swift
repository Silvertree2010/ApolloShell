import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Where the menu bar of a screen stands and what room the bars keep")
struct MenuBarGeometryTests {
    // A MacBook screen: 1728 x 1117, menu bar 33.
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let visibleTop: CGFloat = 1084

    @Test("Nothing on: the sidebar runs up to Apple's menu bar, nothing reserved but its width")
    func nothing() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44, bar: nil)
        #expect(r.frame == nil)
        #expect(r.sidebarMaxY == 1084)
        #expect(r.reserved == ReservedInsets(left: 44))
    }

    @Test("A bar over Apple's menu bar is never thinner than it, and keeps no extra room")
    func covering() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                       bar: .init(thickness: 28))
        #expect(r.frame == CGRect(x: 0, y: 1084, width: 1728, height: 33))
        #expect(r.sidebarMaxY == 1084)
        #expect(r.reserved == ReservedInsets(left: 44))
    }

    @Test("A thick bar over Apple's menu bar reaches below it and keeps that room")
    func coveringThick() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: nil,
                                       bar: .init(thickness: 44))
        #expect(r.frame == CGRect(x: 0, y: 1073, width: 1728, height: 44))
        #expect(r.sidebarMaxY == 1073)
        #expect(r.reserved.top == 44)
    }

    @Test("Below Apple's menu bar the bar starts under it")
    func below() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                       bar: .init(thickness: 34, coversMenuBar: false))
        #expect(r.frame == CGRect(x: 0, y: 1050, width: 1728, height: 34))
        #expect(r.sidebarMaxY == 1050)
        #expect(r.reserved == ReservedInsets(top: 67, left: 44))
    }

    @Test("Islands add their gap to the top edge")
    func islands() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: nil,
                                       bar: .init(thickness: 34, style: .islands))
        #expect(r.frame == CGRect(x: 0, y: 1077, width: 1728, height: 40))
        #expect(r.reserved.top == 40)
    }

    @Test("A second screen to the right with its own origin")
    func offsetScreen() {
        let second = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let r = MenuBarGeometry.layout(screen: second, visibleTop: 880, sidebarWidth: 44,
                                       bar: .init(thickness: 34))
        #expect(r.frame == CGRect(x: 1728, y: 846, width: 1920, height: 34))
        #expect(r.sidebarMaxY == 846)
        #expect(r.reserved == ReservedInsets(top: 34, left: 44))
    }

    @Test("Menu bar hidden: the bar sits at the very top")
    func hiddenMenuBar() {
        let r = MenuBarGeometry.layout(screen: screen, visibleTop: 1117, sidebarWidth: nil,
                                       bar: .init(thickness: 34))
        #expect(r.frame == CGRect(x: 0, y: 1083, width: 1728, height: 34))
        #expect(r.reserved.top == 34)
    }

    // MARK: Room left for panels

    @Test("Bar inset: the full reach from the top edge, Apple's menu bar included")
    func barInset() {
        let none = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44, bar: nil)
        #expect(none.barInset == 0)
        let covering = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                              bar: .init(thickness: 28))
        #expect(covering.barInset == 33)
        let islands = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: 44,
                                             bar: .init(thickness: 34, style: .islands))
        #expect(islands.barInset == 40)
        let below = MenuBarGeometry.layout(screen: screen, visibleTop: visibleTop, sidebarWidth: nil,
                                           bar: .init(thickness: 34, coversMenuBar: false))
        #expect(below.barInset == 67)
    }

    @Test("No menu bar: usable and bar-free frames are the old ones, bit for bit")
    func roomUnchanged() {
        let visible = CGRect(x: 0.25, y: 70.5, width: 1727.75, height: 1013.5)
        #expect(MenuBarGeometry.usableFrame(visible: visible, screen: screen, barInset: 0) == visible)
        #expect(MenuBarGeometry.barFreeFrame(screen: screen, barInset: 0) == screen)
    }

    @Test("Usable frame: the visible frame without what the bar covers")
    func usableFrame() {
        // Apple's Dock at the bottom (70), menu bar 33.
        let visible = CGRect(x: 0, y: 70, width: 1728, height: 1014)
        #expect(MenuBarGeometry.usableFrame(visible: visible, screen: screen, barInset: 44)
            == CGRect(x: 0, y: 70, width: 1728, height: 1003))
        #expect(MenuBarGeometry.barFreeFrame(screen: screen, barInset: 44)
            == CGRect(x: 0, y: 0, width: 1728, height: 1073))
        // A bar inside Apple's menu bar takes nothing the menu bar did not.
        #expect(MenuBarGeometry.usableFrame(visible: visible, screen: screen, barInset: 33) == visible)
    }
}
