import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bento geometry: a valid place and the scale")
struct BentoGeometryTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    @Test("On the page")
    func inside() {
        #expect(BentoGeometry.isInside(f(0, 0, 839, 392)))
        #expect(!BentoGeometry.isInside(f(-1, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(740, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(0, 263, 110, 130)))
    }

    @Test("Exactly 12 points apart is allowed, 11 is not, a diagonal offset does not count")
    func spacing() {
        let weather = f(0, 0, 275, 130)
        #expect(!BentoGeometry.tooClose(weather, f(287, 0, 340, 130)))
        #expect(BentoGeometry.tooClose(weather, f(286, 0, 340, 130)))
        #expect(!BentoGeometry.tooClose(weather, f(0, 142, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(0, 141, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(280, 136, 100, 250)))            // 5 in x, 6 in y: too close
        #expect(!BentoGeometry.tooClose(weather, f(300, 200, 100, 130)))           // 25 in x: free
        #expect(BentoGeometry.tooClose(weather, f(100, 50, 50, 50)))               // overlaps
    }

    @Test("Valid: on the page, an allowed size, the gap")
    func valid() {
        let others = [f(0, 0, 275, 130)]
        #expect(BentoGeometry.isValid(f(0, 142, 110, 250), kind: .clock, others: others))
        #expect(!BentoGeometry.isValid(f(0, 142, 100, 250), kind: .clock, others: others))   // too narrow
        #expect(!BentoGeometry.isValid(f(0, 142, 110, 200), kind: .clock, others: others))   // this height does not exist
        #expect(!BentoGeometry.isValid(f(0, 130, 110, 250), kind: .clock, others: others))   // too close
    }

    @Test("The scale: automatic by width, the slider, the height limits it", arguments: [
        (1512.0, 2000.0, 1.0, 1.0),
        (2560, 2000, 1.0, 1.5),
        (1280, 2000, 1.0, 0.85),
        (1512, 2000, 1.2, 1.2),
        (2560, 2000, 1.5, 2.25),
        (1512, 400, 1.0, 400.0 / 460.0),
        (1512, 2000, 9.0, 1.5),
        (1512, 2000, .nan, 1.0),
    ])
    func scale(screenWidth: Double, availableHeight: Double, user: Double, expected: Double) {
        let value = BentoGeometry.scale(screenWidth: screenWidth, availableHeight: availableHeight,
                                        contentHeight: 460, userScale: user)
        #expect(abs(value - expected) < 0.0001)
    }
}

@Suite("Bento geometry: snapping")
struct BentoSnapTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }
    private let weather = WidgetFrame(x: 0, y: 0, width: 275, height: 130)

    @Test("Dragging: the page edge, the line, 12 points beside it, otherwise free", arguments: [
        (WidgetFrame(x: 5, y: 300, width: 100, height: 50), 0.0, 300.0),     // left edge (y free)
        (WidgetFrame(x: 636, y: 3, width: 200, height: 130), 639, 0),        // right edge, top edge
        (WidgetFrame(x: 290, y: 4, width: 200, height: 130), 287, 0),        // 12 beside the weather
        (WidgetFrame(x: 400.4, y: 250.6, width: 100, height: 50), 400, 251), // no target: only rounded
        (WidgetFrame(x: 3, y: 146, width: 110, height: 250), 0, 142),        // aligned left, 12 below the weather
    ])
    func move(proposed: WidgetFrame, x: Double, y: Double) {
        let snapped = BentoGeometry.snapMove(proposed, others: [weather])
        #expect(snapped.x == x)
        #expect(snapped.y == y)
        // The width and height stay unchanged (not rounded) - some sizes of
        // the performance page are half points (413.5, say).
        #expect(snapped.width == proposed.width)
        #expect(snapped.height == proposed.height)
    }

    @Test("Dragging: half-point sizes of the performance page stay valid", arguments: [
        (true, WidgetKind.performanceStorage),
        (false, WidgetKind.performanceStorage),
        (true, WidgetKind.performanceCPU),
        (false, WidgetKind.performanceCPU),
    ])
    func moveHalfPointPerformanceWidgets(hasBattery: Bool, kind: WidgetKind) {
        // Template frames of the performance page (measured), the width
        // possibly a half point like 413.5 or 169.5.
        let size = kind.sizes.max { $0.maxWidth < $1.maxWidth }!
        let width = hasBattery ? size.minWidth : size.maxWidth
        let frame = WidgetFrame(x: 0, y: 0, width: width, height: size.height)
        // Move it a few points, as when dragging with the mouse.
        let proposed = WidgetFrame(x: frame.x + 3, y: frame.y + 4, width: width, height: size.height)
        let snapped = BentoGeometry.snapMove(proposed, others: [])
        #expect(BentoGeometry.isValid(snapped, kind: kind, others: []))
    }

    @Test("Dragging: the nearest target wins")
    func nearestWins() {
        // The right edge flush with the weather (x = 175) lies 2 away, everything else further.
        let snapped = BentoGeometry.snapMove(f(177, 300, 100, 50), others: [weather])
        #expect(snapped.x == 175)
    }

    @Test("Size: the height jumps, the width stays in range and snaps")
    func resize() {
        let clock = f(0, 142, 110, 250)
        // Height 260 -> 250, width 115 free (no target closer than 8)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 115, proposedHeight: 260, others: []) == f(0, 142, 115, 250))
        // Height 380 -> 392 no longer fits on the page; the function only snaps, isValid checks validity
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 110, proposedHeight: 380, others: []).height == 392)
        // A width below the minimum -> the minimum
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 40, proposedHeight: 250, others: []).width == 110)
        // The width snaps 12 before the neighbour: a neighbour at x = 300 -> width 288
        let neighbour = f(300, 142, 110, 250)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 283, proposedHeight: 250, others: [neighbour]).width == 288)
        // A fixed size stays fixed
        let network = f(0, 203, 335, 189)
        #expect(BentoGeometry.snapResize(network, kind: .performanceNetwork, proposedWidth: 400, proposedHeight: 150, others: []) == network)
    }

    @Test("Dropping: the smallest size, centred under the pointer, snapped")
    func drop() {
        let frame = BentoGeometry.dropFrame(kind: .clock, x: 60, y: 208, others: [weather])
        #expect(frame == f(0, 142, 110, 130))   // 60-55 = 5 -> edge 0; 208-65 = 143 -> 142 (12 below the weather)
    }
}
