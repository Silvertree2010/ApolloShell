import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("Where the zones of the menu bar go")
struct MenuBarZonesTests {
    private typealias Span = MenuBarZoneLayout.Span

    @Test("With room to spare the centre stands in the true middle")
    func centred() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 100, gap: 8)
        #expect(p.start == Span(origin: 0, length: 100))
        #expect(p.center == Span(origin: 400, length: 200))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A long start pushes the centre right, a gap away")
    func pushedByStart() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 500, center: 200, end: 100, gap: 8)
        #expect(p.center.origin == 508)
        #expect(p.center.end + 8 <= p.end.origin)
    }

    @Test("A long end pushes the centre left, a gap away")
    func pushedByEnd() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 500, gap: 8)
        #expect(p.center == Span(origin: 292, length: 200))
        #expect(p.start.end + 8 <= p.center.origin)
    }

    @Test("Too long a start is cut, never laid over centre or end")
    func startCut() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 900, center: 200, end: 100, gap: 8)
        #expect(p.start.length == 684)
        #expect(p.start.end + 8 == p.center.origin)
        #expect(p.center.end + 8 == p.end.origin)
    }

    @Test("Empty zones take neither room nor a gap")
    func emptyZones() {
        let onlyCenter = MenuBarZoneLayout.place(length: 1000, start: 0, center: 200, end: 0, gap: 8)
        #expect(onlyCenter.center == Span(origin: 400, length: 200))
        let onlyEnd = MenuBarZoneLayout.place(length: 1000, start: 0, center: 0, end: 100, gap: 8)
        #expect(onlyEnd.end == Span(origin: 900, length: 100))
        #expect(onlyEnd.start.length == 0 && onlyEnd.center.length == 0)
    }

    @Test("More than fits: the end keeps its length, the centre shrinks to the rest")
    func overfull() {
        let p = MenuBarZoneLayout.place(length: 300, start: 100, center: 200, end: 250, gap: 8)
        #expect(p.end == Span(origin: 50, length: 250))
        #expect(p.center.length == 42)
        #expect(p.start.length == 0)
        #expect(p.center.origin >= 0 && p.center.end + 8 <= p.end.origin)
    }

    private let notch = BarNotch(leftEnd: 771, rightStart: 956)

    @Test("Notch: the start stays left of the housing, centre and end go right of it")
    func notchSplits() {
        let p = MenuBarZoneLayout.place(length: 1728, start: 300, center: 150, end: 200, gap: 8, notch: notch)
        #expect(p.start == Span(origin: 0, length: 300))
        #expect(p.center == Span(origin: 964, length: 150))
        #expect(p.end == Span(origin: 1528, length: 200))
    }

    @Test("Notch: a start longer than the left area is cut a gap short of the housing")
    func notchCutsStart() {
        let p = MenuBarZoneLayout.place(length: 1728, start: 900, center: 0, end: 0, gap: 8, notch: notch)
        #expect(p.start.length == 763)
    }

    @Test("Notch: when centre and end overfill the right area, the centre gives way")
    func notchRightOverfull() {
        let p = MenuBarZoneLayout.place(length: 1728, start: 0, center: 600, end: 300, gap: 8, notch: notch)
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

    private typealias Flex = MenuBarZoneLayout.Flexible

    @Test("A Dock alone in the centre takes the room between start and end")
    func flexibleCenterFills() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 100, center: 0, end: 100, gap: 8,
                                        flexible: Flex(center: 1))
        #expect(p.center == Span(origin: 108, length: 784))
        #expect(p.start == Span(origin: 0, length: 100))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A flexible centre grows evenly on both sides so it stays in the middle")
    func flexibleCenterStaysCentred() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 300, center: 0, end: 100, gap: 8,
                                        flexible: Flex(center: 1))
        #expect(p.center == Span(origin: 308, length: 384))
        #expect(p.center.origin + p.center.length / 2 == 500)
    }

    @Test("A flexible start grows up to the centre, a gap short of it")
    func flexibleStartGrowsToCenter() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 100, gap: 8,
                                        flexible: Flex(start: 1))
        #expect(p.start == Span(origin: 0, length: 392))
        #expect(p.center == Span(origin: 400, length: 200))
        #expect(p.end == Span(origin: 900, length: 100))
    }

    @Test("A flexible end grows towards the centre")
    func flexibleEndGrowsToCenter() {
        let p = MenuBarZoneLayout.place(length: 1000, start: 100, center: 200, end: 50, gap: 8,
                                        flexible: Flex(end: 1))
        #expect(p.end == Span(origin: 608, length: 392))
    }

    @Test("Flexible start and end without a centre share the room like BarFlex")
    func flexibleShare() {
        let even = MenuBarZoneLayout.place(length: 1000, start: 100, center: 0, end: 100, gap: 8,
                                           flexible: Flex(start: 1, end: 1))
        #expect(even.start == Span(origin: 0, length: 496))
        #expect(even.end == Span(origin: 504, length: 496))
        let weighted = MenuBarZoneLayout.place(length: 1000, start: 0, center: 0, end: 0, gap: 8,
                                               flexible: Flex(start: 2, end: 1))
        #expect(abs(weighted.start.length - 2 * weighted.end.length) < 0.001)
        #expect(abs(weighted.end.end - 1000) < 0.001)
        #expect(abs(weighted.start.end + 8 - weighted.end.origin) < 0.001)
    }

    @Test("No room left over: flexible zones keep their natural length")
    func flexibleOverfull() {
        let plain = MenuBarZoneLayout.place(length: 1000, start: 600, center: 300, end: 200, gap: 8)
        let flex = MenuBarZoneLayout.place(length: 1000, start: 600, center: 300, end: 200, gap: 8,
                                           flexible: Flex(center: 1))
        #expect(flex == plain)
    }

    @Test("Notch: a flexible centre fills the right area up to the end, a flexible start the left one")
    func flexibleWithNotch() {
        let p = MenuBarZoneLayout.place(length: 1728, start: 100, center: 0, end: 200, gap: 8, notch: notch,
                                        flexible: Flex(start: 1, center: 1))
        #expect(p.start == Span(origin: 0, length: 763))
        #expect(p.center == Span(origin: 964, length: 556))
        #expect(p.end == Span(origin: 1528, length: 200))
    }

    @Test("Inside a zone the flexible groups share what the fixed ones leave")
    func stackShares() {
        let spans = MenuBarZoneLayout.stack(naturals: [32, 12, 40], weights: [0, 1, 0], length: 200, spacing: 6)
        #expect(spans == [Span(origin: 0, length: 32), Span(origin: 38, length: 116), Span(origin: 160, length: 40)])
        let tight = MenuBarZoneLayout.stack(naturals: [32, 12], weights: [0, 1], length: 20, spacing: 6)
        #expect(tight.map(\.length) == [32, 12])
    }

    private let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    @Test("The popout hangs below the bar, centred on the icon")
    func popoutBelowBar() {
        let bar = CGRect(x: 0, y: 1073, width: 1728, height: 44)
        let icon = CGRect(x: 800, y: 1080, width: 30, height: 30)
        let f = MenuBarPopoutPlacement.frame(icon: icon, bar: bar, size: CGSize(width: 300, height: 200),
                                             screen: screenFrame)
        #expect(f == CGRect(x: 665, y: 867, width: 300, height: 200))
    }

    @Test("An icon in the corner keeps the window on screen")
    func popoutInCorner() {
        let bar = CGRect(x: 0, y: 1073, width: 1728, height: 44)
        let icon = CGRect(x: 1690, y: 1080, width: 30, height: 30)
        let f = MenuBarPopoutPlacement.frame(icon: icon, bar: bar, size: CGSize(width: 300, height: 200),
                                             screen: screenFrame)
        #expect(f == CGRect(x: 1420, y: 867, width: 300, height: 200))
    }

}
