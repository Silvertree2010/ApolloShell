import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("Tab groups")
struct TabGroupTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func newGroupShowsTheAddedWindow() {
        var group = TabGroup(1, 2)
        #expect(group.active == 2)
        group.add(3)
        #expect(group.members == [1, 2, 3])
        #expect(group.active == 3)
    }

    @Test func removingActivePicksRightNeighbor() {
        var group = TabGroup(1, 2, active: 1)
        group.add(3)
        group.activate(2)
        #expect(group.remove(2) == 3)
        #expect(group.active == 3)
    }

    @Test func removingLastTabPicksLeftNeighbor() {
        var group = TabGroup(1, 2)
        group.add(3)
        #expect(group.remove(3) == 2)
    }

    @Test func groupOfOneEnds() {
        var group = TabGroup(1, 2)
        #expect(group.remove(1) == nil)
    }

    @Test func tabNeighborsWrapAround() {
        var group = TabGroup(1, 2)
        group.add(3)
        #expect(group.neighbor(of: 3, forward: true) == 1)
        #expect(group.neighbor(of: 1, forward: false) == 3)
    }

    @Test func replaceKeepsTheTile() {
        var tree = DwindleTree<Int>()
        [1, 2].forEach { tree.insert($0) }
        let before = tree.layout(in: area)
        tree.replace(2, with: 9)
        #expect(tree.layout(in: area)[9] == before[2])
        #expect(!tree.contains(2))
    }

    @Test func siblingIsWhereTheWindowWasSplitFrom() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        #expect(tree.sibling(of: 3) == 2)
        #expect(tree.sibling(of: 1) == 2)
    }

    @Test func fitsKnowsWhenMinimumsClash() {
        var tree = DwindleTree<Int>()
        [1, 2].forEach { tree.insert($0) }
        #expect(tree.fits(in: area, minimums: [1: CGSize(width: 400, height: 0)]))
        #expect(!tree.fits(in: area, minimums: [1: CGSize(width: 700, height: 0), 2: CGSize(width: 400, height: 0)]))
    }

    @Test func aTabMovesOnePlaceAlongTheBarAndStopsAtTheEnds() {
        var group = TabGroup(1, 2)
        group.add(3)
        let moved = group.move(1, forward: true)
        #expect(moved)
        #expect(group.members == [2, 1, 3])
        let stopped = group.move(2, forward: false)
        #expect(!stopped)
        #expect(group.members == [2, 1, 3])
    }

    @Test func aTabCanBeDroppedAtAPlace() {
        var group = TabGroup(1, 2)
        group.add(3)
        group.move(3, to: 0)
        #expect(group.members == [3, 1, 2])
        group.move(3, to: 99)
        #expect(group.members == [3, 1, 2])
    }
}
