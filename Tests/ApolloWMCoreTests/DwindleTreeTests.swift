import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("Dwindle layout: split, remove, drop by mouse")
struct DwindleTreeTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func singleWindowFillsArea() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        #expect(tree.layout(in: area) == [1: area])
    }

    @Test func outerGapInsetsArea() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        #expect(tree.layout(in: area, gaps: Gaps(outer: 10, inner: 0))[1] == CGRect(x: 10, y: 10, width: 980, height: 580))
    }

    @Test func secondWindowSplitsSideBySideOnWideArea() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test func thirdWindowStacksInTallHalf() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        let f = tree.layout(in: area)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(f[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func innerGapSeparatesTiles() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, gaps: Gaps(outer: 0, inner: 10))
        #expect(f[1] == CGRect(x: 0, y: 0, width: 495, height: 600))
        #expect(f[2] == CGRect(x: 505, y: 0, width: 495, height: 600))
    }

    @Test func removeGivesSpaceToSibling() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        tree.remove(2)
        let f = tree.layout(in: area)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(f[3] == CGRect(x: 500, y: 0, width: 500, height: 600))
        #expect(tree.ids == [1, 3])
    }

    @Test func removeLastEmptiesTree() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.remove(1)
        #expect(tree.isEmpty)
    }

    @Test func duplicateInsertIsIgnored() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(1)
        #expect(tree.ids == [1])
    }

    @Test func dropOnLeftHalfOfTileGoesLeft() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(3, at: CGPoint(x: 100, y: 300), in: area)
        #expect(tree.ids == [3, 1])
    }

    @Test func dropOnRightHalfOfTileGoesRight() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(3, at: CGPoint(x: 900, y: 300), in: area)
        #expect(tree.ids == [1, 3])
    }

    @Test func dropSplitsTheTileUnderTheMouse() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        // Top of window 1's tall tile: 1 is split top/bottom, 3 on top.
        tree.insert(3, at: CGPoint(x: 250, y: 50), in: area)
        let f = tree.layout(in: area)
        #expect(f[3] == CGRect(x: 0, y: 0, width: 500, height: 300))
        #expect(f[1] == CGRect(x: 0, y: 300, width: 500, height: 300))
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }

    @Test func dropOutsideAllTilesSplitsLast() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        tree.insert(3, at: CGPoint(x: -50, y: -50), in: area)
        #expect(tree.ids == [1, 2, 3])
    }

    @Test func dropIntoEmptyTreeFillsArea() {
        var tree = DwindleTree<Int>()
        tree.insert(7, at: CGPoint(x: 1, y: 1), in: area)
        #expect(tree.layout(in: area) == [7: area])
    }

    @Test func minimumWidthMovesSplit() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, minimums: [2: CGSize(width: 700, height: 0)])
        #expect(f[1] == CGRect(x: 0, y: 0, width: 300, height: 600))
        #expect(f[2] == CGRect(x: 300, y: 0, width: 700, height: 600))
    }

    @Test func minimumBelowShareChangesNothing() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        #expect(tree.layout(in: area, minimums: [1: CGSize(width: 200, height: 200)]) == tree.layout(in: area))
    }

    @Test func nestedMinimumPushesWholeSubtree() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        // 3 sits in the right half, stacked under 2; its width moves the root split.
        let f = tree.layout(in: area, minimums: [3: CGSize(width: 800, height: 0)])
        #expect(f[1] == CGRect(x: 0, y: 0, width: 200, height: 600))
        #expect(f[2]?.width == 800)
        #expect(f[3] == CGRect(x: 200, y: 300, width: 800, height: 300))
    }

    @Test func minimumHeightMovesStackedSplit() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        let f = tree.layout(in: area, minimums: [2: CGSize(width: 0, height: 450)])
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 450))
        #expect(f[3] == CGRect(x: 500, y: 450, width: 500, height: 150))
    }

    @Test func impossibleMinimumsShareProportionally() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, minimums: [1: CGSize(width: 900, height: 0), 2: CGSize(width: 300, height: 0)])
        #expect(f[1]?.width == 750)
        #expect(f[2]?.width == 250)
    }

    @Test func minimumsRespectInnerGap() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, gaps: Gaps(outer: 0, inner: 10), minimums: [1: CGSize(width: 800, height: 0)])
        #expect(f[1] == CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(f[2] == CGRect(x: 810, y: 0, width: 190, height: 600))
    }

    @Test func maximumHandsRestToNeighbor() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, maximums: [1: CGSize(width: 300, height: CGFloat.infinity)])
        #expect(f[1] == CGRect(x: 0, y: 0, width: 300, height: 600))
        #expect(f[2] == CGRect(x: 300, y: 0, width: 700, height: 600))
    }

    @Test func maximumOfSecondSideWorksToo() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, maximums: [2: CGSize(width: 200, height: CGFloat.infinity)])
        #expect(f[1]?.width == 800)
        #expect(f[2] == CGRect(x: 800, y: 0, width: 200, height: 600))
    }

    @Test func minimumBeatsMaximum() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let f = tree.layout(in: area, minimums: [2: CGSize(width: 900, height: 0)],
                            maximums: [1: CGSize(width: 800, height: CGFloat.infinity)])
        #expect(f[2]?.width == 900)
    }

    @Test func maximumInsideStackLimitsOnlyAlongStack() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        // 2 and 3 are stacked; 2 cannot be taller than 200, 3 takes the rest.
        let f = tree.layout(in: area, maximums: [2: CGSize(width: CGFloat.infinity, height: 200)])
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 200))
        #expect(f[3] == CGRect(x: 500, y: 200, width: 500, height: 400))
        #expect(f[1]?.width == 500)
    }

    @Test func windowThatCannotFillSitsCentered() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        let f = tree.layout(in: area, maximums: [1: CGSize(width: 400, height: 300)])
        #expect(f[1] == CGRect(x: 300, y: 150, width: 400, height: 300))
    }

    @Test func centeringOnlyAcrossTheSplit() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        // 2 sits in a 500 wide column but cannot be wider than 300.
        let f = tree.layout(in: area, maximums: [2: CGSize(width: 300, height: CGFloat.infinity)])
        #expect(f[2] == CGRect(x: 600, y: 0, width: 300, height: 300))
        #expect(f[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func marginAroundCenteredWindowStillHitsIt() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        let maxes = [1: CGSize(width: 200, height: 200)]
        // 1 gives the rest to 2 along the split; across it, 1 is centered.
        #expect(tree.id(at: CGPoint(x: 100, y: 20), in: area, maximums: maxes) == 1)
    }

    @Test func draggingRightEdgeMovesSplit() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        tree.resize(1, to: CGRect(x: 0, y: 0, width: 700, height: 600), in: area)
        let f = tree.layout(in: area)
        #expect(f[1] == CGRect(x: 0, y: 0, width: 700, height: 600))
        #expect(f[2] == CGRect(x: 700, y: 0, width: 300, height: 600))
    }

    @Test func draggingLeftEdgeOfSecondMovesSplit() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        tree.resize(2, to: CGRect(x: 200, y: 0, width: 800, height: 600), in: area, gaps: Gaps(outer: 0, inner: 10))
        let f = tree.layout(in: area, gaps: Gaps(outer: 0, inner: 10))
        #expect(f[1]?.width == 190)
        #expect(f[2] == CGRect(x: 200, y: 0, width: 800, height: 600))
    }

    @Test func draggingBottomEdgeMovesNearestStackedSplit() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        tree.freezeDirections(in: area)
        tree.resize(2, to: CGRect(x: 500, y: 0, width: 500, height: 450), in: area)
        let f = tree.layout(in: area)
        #expect(f[2] == CGRect(x: 500, y: 0, width: 500, height: 450))
        #expect(f[3] == CGRect(x: 500, y: 450, width: 500, height: 150))
        #expect(f[1]?.width == 500)
    }

    @Test func cornerDragMovesBothSplits() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        tree.freezeDirections(in: area)
        // 2's bottom-left corner: left edge to 400, bottom edge to 200.
        tree.resize(2, to: CGRect(x: 400, y: 0, width: 600, height: 200), in: area)
        let f = tree.layout(in: area)
        #expect(f[1]?.width == 400)
        #expect(f[2] == CGRect(x: 400, y: 0, width: 600, height: 200))
        #expect(f[3] == CGRect(x: 400, y: 200, width: 600, height: 400))
    }

    @Test func frozenDirectionSurvivesResize() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        tree.freezeDirections(in: area)
        // Shrinking the right column to 300 wide would make it taller than
        // wide; frozen, 2 and 3 stay stacked.
        tree.resize(1, to: CGRect(x: 0, y: 0, width: 900, height: 600), in: area)
        let f = tree.layout(in: area)
        #expect(f[2] == CGRect(x: 900, y: 0, width: 100, height: 300))
        #expect(f[3] == CGRect(x: 900, y: 300, width: 100, height: 300))
    }

    @Test func resizeClampsRatio() {
        var tree = DwindleTree<Int>()
        tree.insert(1)
        tree.insert(2)
        tree.resize(1, to: CGRect(x: 0, y: 0, width: 5000, height: 600), in: area)
        #expect(tree.layout(in: area)[2]?.width == 50)
    }

    @Test func hitTestFindsTile() {
        var tree = DwindleTree<Int>()
        [1, 2, 3].forEach { tree.insert($0) }
        #expect(tree.id(at: CGPoint(x: 700, y: 500), in: area) == 3)
        #expect(tree.id(at: CGPoint(x: 2000, y: 0), in: area) == nil)
    }
}

