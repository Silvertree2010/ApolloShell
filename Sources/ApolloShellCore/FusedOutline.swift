import CoreGraphics

public enum FusionStyle: String, CaseIterable, Equatable, Sendable {
    case separate
    case rounded
    case square
}

public enum FusionScreenEdge: String, CaseIterable, Equatable, Sendable {
    case flush
    case rounded
}

public struct FusionShape: Equatable, Sendable {
    public var style: FusionStyle
    public var innerRadius: CGFloat
    public var screenEdge: FusionScreenEdge

    public init(style: FusionStyle, innerRadius: CGFloat, screenEdge: FusionScreenEdge) {
        self.style = style
        self.innerRadius = innerRadius
        self.screenEdge = screenEdge
    }

    public static let standard = FusionShape(style: .rounded, innerRadius: 14, screenEdge: .flush)
}

public struct FusionPiece: Equatable, Sendable {
    public var rect: CGRect
    public var radius: CGFloat

    public init(rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.radius = radius
    }
}

public enum FusedOutline {
    public struct Corner: Equatable, Sendable {
        public var point: CGPoint
        public var convex: Bool
        public var radius: CGFloat
    }

    public struct Ear: Equatable, Sendable {
        public var corner: CGPoint
        public var alongEdge: CGVector
        public var alongSide: CGVector
        public var radius: CGFloat
    }

    public struct Outline: Equatable, Sendable {
        public var islands: [[Corner]]
        public var ears: [Ear]
    }

    static let touching: CGFloat = 1
    static let onPoint: CGFloat = 0.5

    public static func outline(_ pieces: [FusionPiece], screen: CGRect, shape: FusionShape) -> Outline {
        let pieces = snapped(pieces.filter { $0.rect.width > onPoint && $0.rect.height > onPoint })
        guard !pieces.isEmpty else { return Outline(islands: [], ears: []) }
        var union = CGPath(rect: pieces[0].rect, transform: nil)
        for piece in pieces.dropFirst() {
            union = union.union(CGPath(rect: piece.rect, transform: nil))
        }
        let inner = shape.style == .square ? 0 : max(shape.innerRadius, 0)
        var islands: [[Corner]] = []
        var ears: [Ear] = []
        for polygon in polygons(of: union) {
            let points = simplified(polygon)
            guard points.count >= 3 else { continue }
            let count = points.count
            let clockwise = signedArea(points) < 0
            var corners: [Corner] = []
            for index in 0..<count {
                let previous = points[(index - 1 + count) % count]
                let point = points[index]
                let next = points[(index + 1) % count]
                let turn = cross(previous, point, next)
                let convex = (turn > 0) != clockwise
                let edges = screenEdges(of: point, in: screen)
                var radius: CGFloat
                if convex {
                    radius = edges.isEmpty ? outerRadius(at: point, pieces: pieces) : 0
                } else {
                    radius = inner
                }
                let cap = min(distance(previous, point), distance(point, next)) / 2
                radius = min(radius, cap)
                corners.append(Corner(point: point, convex: convex, radius: radius))
                if convex, edges.count == 1, shape.screenEdge == .rounded, inner > 0,
                   let ear = ear(at: point, previous: previous, next: next, screen: screen, radius: inner) {
                    ears.append(ear)
                }
            }
            islands.append(corners)
        }
        return Outline(islands: islands, ears: ears)
    }

    public static func path(_ pieces: [FusionPiece], screen: CGRect, shape: FusionShape) -> CGPath {
        path(outline(pieces, screen: screen, shape: shape))
    }

    public static func path(_ outline: Outline) -> CGPath {
        let result = CGMutablePath()
        for corners in outline.islands where corners.count >= 3 {
            let count = corners.count
            let last = corners[count - 1].point
            let first = corners[0].point
            result.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
            for index in 0..<count {
                let corner = corners[index]
                let next = corners[(index + 1) % count].point
                if corner.radius > 0.01 {
                    result.addArc(tangent1End: corner.point, tangent2End: next, radius: corner.radius)
                } else {
                    result.addLine(to: corner.point)
                }
            }
            result.closeSubpath()
        }
        guard !outline.ears.isEmpty else { return result }
        let ears = CGMutablePath()
        for ear in outline.ears {
            let out = CGPoint(x: ear.corner.x + ear.alongEdge.dx * ear.radius,
                              y: ear.corner.y + ear.alongEdge.dy * ear.radius)
            let side = CGPoint(x: ear.corner.x + ear.alongSide.dx * ear.radius,
                               y: ear.corner.y + ear.alongSide.dy * ear.radius)
            ears.move(to: ear.corner)
            ears.addLine(to: out)
            ears.addArc(tangent1End: ear.corner, tangent2End: side, radius: ear.radius)
            ears.closeSubpath()
        }
        return result.union(ears)
    }

