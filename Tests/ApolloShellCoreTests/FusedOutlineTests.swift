import CoreGraphics
import Testing
@testable import ApolloShellCore

@Suite("The outline of touching shell surfaces as one shape")
struct FusedOutlineTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let rounded = FusionShape(style: .rounded, innerRadius: 14, screenEdge: .flush)

    private func corners(_ pieces: [FusionPiece], shape: FusionShape? = nil) -> [FusedOutline.Corner] {
        FusedOutline.outline(pieces, screen: screen, shape: shape ?? rounded).islands.flatMap { $0 }
    }

    private func corner(at point: CGPoint, in list: [FusedOutline.Corner]) -> FusedOutline.Corner? {
        list.first { abs($0.point.x - point.x) < 0.01 && abs($0.point.y - point.y) < 0.01 }
    }

    @Test("One free rectangle: four convex corners with its own radius")
    func single() {
        let list = corners([FusionPiece(rect: CGRect(x: 100, y: 100, width: 200, height: 100), radius: 10)])
        #expect(list.count == 4)
        #expect(list.allSatisfy { $0.convex && $0.radius == 10 })
    }

    @Test("A popout under a top bar: one island, two concave corners with the fillet radius")
    func popoutUnderBar() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 364, width: 200, height: 200), radius: 16)
        let outline = FusedOutline.outline([bar, popout], screen: screen, shape: rounded)
        #expect(outline.islands.count == 1)
        let list = outline.islands[0]
        let concave = list.filter { !$0.convex }
        #expect(concave.count == 2)
        #expect(concave.allSatisfy { $0.radius == 14 })
        #expect(corner(at: CGPoint(x: 400, y: 364), in: list)?.radius == 16)
        #expect(corner(at: CGPoint(x: 600, y: 364), in: list)?.radius == 16)
    }

    @Test("Flush: corners on the screen edge stay square")
    func flushEdge() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 12)
        let list = corners([bar])
        #expect(list.count == 4)
        #expect(list.allSatisfy { $0.radius == 0 })
        #expect(FusedOutline.outline([bar], screen: screen, shape: rounded).ears.isEmpty)
    }

    @Test("A bar off the edge keeps its round corners away from the edge")
    func sidebarCorners() {
        let side = FusionPiece(rect: CGRect(x: 0, y: 0, width: 44, height: 564), radius: 12)
        let list = corners([side])
        #expect(corner(at: CGPoint(x: 44, y: 564), in: list)?.radius == 12)
        #expect(corner(at: CGPoint(x: 44, y: 0), in: list)?.radius == 0)
        #expect(corner(at: CGPoint(x: 0, y: 564), in: list)?.radius == 0)
    }

    @Test("Rounded screen edge: an ear where a bar leaves the edge, none at screen corners")
    func ears() {
        let shape = FusionShape(style: .rounded, innerRadius: 14, screenEdge: .rounded)
        let side = FusionPiece(rect: CGRect(x: 0, y: 0, width: 44, height: 564), radius: 12)
        let outline = FusedOutline.outline([side], screen: screen, shape: shape)
        #expect(outline.ears.count == 2)
        let up = outline.ears.first { $0.corner == CGPoint(x: 0, y: 564) }
        #expect(up?.alongEdge == CGVector(dx: 0, dy: 1))
        #expect(up?.alongSide == CGVector(dx: 1, dy: 0))
        #expect(up?.radius == 14)
        let right = outline.ears.first { $0.corner == CGPoint(x: 44, y: 0) }
        #expect(right?.alongEdge == CGVector(dx: 1, dy: 0))
        #expect(right?.alongSide == CGVector(dx: 0, dy: 1))
    }

    @Test("Square: no fillets, no ears, outer corners keep their radius")
    func square() {
        let shape = FusionShape(style: .square, innerRadius: 14, screenEdge: .rounded)
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 364, width: 200, height: 200), radius: 16)
        let outline = FusedOutline.outline([bar, popout], screen: screen, shape: shape)
        #expect(outline.islands.flatMap { $0 }.filter { !$0.convex }.allSatisfy { $0.radius == 0 })
        #expect(outline.ears.isEmpty)
        #expect(corner(at: CGPoint(x: 400, y: 364), in: outline.islands[0])?.radius == 16)
    }

    @Test("A short edge caps the radius at half its length")
    func shortEdge() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 554, width: 200, height: 10), radius: 16)
        let list = corners([bar, popout])
        #expect(list.allSatisfy { $0.radius <= 5 }, "\(list)")
    }

    @Test("A gap of up to 1 pt still counts as touching")
    func tolerance() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 363.4, width: 200, height: 200), radius: 16)
        #expect(FusedOutline.outline([bar, popout], screen: screen, shape: rounded).islands.count == 1)
    }

    @Test("Apart by more: two islands")
    func apart() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 358, width: 200, height: 200), radius: 16)
        #expect(FusedOutline.outline([bar, popout], screen: screen, shape: rounded).islands.count == 2)
    }

    @Test("Top bar, sidebar and popout: one island, a fillet where the sidebar meets the bar")
    func tShape() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let side = FusionPiece(rect: CGRect(x: 0, y: 0, width: 44, height: 564), radius: 12)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 364, width: 200, height: 200), radius: 16)
        let outline = FusedOutline.outline([bar, side, popout], screen: screen, shape: rounded)
        #expect(outline.islands.count == 1)
        let joint = corner(at: CGPoint(x: 44, y: 564), in: outline.islands[0])
        #expect(joint?.convex == false)
        #expect(joint?.radius == 14)
    }

    @Test("Empty and degenerate rectangles draw nothing")
    func empty() {
        #expect(FusedOutline.outline([], screen: screen, shape: rounded).islands.isEmpty)
        let flat = FusionPiece(rect: CGRect(x: 10, y: 10, width: 0.2, height: 100), radius: 4)
        #expect(FusedOutline.outline([flat], screen: screen, shape: rounded).islands.isEmpty)
        #expect(FusedOutline.path([], screen: screen, shape: rounded).isEmpty)
    }

    @Test("The path covers the pieces and the fillet, not the far corner")
    func pathContains() {
        let bar = FusionPiece(rect: CGRect(x: 0, y: 564, width: 1000, height: 36), radius: 0)
        let popout = FusionPiece(rect: CGRect(x: 400, y: 364, width: 200, height: 200), radius: 16)
        let path = FusedOutline.path([bar, popout], screen: screen, shape: rounded)
        #expect(path.contains(CGPoint(x: 500, y: 580)))
        #expect(path.contains(CGPoint(x: 500, y: 400)))
        #expect(path.contains(CGPoint(x: 398, y: 562)))
        #expect(!path.contains(CGPoint(x: 380, y: 540)))
        #expect(!path.contains(CGPoint(x: 400.5, y: 364.5)))
    }

    @Test("Rounded screen edge: the ear is part of the path")
    func earInPath() {
        let shape = FusionShape(style: .rounded, innerRadius: 14, screenEdge: .rounded)
        let side = FusionPiece(rect: CGRect(x: 0, y: 0, width: 44, height: 564), radius: 12)
        let path = FusedOutline.path([side], screen: screen, shape: shape)
        #expect(path.contains(CGPoint(x: 1, y: 566)))
        #expect(!path.contains(CGPoint(x: 13, y: 577)))
    }
}

@Suite("Fused outline in the skin's flipped coordinates")
struct FusedOutlineFlippedTests {
    @Test("Menu bar and a sidebar down to the bottom edge: an ear right of the sidebar along the bottom edge")
    func sidebarBelowMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let shape = FusionShape(style: .rounded, innerRadius: 14, screenEdge: .rounded)
        let bar = FusionPiece(rect: CGRect(x: 0, y: 0, width: 1024, height: 33), radius: 0)
        let side = FusionPiece(rect: CGRect(x: 0, y: 33, width: 44, height: 735), radius: 14)
        let outline = FusedOutline.outline([bar, side], screen: screen, shape: shape)
        let ear = outline.ears.first { $0.corner == CGPoint(x: 44, y: 768) }
        #expect(ear?.alongEdge == CGVector(dx: 1, dy: 0), "\(outline)")
        #expect(!outline.ears.contains { $0.corner == CGPoint(x: 0, y: 768) }, "\(outline)")
    }
}
