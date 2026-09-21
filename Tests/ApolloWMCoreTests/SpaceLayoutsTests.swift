import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("One layout per desktop")
struct SpaceLayoutsTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func desktopsDoNotShareTiles() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 20) { $0.insert(2) }
        #expect(layouts[10].layout(in: area) == [1: area])
        #expect(layouts[20].layout(in: area) == [2: area])
    }

    @Test func movingWindowLeavesOldDesktop() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 10) { $0.insert(2) }
        layouts.assign(2, to: 20) { $0.insert(2) }
        #expect(layouts[10].ids == [1])
        #expect(layouts[20].ids == [2])
        #expect(layouts.space(of: 2) == 20)
    }

    @Test func assignToSameDesktopKeepsPosition() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 10) { $0.insert(2) }
        layouts.assign(1, to: 10) { $0.insert(1) }
        #expect(layouts[10].ids == [1, 2])
    }

    @Test func removeForgetsWindow() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.remove(1)
        #expect(layouts.space(of: 1) == nil)
        #expect(layouts.trees.isEmpty)
    }

    @Test func unknownDesktopIsEmpty() {
        #expect(SpaceLayouts<Int, Int>()[99].isEmpty)
    }
}
