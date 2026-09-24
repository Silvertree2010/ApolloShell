import CoreGraphics
import Testing
@testable import ApolloWMCore

@Suite("Canvas strip: columns, focus, scrolling")
struct StripTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let gaps = Gaps(outer: 0, inner: 10)

    private func strip(_ count: Int, width: CGFloat = 0.5) -> Strip<Int> {
        var strip = Strip<Int>()
        for id in 1...count { strip.insert(id, width: width) }
        return strip
    }

    @Test func aNewWindowOpensItsOwnColumnRightOfTheFocusedOne() {
        var strip = Strip<Int>()
        strip.insert(1)
        strip.insert(2)
        strip.focus(1)
        strip.insert(3)
        #expect(strip.columns.map(\.windows) == [[1], [3], [2]])
        #expect(strip.focused == 3)
    }

    @Test func stackingPutsAWindowUnderAnotherInItsColumn() {
        var strip = strip(2)
        strip.stack(3, intoColumnOf: 1)
        #expect(strip.columns.map(\.windows) == [[1, 3], [2]])
        #expect(strip.focused == 3)
        #expect(strip.columns.count == 2)
    }

    @Test func removingTheLastWindowTakesTheColumnWithIt() {
        var strip = strip(3)
        strip.remove(2)
        #expect(strip.columns.map(\.windows) == [[1], [3]])
        strip.stack(4, intoColumnOf: 3)
        strip.remove(4)
        #expect(strip.columns.map(\.windows) == [[1], [3]])
        #expect(strip.columns[1].active == 3)
    }

    @Test func focusWalksColumnsAndStopsAtTheEnds() {
        var strip = strip(3)
        strip.focus(1)
        #expect(strip.focusColumn(next: true) == 2)
        #expect(strip.focusColumn(next: true) == 3)
        #expect(strip.focusColumn(next: true) == 3)
        #expect(strip.focusColumn(next: false) == 2)
    }

    @Test func focusWalksInsideAColumn() {
        var strip = strip(1)
        strip.stack(2, intoColumnOf: 1)
        strip.stack(3, intoColumnOf: 2)
        strip.focus(1)
        #expect(strip.focusInColumn(next: true) == 2)
        #expect(strip.focusInColumn(next: true) == 3)
        #expect(strip.focusInColumn(next: true) == 3)
        #expect(strip.focusInColumn(next: false) == 2)
    }

    @Test func movingAColumnTakesTheFocusAlong() {
        var strip = strip(3)
        strip.focus(3)
        strip.moveColumn(next: false)
        #expect(strip.columns.map(\.windows) == [[1], [3], [2]])
        #expect(strip.focused == 3)
        strip.moveColumn(next: false)
        strip.moveColumn(next: false)
        #expect(strip.columns.map(\.windows) == [[3], [1], [2]])
    }

    @Test func expelTakesAStackedWindowIntoItsOwnColumn() {
        var strip = strip(1)
        strip.stack(2, intoColumnOf: 1)
        strip.expel(2)
        #expect(strip.columns.map(\.windows) == [[1], [2]])
        #expect(strip.focused == 2)
    }

    @Test func expelDoesNothingForAWindowAloneInItsColumn() {
        var strip = strip(2)
        strip.expel(1)
        #expect(strip.columns.map(\.windows) == [[1], [2]])
    }

    @Test func widthCyclesThroughThePresetsAndWrapsAround() {
        var strip = strip(1, width: 1.0 / 3)
        strip.cycleWidth(of: 1, wider: true)
        #expect(strip.columns[0].width == 0.5)
        strip.cycleWidth(of: 1, wider: true)
        #expect(strip.columns[0].width == 2.0 / 3)
        strip.cycleWidth(of: 1, wider: true)
        #expect(strip.columns[0].width == 1)
        strip.cycleWidth(of: 1, wider: true)
        #expect(strip.columns[0].width == 1.0 / 3)
        strip.cycleWidth(of: 1, wider: false)
        #expect(strip.columns[0].width == 1)
    }

    @Test func columnsStandSideBySideWithTheInnerGapBetweenThem() {
        var strip = strip(3)
        strip.scroll(by: -100, area: area, gaps: gaps)
        let frames = strip.layout(in: area, gaps: gaps)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[2] == CGRect(x: 510, y: 0, width: 500, height: 600))
        #expect(frames[3] == CGRect(x: 1020, y: 0, width: 500, height: 600))
    }

    @Test func stackedWindowsShareTheColumnHeight() {
        var strip = strip(1)
        strip.stack(2, intoColumnOf: 1)
        let frames = strip.layout(in: area, gaps: gaps)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 295))
        #expect(frames[2] == CGRect(x: 0, y: 305, width: 500, height: 295))
    }

    @Test func scrollingBringsTheFocusedColumnIntoView() {
        var strip = strip(3)
        strip.focus(3)
        strip.scrollToFocused(area: area, gaps: gaps)
        // The third column ends at 1520; the viewport is 1000 wide.
        #expect(strip.offset == 520)
        let frames = strip.layout(in: area, gaps: gaps)
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 600))
        strip.focus(1)
        strip.scrollToFocused(area: area, gaps: gaps)
        #expect(strip.offset == 0)
    }

    @Test func centeringPullsTheFocusedColumnToTheMiddle() {
        var strip = strip(3)
        strip.centerFocused = true
        strip.focus(2)
        strip.scrollToFocused(area: area, gaps: gaps)
        #expect(strip.offset == 260)
    }

    @Test func scrollingNeverLeavesTheStrip() {
        var strip = strip(2)
        strip.scroll(by: -500, area: area, gaps: gaps)
        #expect(strip.offset == 0)
        strip.scroll(by: 5000, area: area, gaps: gaps)
        // Two columns of 500 with a 10 gap = 1010, screen 1000.
        #expect(strip.offset == 10)
    }

    @Test func aStripShorterThanTheScreenStaysAtTheStart() {
        var strip = strip(1)
        strip.scroll(by: 300, area: area, gaps: gaps)
        #expect(strip.offset == 0)
    }

    @Test func onlyTheColumnsOnScreenCountAsVisible() {
        var strip = strip(4)
        strip.focus(1)
        strip.scrollToFocused(area: area, gaps: gaps)
        let visible = strip.visible(in: area, gaps: gaps)
        #expect(visible.contains(1))
        #expect(visible.contains(2))
        #expect(!visible.contains(4))
    }

    @Test func aMinimumSizeWidensAWindowWithoutMovingTheColumn() {
        var strip = strip(2, width: 1.0 / 3)
        strip.focus(1)
        let frames = strip.layout(in: area, gaps: gaps, minimums: [1: CGSize(width: 800, height: 0)])
        #expect(frames[1]?.width == 800)
        #expect(frames[2]?.minX == 343)
    }
}
