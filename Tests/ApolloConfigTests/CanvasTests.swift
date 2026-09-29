import Testing
import Foundation
@testable import ApolloConfig

@Suite("Canvas, Sonne und Mond")
struct CanvasTests {
    static let page = CanvasGeometry(width: 839, height: 392)

    static func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Value {
        CanvasFrame(x: x, y: y, width: w, height: h).value
    }

    static let cases: [FilterCase] = [
        .ok("first-free-frame", .list([]), [.number(275), .number(130)], frame(0, 0, 275, 130)),
        .ok("first-free-frame", .null, [.number(100), .number(100)], .null),
        .ok("first-free-frame", .list([frame(0, 0, 275, 130)]), [.number(275), .number(130)], frame(287, 0, 275, 130)),
        .ok("first-free-frame", .list([frame(0, 0, 839, 392)]), [.number(10), .number(10)], .null),
        .ok("first-free-frame", .list([frame(0, 0, 100, 100)]), [.number(100), .number(100), .number(200), .number(250), .number(0)], frame(100, 0, 100, 100)),
        .fails("first-free-frame", .list([]), [.number(0), .number(10)]),
        .fails("first-free-frame", .string("x"), [.number(10), .number(10)]),
        .fails("first-free-frame", .list([]), [.string("a"), .number(10)]),
        .fails("sun-moon", .date(FilterHarness.now), [.number(95), .number(0)]),
        .fails("sun-moon", .string("x"), [.number(46), .number(9)]),
        .fails("sun-moon", .date(FilterHarness.now), [.number(46)]),
    ]

    @Test("Filter first-free-frame und sun-moon", arguments: CanvasTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("sun-moon liefert Aufgang vor Untergang und eine Mondphase")
    func sunMoonRecord() throws {
        let function = try #require(FilterTable.builtin.function(named: "sun-moon"))
        guard case .value(.record(let record)) = function(.date(FilterHarness.now), [.number(46.85), .number(9.53)], FilterHarness.context) else {
            Issue.record("no record"); return
        }
        guard case .date(let rise)? = record["sunrise"], case .date(let set)? = record["sunset"], case .number(let phase)? = record["moon-phase"] else {
            Issue.record("fields missing"); return
        }
        #expect(rise < set)
        #expect((0..<1).contains(phase))
        #expect(record["moonrise"] == .null)
        let polar = SunMoon.day(Date(timeIntervalSince1970: 1_781_870_400), latitude: 80, longitude: 0)
        #expect(polar.sunrise == nil && polar.alwaysUp)
    }

    @Test("Gültig: innen, Abstand 12, erlaubte Grösse")
    func validity() {
        let a = CanvasFrame(x: 0, y: 0, width: 275, height: 130)
        #expect(Self.page.isValid(CanvasFrame(x: 287, y: 0, width: 100, height: 130), sizes: [], others: [a]))
        #expect(!Self.page.isValid(CanvasFrame(x: 286, y: 0, width: 100, height: 130), sizes: [], others: [a]))
        #expect(!Self.page.isValid(CanvasFrame(x: 800, y: 0, width: 100, height: 130), sizes: [], others: []))
        let sizes = [CanvasSize(minWidth: 200, maxWidth: 839, height: 130)]
        #expect(!Self.page.isValid(CanvasFrame(x: 0, y: 0, width: 150, height: 130), sizes: sizes, others: []))
        #expect(!Self.page.isValid(CanvasFrame(x: 0, y: 0, width: 250, height: 131), sizes: sizes, others: []))
    }

    @Test("Einrasten an Rand und Nachbar, Grösse auf nächste erlaubte Höhe")
    func snapping() {
        let a = CanvasFrame(x: 0, y: 0, width: 275, height: 130)
        let moved = Self.page.snapMove(CanvasFrame(x: 292, y: 5, width: 100, height: 130), others: [a])
        #expect(moved == CanvasFrame(x: 287, y: 0, width: 100, height: 130))
        let far = Self.page.snapMove(CanvasFrame(x: 400.4, y: 100.6, width: 100, height: 100), others: [a])
        #expect(far == CanvasFrame(x: 400, y: 101, width: 100, height: 100))
        let sizes = [CanvasSize(minWidth: 200, maxWidth: 839, height: 130), CanvasSize(minWidth: 200, maxWidth: 839, height: 250)]
        let resized = Self.page.snapResize(CanvasFrame(x: 0, y: 142, width: 300, height: 130), sizes: sizes, proposedWidth: 834, proposedHeight: 240, others: [])
        #expect(resized == CanvasFrame(x: 0, y: 142, width: 839, height: 250))
        #expect(CanvasSize.list(.list([.record(Record([("width", .number(10)), ("height", .number(5))]))])) == [CanvasSize(minWidth: 10, maxWidth: 10, height: 5)])
    }

    @Test("Automatische Skala nach Breite, Regler geklemmt, begrenzt durch Höhe")
    func scale() {
        #expect(CanvasGeometry.scale(screenWidth: 1512, availableHeight: 2000, contentHeight: 0, userScale: 1) == 1)
        #expect(CanvasGeometry.scale(screenWidth: 1000, availableHeight: 2000, contentHeight: 0, userScale: 1) == 0.85)
        #expect(CanvasGeometry.scale(screenWidth: 1512, availableHeight: 2000, contentHeight: 0, userScale: 3) == 1.5)
        #expect(CanvasGeometry.scale(screenWidth: 1512, availableHeight: 400, contentHeight: 800, userScale: 1) == 0.5)
    }

    @Test("canvas im wm-Block bleibt die wm-Einstellung, sonst das Layout")
    func scopedCanvas() {
        let registry = SchemaRegistry.builtin
        #expect(registry.node("canvas")?.category == .layout)
        #expect(registry.node("canvas", in: .wmBlock)?.category == .wmSetting)
        #expect(registry.node("canvas", in: .elementBody)?.category == .layout)
        #expect(registry.allNodes.filter { $0.name == "canvas" }.count == 2)
    }
}