@Suite("Springs: settle, no overshoot, keep velocity on retarget")
struct SpringTests {
    @Test func settlesOnTarget() {
        var s = Spring(0)
        s.target = 100
        for _ in 0..<120 { s.step(1.0 / 60, response: 0.3) }
        #expect(s.isSettled)
        #expect(s.value == 100)
    }

    @Test func neverOvershootsFromRest() {
        var s = Spring(0)
        s.target = 100
        for _ in 0..<240 {
            s.step(1.0 / 120, response: 0.3)
            #expect(s.value <= 100)
        }
    }

    @Test func retargetKeepsVelocity() {
        var s = Spring(0)
        s.target = 100
        for _ in 0..<5 { s.step(1.0 / 60, response: 0.3) }
        let v = s.velocity
        s.target = -100
        #expect(s.velocity == v)
        #expect(v > 0)
    }

    @Test func largeStepStaysStable() {
        var s = Spring(0)
        s.target = 100
        s.step(5, response: 0.3)
        #expect(s.value == 100)
    }

    @Test func animatedRectReportsTarget() {
        var r = AnimatedRect(CGRect(x: 0, y: 0, width: 10, height: 10))
        r.target = CGRect(x: 50, y: 60, width: 70, height: 80)
        #expect(!r.isSettled)
        for _ in 0..<200 { r.step(1.0 / 60, response: 0.3) }
        #expect(r.current == CGRect(x: 50, y: 60, width: 70, height: 80))
    }
}

