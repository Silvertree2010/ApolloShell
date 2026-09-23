import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Where the zones of an edge bar go")
struct EdgeBarZonesTests {
    private typealias Span = EdgeBarZoneLayout.Span

    @Test("With room to spare the centre stands in the true middle")
    func centred() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 100, gap: 8)
        #expect(p.start == Span(origin: 0, length: 100))
        #expect(p.center == Span(origin: 400, length: 200))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A long start pushes the centre right, a gap away")
    func pushedByStart() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 500, center: 200, end: 100, gap: 8)
        #expect(p.center.origin == 508)
        #expect(p.center.end + 8 <= p.end.origin)
    }

    @Test("A long end pushes the centre left, a gap away")
    func pushedByEnd() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 500, gap: 8)
        #expect(p.center == Span(origin: 292, length: 200))
        #expect(p.start.end + 8 <= p.center.origin)
    }

    @Test("Too long a start is cut, never laid over centre or end")
    func startCut() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 900, center: 200, end: 100, gap: 8)
        #expect(p.start.length == 684)
        #expect(p.start.end + 8 == p.center.origin)
        #expect(p.center.end + 8 == p.end.origin)
    }

    @Test("Empty zones take neither room nor a gap")
    func emptyZones() {
        let onlyCenter = EdgeBarZoneLayout.place(length: 1000, start: 0, center: 200, end: 0, gap: 8)
        #expect(onlyCenter.center == Span(origin: 400, length: 200))
        let onlyEnd = EdgeBarZoneLayout.place(length: 1000, start: 0, center: 0, end: 100, gap: 8)
        #expect(onlyEnd.end == Span(origin: 900, length: 100))
        #expect(onlyEnd.start.length == 0 && onlyEnd.center.length == 0)
    }

    @Test("More than fits: the end keeps its length, the centre shrinks to the rest")
    func overfull() {
        let p = EdgeBarZoneLayout.place(length: 300, start: 100, center: 200, end: 250, gap: 8)
        #expect(p.end == Span(origin: 50, length: 250))
        #expect(p.center.length == 42)
        #expect(p.start.length == 0)
        #expect(p.center.origin >= 0 && p.center.end + 8 <= p.end.origin)
    }

    // The MacBook measured 22.09.: left area up to 771, right area from 956.
    private let notch = BarNotch(leftEnd: 771, rightStart: 956)

    @Test("Notch: the start stays left of the housing, centre and end go right of it")
    func notchSplits() {
        let p = EdgeBarZoneLayout.place(length: 1728, start: 300, center: 150, end: 200, gap: 8, notch: notch)
        #expect(p.start == Span(origin: 0, length: 300))
        #expect(p.center == Span(origin: 964, length: 150))
        #expect(p.end == Span(origin: 1528, length: 200))
    }

    @Test("Notch: a start longer than the left area is cut a gap short of the housing")
    func notchCutsStart() {
        let p = EdgeBarZoneLayout.place(length: 1728, start: 900, center: 0, end: 0, gap: 8, notch: notch)
        #expect(p.start.length == 763)
    }

    @Test("Notch: when centre and end overfill the right area, the centre gives way")
    func notchRightOverfull() {
        let p = EdgeBarZoneLayout.place(length: 1728, start: 0, center: 600, end: 300, gap: 8, notch: notch)
        #expect(p.end == Span(origin: 1428, length: 300))
        #expect(p.center == Span(origin: 964, length: 456))
    }

    @Test("Notch from the screen's auxiliary areas, relative to the screen")
    func notchFromAreas() {
        let left = CGRect(x: 1728, y: 1085, width: 771, height: 32)
        let right = CGRect(x: 1728 + 956, y: 1085, width: 772, height: 32)
        #expect(BarNotch(screenMinX: 1728, leftArea: left, rightArea: right) == BarNotch(leftEnd: 771, rightStart: 956))
        #expect(BarNotch(screenMinX: 1728, leftArea: left, rightArea: nil) == nil)
        let touching = CGRect(x: left.maxX, y: 1085, width: 900, height: 32)
        #expect(BarNotch(screenMinX: 1728, leftArea: left, rightArea: touching) == nil)
        #expect(BarNotch(leftEnd: 771, rightStart: 956).shifted(by: 10) == BarNotch(leftEnd: 761, rightStart: 946))
    }

    // MARK: Flexible zones

    private typealias Flex = EdgeBarZoneLayout.Flexible

    @Test("A Dock alone in the centre takes the room between start and end")
    func flexibleCenterFills() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 0, end: 100, gap: 8,
                                        flexible: Flex(center: 1))
        #expect(p.center == Span(origin: 108, length: 784))
        #expect(p.start == Span(origin: 0, length: 100))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A flexible centre grows evenly on both sides so it stays in the middle")
    func flexibleCenterStaysCentred() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 300, center: 0, end: 100, gap: 8,
                                        flexible: Flex(center: 1))
        #expect(p.center == Span(origin: 308, length: 384))
        #expect(p.center.origin + p.center.length / 2 == 500)
    }

    @Test("A flexible start grows up to the centre, a gap short of it")
    func flexibleStartGrowsToCenter() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 100, gap: 8,
                                        flexible: Flex(start: 1))
        #expect(p.start == Span(origin: 0, length: 392))
        #expect(p.center == Span(origin: 400, length: 200))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A flexible end grows towards the centre")
    func flexibleEndGrowsToCenter() {
        let p = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 50, gap: 8,
                                        flexible: Flex(end: 1))
        #expect(p.end == Span(origin: 608, length: 392))
    }

    @Test("Flexible start and end without a centre share the room like BarFlex")
    func flexibleShare() {
        let even = EdgeBarZoneLayout.place(length: 1000, start: 100, center: 0, end: 100, gap: 8,
                                           flexible: Flex(start: 1, end: 1))
        #expect(even.start == Span(origin: 0, length: 496))
        #expect(even.end == Span(origin: 504, length: 496))
        // Per module, not per zone: two spacers on the left get twice the share.
        let weighted = EdgeBarZoneLayout.place(length: 1000, start: 0, center: 0, end: 0, gap: 8,
                                               flexible: Flex(start: 2, end: 1))
        #expect(abs(weighted.start.length - 2 * weighted.end.length) < 0.001)
        #expect(abs(weighted.end.end - 1000) < 0.001)
        #expect(abs(weighted.start.end + 8 - weighted.end.origin) < 0.001)
    }

    @Test("No room left over: flexible zones keep their natural length")
    func flexibleOverfull() {
        let plain = EdgeBarZoneLayout.place(length: 1000, start: 600, center: 300, end: 200, gap: 8)
        let flex = EdgeBarZoneLayout.place(length: 1000, start: 600, center: 300, end: 200, gap: 8,
                                           flexible: Flex(center: 1))
        #expect(flex == plain)
    }

    @Test("Notch: a flexible centre fills the right area up to the end, a flexible start the left one")
    func flexibleWithNotch() {
        let p = EdgeBarZoneLayout.place(length: 1728, start: 100, center: 0, end: 200, gap: 8, notch: notch,
                                        flexible: Flex(start: 1, center: 1))
        #expect(p.start == Span(origin: 0, length: 763))
        #expect(p.center == Span(origin: 964, length: 556))
        #expect(p.end == Span(origin: 1528, length: 200))
    }

    @Test("Inside a zone the flexible groups share what the fixed ones leave")
    func stackShares() {
        let spans = EdgeBarZoneLayout.stack(naturals: [32, 12, 40], weights: [0, 1, 0], length: 200, spacing: 6)
        #expect(spans == [Span(origin: 0, length: 32), Span(origin: 38, length: 116), Span(origin: 160, length: 40)])
        let tight = EdgeBarZoneLayout.stack(naturals: [32, 12], weights: [0, 1], length: 20, spacing: 6)
        #expect(tight.map(\.length) == [32, 12])
    }

    @Test("Two reservations for one screen key: the larger strip per edge wins")
    func insetsUnion() {
        let a = ReservedInsets(top: 40, left: 44)
        let b = ReservedInsets(left: 30, bottom: 34)
        #expect(a.union(b) == ReservedInsets(top: 40, left: 44, bottom: 34))
        #expect(ReservedInsets.zero.union(a) == a)
    }
}