    static func snapped(_ pieces: [FusionPiece]) -> [FusionPiece] {
        let xs = clusters(pieces.flatMap { [$0.rect.minX, $0.rect.maxX] })
        let ys = clusters(pieces.flatMap { [$0.rect.minY, $0.rect.maxY] })
        return pieces.map { piece in
            let minX = xs(piece.rect.minX), maxX = xs(piece.rect.maxX)
            let minY = ys(piece.rect.minY), maxY = ys(piece.rect.maxY)
            return FusionPiece(rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                               radius: piece.radius)
        }
    }

    private static func clusters(_ values: [CGFloat]) -> (CGFloat) -> CGFloat {
        let sorted = values.sorted()
        var anchors: [(value: CGFloat, anchor: CGFloat)] = []
        var anchor = sorted.first ?? 0
        var previous = anchor
        for value in sorted {
            if value - previous > touching { anchor = value }
            anchors.append((value, anchor))
            previous = value
        }
        return { value in anchors.first { $0.value == value }?.anchor ?? value }
    }

    static func polygons(of path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                if !current.isEmpty { result.append(current) }
                current = [element.points[0]]
            case .addLineToPoint:
                current.append(element.points[0])
            case .addQuadCurveToPoint:
                current.append(element.points[1])
            case .addCurveToPoint:
                current.append(element.points[2])
            case .closeSubpath:
                if !current.isEmpty { result.append(current) }
                current = []
            @unknown default:
                break
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    static func simplified(_ polygon: [CGPoint]) -> [CGPoint] {
        var points = polygon.map { CGPoint(x: ($0.x * 64).rounded() / 64, y: ($0.y * 64).rounded() / 64) }
        if let first = points.first, let last = points.last, points.count > 1, distance(first, last) < 0.01 {
            points.removeLast()
        }
        var changed = true
        while changed, points.count >= 3 {
            changed = false
            for index in points.indices {
                let count = points.count
                let previous = points[(index - 1 + count) % count]
                let point = points[index]
                let next = points[(index + 1) % count]
                if distance(previous, point) < 0.01 || abs(cross(previous, point, next)) < 0.01 {
                    points.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return points
    }

    private static func outerRadius(at point: CGPoint, pieces: [FusionPiece]) -> CGFloat {
        let owners = pieces.filter { piece in
            let r = piece.rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
                .contains { distance($0, point) < onPoint }
        }
        return owners.map(\.radius).min() ?? 0
    }

    private enum ScreenSide { case left, right, bottom, top }

    private static func screenEdges(of point: CGPoint, in screen: CGRect) -> [ScreenSide] {
        var sides: [ScreenSide] = []
        if abs(point.x - screen.minX) < onPoint { sides.append(.left) }
        if abs(point.x - screen.maxX) < onPoint { sides.append(.right) }
        if abs(point.y - screen.minY) < onPoint { sides.append(.bottom) }
        if abs(point.y - screen.maxY) < onPoint { sides.append(.top) }
        return sides
    }

    private static func ear(at point: CGPoint, previous: CGPoint, next: CGPoint,
                            screen: CGRect, radius: CGFloat) -> Ear? {
        let sides = screenEdges(of: point, in: screen)
        guard let side = sides.first else { return nil }
        func onSameEdge(_ other: CGPoint) -> Bool { screenEdges(of: other, in: screen).contains(side) }
        let (along, leaving): (CGPoint, CGPoint)
        if onSameEdge(previous), !onSameEdge(next) {
            (along, leaving) = (previous, next)
        } else if onSameEdge(next), !onSameEdge(previous) {
            (along, leaving) = (next, previous)
        } else {
            return nil
        }
        let alongEdge = unit(from: along, to: point)
        let alongSide = unit(from: point, to: leaving)
        let room: CGFloat = switch side {
        case .left, .right: alongEdge.dy > 0 ? screen.maxY - point.y : point.y - screen.minY
        case .bottom, .top: alongEdge.dx > 0 ? screen.maxX - point.x : point.x - screen.minX
        }
        let r = min(radius, room, distance(point, leaving) / 2)
        guard r > 0.01 else { return nil }
        return Ear(corner: point, alongEdge: alongEdge, alongSide: alongSide, radius: r)
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
    }

    private static func signedArea(_ points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let length = distance(a, b)
        guard length > 0 else { return CGVector(dx: 0, dy: 0) }
        return CGVector(dx: ((b.x - a.x) / length).rounded(), dy: ((b.y - a.y) / length).rounded())
    }
}
