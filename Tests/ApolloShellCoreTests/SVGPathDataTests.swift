import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("SVG path data")
struct SVGPathDataTests {
    @Test("absolute and relative moves, lines and close")
    func linesAndClose() {
        let steps = SVGPathData.parse("M10,20 l5,0 L30 40 h-10 v5 z")
        #expect(steps == [
            .move(CGPoint(x: 10, y: 20)), .line(CGPoint(x: 15, y: 20)), .line(CGPoint(x: 30, y: 40)),
            .line(CGPoint(x: 20, y: 40)), .line(CGPoint(x: 20, y: 45)), .close,
        ])
    }

    @Test("numbers glued together the way Illustrator writes them")
    func gluedNumbers() {
        let steps = SVGPathData.parse("M514.39,417.64c-3.97-6.38-8.65-11.39-16.08-12.89")
        #expect(steps == [
            .move(CGPoint(x: 514.39, y: 417.64)),
            .curve(CGPoint(x: 514.39 - 16.08, y: 417.64 - 12.89),
                   control1: CGPoint(x: 514.39 - 3.97, y: 417.64 - 6.38),
                   control2: CGPoint(x: 514.39 - 8.65, y: 417.64 - 11.39)),
        ])
    }

    @Test("a repeated command without its letter, and a move that turns into lines")
    func implicitRepeats() {
        let steps = SVGPathData.parse("M0,0 10,0 l1,1 1,1")
        #expect(steps == [.move(.zero), .line(CGPoint(x: 10, y: 0)), .line(CGPoint(x: 11, y: 1)), .line(CGPoint(x: 12, y: 2))])
    }

    @Test("s mirrors the previous control point")
    func smoothCurve() {
        let steps = SVGPathData.parse("M0,0 c0,10 10,10 10,0 s10,-10 10,0")
        #expect(steps.last == .curve(CGPoint(x: 20, y: 0), control1: CGPoint(x: 10, y: -10), control2: CGPoint(x: 20, y: -10)))
    }

    @Test("points and exponents", arguments: [
        ("M.5.5", CGPoint(x: 0.5, y: 0.5)),
        ("M1e2,-2E1", CGPoint(x: 100, y: -20)),
        ("M-1-2", CGPoint(x: -1, y: -2)),
    ])
    func numberForms(d: String, point: CGPoint) {
        #expect(SVGPathData.parse(d) == [.move(point)])
    }

    @Test("an unknown command stops the path instead of crashing")
    func unsupported() {
        #expect(SVGPathData.parse("M0,0 L1,1 A5,5 0 0 1 10,10 L2,2") == [.move(.zero), .line(CGPoint(x: 1, y: 1))])
        #expect(SVGPathData.parse("M0,") == [])
        #expect(SVGPathData.parse("") == [])
    }
}
