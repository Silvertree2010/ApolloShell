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

    @Test("Two reservations for one screen key: the larger strip per edge wins")
    func insetsUnion() {
        let a = ReservedInsets(top: 40, left: 44)
        let b = ReservedInsets(left: 30, bottom: 34)
        #expect(a.union(b) == ReservedInsets(top: 40, left: 44, bottom: 34))
        #expect(ReservedInsets.zero.union(a) == a)
    }
}
