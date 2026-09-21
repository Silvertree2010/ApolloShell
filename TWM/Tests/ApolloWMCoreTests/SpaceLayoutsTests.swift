import CoreGraphics
import Foundation
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

    @Test func survivesSavingAndLoading() throws {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 10) { $0.insert(2) }
        layouts.assign(3, to: 20) { $0.insert(3) }
        layouts[10].resize(1, to: CGRect(x: 0, y: 0, width: 700, height: 600), in: area)
        layouts[10].freezeDirections(in: area)
        let data = try JSONEncoder().encode(layouts)
        let loaded = try JSONDecoder().decode(SpaceLayouts<Int, Int>.self, from: data)
        #expect(loaded[10].layout(in: area) == layouts[10].layout(in: area))
        #expect(loaded[10].layout(in: area)[1]?.width == 700)
        #expect(loaded.space(of: 3) == 20)
    }

    @Test func retainDropsVanishedWindows() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 10) { $0.insert(2) }
        layouts.retain { $0 != 2 }
        #expect(layouts[10].ids == [1])
        #expect(layouts.space(of: 2) == nil)
    }

    @Test func movingWholeLayoutKeepsArrangement() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 10) { $0.insert(2) }
        layouts[10].resize(1, to: CGRect(x: 0, y: 0, width: 700, height: 600), in: area)
        let before = layouts[10].layout(in: area)
        layouts.move(10, to: 30)
        #expect(layouts[30].layout(in: area) == before)
        #expect(layouts[10].isEmpty)
        #expect(layouts.space(of: 1) == 30)
    }

    @Test func movingOntoUsedLayoutAddsWindows() {
        var layouts = SpaceLayouts<Int, Int>()
        layouts.assign(1, to: 10) { $0.insert(1) }
        layouts.assign(2, to: 30) { $0.insert(2) }
        layouts.move(10, to: 30)
        #expect(Set(layouts[30].ids) == [1, 2])
        #expect(layouts.space(of: 1) == 30)
    }

    @Test func unknownDesktopIsEmpty() {
        #expect(SpaceLayouts<Int, Int>()[99].isEmpty)
    }
}
