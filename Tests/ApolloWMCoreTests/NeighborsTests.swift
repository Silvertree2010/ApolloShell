import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("Keyboard: neighbors, swap, toggle split, equalize")
struct NeighborsTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    func threeWindows() -> DwindleTree<Int> {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        tree.freezeDirections(in: area)
        return tree
    }

    @Test func neighborsFollowTheScreen() {
        let frames = threeWindows().layout(in: area)
        #expect(Neighbors.neighbor(of: 1, .right, in: frames) == 2)
        #expect(Neighbors.neighbor(of: 2, .down, in: frames) == 3)
        #expect(Neighbors.neighbor(of: 3, .up, in: frames) == 2)
        #expect(Neighbors.neighbor(of: 3, .left, in: frames) == 1)
        #expect(Neighbors.neighbor(of: 1, .left, in: frames) == nil)
        #expect(Neighbors.neighbor(of: 2, .right, in: frames) == nil)
    }

    @Test func noDiagonalJumps() {
        let frames: [Int: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 100, height: 100),
            2: CGRect(x: 200, y: 300, width: 100, height: 100),
        ]
        #expect(Neighbors.neighbor(of: 1, .right, in: frames) == nil)
    }

    @Test func swapExchangesPlaces() {
        var tree = threeWindows()
        let before = tree.layout(in: area)
        tree.swap(1, 3)
        let after = tree.layout(in: area)
        #expect(after[1] == before[3])
        #expect(after[3] == before[1])
        #expect(after[2] == before[2])
    }

    @Test func toggleSplitTurnsTheStack() {
        var tree = threeWindows()
        tree.toggleSplit(of: 3)
        let f = tree.layout(in: area)
        // 2 and 3 were stacked in the right half; now side by side.
        #expect(f[2] == CGRect(x: 500, y: 0, width: 250, height: 600))
        #expect(f[3] == CGRect(x: 750, y: 0, width: 250, height: 600))
    }

    @Test func equalizeUndoesResizes() {
        var tree = threeWindows()
        let even = tree.layout(in: area)
        tree.resize(1, to: CGRect(x: 0, y: 0, width: 800, height: 600), in: area)
        tree.equalize()
        #expect(tree.layout(in: area) == even)
    }
}