@Suite("Resize once: glide position, redraw content rarely")
struct ResizeOnceTests {
    @Test func shrinkingSnapsImmediately() {
        var r = AnimatedRect(CGRect(x: 0, y: 0, width: 800, height: 600))
        r.target = CGRect(x: 100, y: 0, width: 400, height: 600)
        r.stepResizingOnce(1.0 / 120, response: 0.3)
        #expect(r.current.width == 400)
        #expect(r.current.minX > 0 && r.current.minX < 100)
    }

    @Test func growingWaitsForPosition() {
        var r = AnimatedRect(CGRect(x: 500, y: 0, width: 400, height: 600))
        r.target = CGRect(x: 0, y: 0, width: 800, height: 600)
        r.stepResizingOnce(1.0 / 120, response: 0.3)
        #expect(r.current.width == 400)
        for _ in 0..<240 { r.stepResizingOnce(1.0 / 120, response: 0.3) }
        #expect(r.isSettled)
        #expect(r.current == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func sizeChangesAtMostTwice() {
        var r = AnimatedRect(CGRect(x: 500, y: 0, width: 400, height: 300))
        r.target = CGRect(x: 0, y: 0, width: 800, height: 200)
        var sizes: [CGSize] = [r.current.size]
        while !r.isSettled {
            r.stepResizingOnce(1.0 / 120, response: 0.3)
            if sizes.last != r.current.size { sizes.append(r.current.size) }
        }
        #expect(sizes.count <= 3)
    }
}

@Suite("Duration stats")
struct DurationsTests {
    @Test func percentiles() {
        var d = Durations()
        (1...100).forEach { d.add(Double($0)) }
        #expect(d.median == 50)
        #expect(d.percentile(0.95) == 95)
        #expect(d.max == 100)
    }

    @Test func emptySummary() {
        #expect(Durations().summary == "n=0")
    }
}
