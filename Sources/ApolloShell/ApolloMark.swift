import ApolloShellCore
import SwiftUI

/// The ApolloShell mark (the logo of 0.2: an A with an orbit and a moon),
/// drawn from the logo's own SVG paths, so the bar shows the logo and not
/// a redrawing of it.
///
/// Layers, back to front: the back arc of the ring, the moon while it is
/// behind, the A, the front arc, the moon while it is in front. The ring
/// already runs through the A in the artwork (gaps in the A where the front
/// arc crosses), so only the moon has to be sorted.
///
/// `orbit` 0...1 moves the moon once around its path and back to where the
/// logo has it; 0 is the logo as drawn. The path is an ellipse fitted to
/// the two ring arcs (least squares over points sampled from the curves,
/// 21.09.): centre (501.4, 497.8), tilted by -18.4°, semi-axes scaled so
/// that the moon's centre in the logo lies on it.
struct ApolloMark: View {
    var orbit: Double = 0

    var body: some View {
        ApolloMarkShape(orbit: orbit)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// The whole mark as one path, filled once: in one colour the layers do
/// not matter (the moon behind the A is hidden either way), and separate
/// fills with a translucent colour such as `.primary` darkened every
/// overlap. A shape so that `orbit` animates.
private struct ApolloMarkShape: Shape {
    var orbit: Double

    var animatableData: Double {
        get { orbit }
        set { orbit = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ApolloMarkGeometry.outline(orbit: orbit).applying(ApolloMarkGeometry.transform(into: rect))
    }
}

enum ApolloMarkGeometry {
    /// Centred on the ring's centre, so the mark sits in the middle of its
    /// frame (the artwork's own box, x 90...926, is not); large enough for
    /// the moon at the far ends of its orbit.
    static let viewBox = CGRect(x: 501.4 - 470, y: 497.8 - 470, width: 940, height: 940)

    /// From the view box into a frame, centred and kept square.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let scale = side / viewBox.width
        return CGAffineTransform(translationX: rect.minX + (rect.width - side) / 2 - viewBox.minX * scale,
                                 y: rect.minY + (rect.height - side) / 2 - viewBox.minY * scale)
            .scaledBy(x: scale, y: scale)
    }

    /// The A, straight from the logo (with the gaps where the ring passes in
    /// front of it).
    static let letter: Path = {
        var path = Path()
        for d in [SVG.aTop, SVG.rightLeg, SVG.leftLeg] { path.addPath(Path(svg: d)) }
        return path
    }()

    // The orbit: an ellipse fitted to the logo's two ring arcs (least
    // squares over points sampled from the curves, 21.09.).
    static let center = CGPoint(x: 501.4, y: 497.8)
    /// Along the long axis (to the upper right) and the short one (down).
    private static let major = CGVector(dx: 0.9488, dy: -0.3159)
    private static let minor = CGVector(dx: 0.3159, dy: 0.9488)
    private static let a: CGFloat = 424.9
    private static let b: CGFloat = 92.6

    /// The ring: the logo's two arcs, except around the moon's resting
    /// place, where the logo leaves a break under the moon - with the moon
    /// moving on, that break showed as a hole (21.09.). There the arcs are
    /// cut off square to the ring (at 36° and 62°) and a band along the
    /// ring's middle line takes over, as wide as the logo's ring at both
    /// cuts (43.8 and 39.2, measured on the SVG).
    private static let bridgeStart = 36 * Double.pi / 180
    private static let bridgeEnd = 62 * Double.pi / 180
    private static let bridge = band(from: bridgeStart, to: bridgeEnd, startWidth: 43.8, endWidth: 39.2)
    private static let bridgeCut = band(from: bridgeStart, to: bridgeEnd, startWidth: 200, endWidth: 200)
    static let ringBack = Path(svg: SVG.ringBack).subtracting(bridgeCut)
    static let ringFront = Path(svg: SVG.ringFront).subtracting(bridgeCut).union(bridge)
    /// The air around the moon, towards the ring and (in front) the A - as
    /// wide as the gaps the logo leaves where the ring crosses the A.
    static let moonGap: CGFloat = 16

    /// The whole mark as one outline, in the logo's coordinates, with the
    /// moon at `orbit` (0 = where the logo has it). The gap around the moon
    /// travels with it: cut out of the ring always, out of the A only while
    /// the moon is in front of it.
    static func outline(orbit: Double = 0) -> Path {
        let moon = moon(at: orbit)
        let gap = circle(moon.center, moon.radius + moonGap)
        let rings = ringBack.union(ringFront).subtracting(gap)
        let a = moon.inFront ? letter.subtracting(gap) : letter
        return a.union(rings).union(circle(moon.center, moon.radius))
    }

    /// The resting mark as a template image for the menu bar: fitted to the
    /// artwork itself (not the roomier view box, the moon does not move
    /// there), so it is as large as the bar allows.
    static func menuBarImage(side: CGFloat) -> NSImage {
        let path = outline()
        let bounds = path.boundingRect
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min(rect.width / bounds.width, rect.height / bounds.height)
            context.translateBy(x: (rect.width - bounds.width * scale) / 2, y: (rect.height - bounds.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.addPath(path.cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nexus"
        return image
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    /// The ring's middle line in the logo is not quite the fitted ellipse:
    /// these are the distances from the ellipse to it, along its normal,
    /// every 3° of `angle`, measured on the SVG (ray casting across the ring
    /// arcs, smoothed; where the A hides the ring or at the break, filled in
    /// between). The moon runs on this line, so it stays in the middle of
    /// the ring all the way round.
    private static let offsets: [CGFloat] = [
        16.1, 15.0, 14.6, 14.1, 13.3, 12.6, 11.4, 9.4, 7.1, 5.3, 4.4, 4.0,
        3.5, 3.0, 2.4, 1.8, 1.1, 0.5, -0.1, -0.8, -1.4, -2.2, -3.1, -3.8,
        -4.1, -4.0, -3.8, -3.2, -2.6, -1.9, -1.2, -0.4, 0.6, 1.8, 2.9, 4.1,
        5.2, 6.2, 7.0, 7.8, 8.7, 9.4, 10.2, 10.9, 11.6, 12.4, 13.1, 13.9,
        14.8, 15.9, 17.1, 18.7, 20.7, 22.3, 22.9, 22.3, 21.1, 20.0, 18.9, 17.7,
        16.6, 15.4, 14.3, 13.2, 12.0, 10.9, 9.7, 8.6, 6.7, 4.3, 1.8, 0.1,
        -1.2, -2.3, -3.4, -4.5, -5.7, -6.9, -8.2, -10.3, -12.6, -14.3, -14.4, -13.8,
        -13.1, -12.4, -11.8, -11.1, -10.4, -9.7, -9.1, -8.4, -7.7, -7.0, -6.4, -5.7,
        -5.0, -4.3, -3.5, -3.0, -2.6, -2.6, -2.5, -2.1, -1.6, -1.0, -0.3, 0.6,
        1.7, 3.0, 4.6, 6.6, 9.5, 12.3, 14.6, 15.8, 16.8, 17.8, 18.2, 17.3,
    ]

    /// Where the moon rests: the point on the ring's middle line nearest to
    /// where the logo has it (cx 779.19, cy 472.95), 6 units from it.
    static let restAngle = 50 * Double.pi / 180
    static let radius: CGFloat = 51.29

    private static func ellipse(_ angle: Double) -> (point: CGPoint, normal: CGVector) {
        let (c, s) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
        let point = CGPoint(x: center.x + a * c * major.dx + b * s * minor.dx,
                            y: center.y + a * c * major.dy + b * s * minor.dy)
        let tx = -a * s * major.dx + b * c * minor.dx
        let ty = -a * s * major.dy + b * c * minor.dy
        let length = max(hypot(tx, ty), 0.001)
        return (point, CGVector(dx: -ty / length, dy: tx / length))
    }

    private static func offset(_ angle: Double) -> CGFloat {
        var degrees = angle * 180 / .pi
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        let position = degrees / 3
        let index = Int(position)
        let t = CGFloat(position - Double(index))
        return offsets[index % offsets.count] * (1 - t) + offsets[(index + 1) % offsets.count] * t
    }

    /// A point on the ring's middle line. The near half (in front of the A)
    /// is where `sin(angle) > 0`, as with the old emblem's orbit.
    static func orbitPoint(_ angle: Double) -> CGPoint {
        let (point, normal) = ellipse(angle)
        let o = offset(angle)
        return CGPoint(x: point.x + normal.dx * o, y: point.y + normal.dy * o)
    }

    // Even speed. The orbit is a flat ellipse (425 by 93): stepping its
    // angle evenly moved the moon nearly five times slower at the two ends
    // than in front and behind, and it crawled there (21.09.). The moon's
    // clock therefore runs in "phase", and `angle(forPhase:)` turns that
    // into the orbit angle that lies as far along the ring as the phase
    // says - equal steps of phase, equal steps of path.

    private static let lengthTable: [Double] = {
        let steps = 720
        var table = [0.0]
        var previous = orbitPoint(0)
        for i in 1...steps {
            let p = orbitPoint(2 * .pi * Double(i) / Double(steps))
            table.append(table[i - 1] + Double(hypot(p.x - previous.x, p.y - previous.y)))
            previous = p
        }
        return table
    }()

    /// The orbit angle for a phase (both in radians, any number of turns).
    static func angle(forPhase phase: Double) -> Double {
        let turns = (phase / (2 * .pi)).rounded(.down)
        let target = (phase / (2 * .pi) - turns) * lengthTable.last!
        var low = 0
        var high = lengthTable.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if lengthTable[mid] < target { low = mid } else { high = mid }
        }
        let span = lengthTable[high] - lengthTable[low]
        let t = span > 0 ? (target - lengthTable[low]) / span : 0
        let steps = Double(lengthTable.count - 1)
        return (turns + (Double(low) + t) / steps) * 2 * .pi
    }

    /// The phase for an orbit angle: the inverse of `angle(forPhase:)`.
    static func phase(forAngle angle: Double) -> Double {
        let turns = (angle / (2 * .pi)).rounded(.down)
        let position = (angle / (2 * .pi) - turns) * Double(lengthTable.count - 1)
        let index = min(Int(position), lengthTable.count - 2)
        let t = position - Double(index)
        let length = lengthTable[index] + (lengthTable[index + 1] - lengthTable[index]) * t
        return (turns + length / lengthTable.last!) * 2 * .pi
    }

    /// A piece of ring as a filled band along the middle line, its width
    /// going evenly from one end to the other.
    private static func band(from start: Double, to end: Double, startWidth: CGFloat, endWidth: CGFloat) -> Path {
        let steps = 32
        var outer: [CGPoint] = []
        var inner: [CGPoint] = []
        for i in 0...steps {
            let angle = start + (end - start) * Double(i) / Double(steps)
            let p = orbitPoint(angle)
            let n = ellipse(angle).normal
            let width = startWidth + (endWidth - startWidth) * CGFloat(i) / CGFloat(steps)
            outer.append(CGPoint(x: p.x + n.dx * width / 2, y: p.y + n.dy * width / 2))
            inner.append(CGPoint(x: p.x - n.dx * width / 2, y: p.y - n.dy * width / 2))
        }
        var path = Path()
        path.addLines(outer + inner.reversed())
        path.closeSubpath()
        return path
    }

    /// The triangle inside the A, above the ring: room for the thinking dots.
    static let counter = CGPoint(x: 492, y: 505)

    /// Position, size and layer of the moon at `orbit` 0...1. In front while
    /// on the near half of the ring (the lower one); a touch smaller at the
    /// back, for depth.
    static func moon(at orbit: Double) -> (center: CGPoint, radius: CGFloat, inFront: Bool) {
        let angle = self.angle(forPhase: phase(forAngle: restAngle) + 2 * .pi * orbit)
        let s = CGFloat(sin(angle))
        let depth = (s + 1) / 2
        let rest = (CGFloat(sin(restAngle)) + 1) / 2
        let size = radius * (0.84 + 0.16 * depth) / (0.84 + 0.16 * rest)
        return (orbitPoint(angle), size, s > 0)
    }

    private enum SVG {
    static let aTop = "M514.39,417.64c-3.97-6.38-8.65-11.39-16.08-12.89-7.37-1.49-16.3,2.19-20.53,9.32-32.13,54.22-62.79,108.84-93.11,164.14l-9.01,17.51c-57.73,11.29-115.31,21.9-174.3,21.61l33.91-61.1,47.23-86,141.6-252.01c9.36-16.65,25.94-27.61,43.75-33.38,19.24-6.23,39.54-5.72,58.63.09,21.22,6.46,36.97,20.99,47.28,40.29l25.3,47.35,45.81,88.01,41.13,79.18,23.22,44.55-32.27,18.52-23.8,12.17c-25.11,11.29-50.64,20.55-76.6,29.19l-26.36-55.18-35.82-71.37Z"
    static let rightLeg = "M735.38,812.59c-26.67-10.04-41.58-32.77-54.12-56.95l-36.95-72.11-44.49-90.23c40.73-13.58,79.74-29.5,117.96-48.56l18.04-9.39,34.66,65.65,42.8,81.52,16.48,33.03c9.68,19.39,10.08,41.3,0,60.61-17.75,33.99-57.9,50.16-94.39,36.43Z"
    static let leftLeg = "M184.85,814.48c-40.83-12.47-58.8-59.37-38.95-95.62l27.51-50.24c21.47,1.99,42.06,1.46,63.62.06,36.29-2.36,71.49-7.15,107.76-12.53l-35.78,64.15-30.65,54.65c-20.12,31.14-56.36,50.89-93.52,39.54Z"
    static let ringFront = "M722.71,487.88c3.94,13.73,11.04,25.64,23.02,34.03l-69.68,34.02-40.97,16.78c-55.8,21.22-112.65,38.67-170.78,53.02-42.14,10.4-84.35,18.12-127.23,24.22-29.13,4.14-57.3,7.96-86.54,10.47-42.67,3.66-114.07,6.66-147.8-18.94-12.22-9.28-16.06-24.06-10.01-38.13,8.87-20.6,30.06-38.92,48.21-52.84,20.99-16.1,42.74-29.92,65.4-43.69,22.56-13.66,44.93-26.06,69.48-36.89l-11.31,20.01c-22.53,14.55-44.23,29.05-65.52,45.25-14.05,10.7-27.26,21.28-39.69,33.69s-26,31.77-10.02,43.63c15.59,11.57,47.79,12.09,68.51,11.73,40.91-.71,83.49-6.91,123.83-14.55l121.56-26.02c38.22-8.18,74.92-19.55,112.11-31.39,27.04-8.61,53.01-17.75,79.1-28.75,23.6-10.05,45.68-21.28,68.31-35.64Z"
    static let ringBack = "M818.88,428.3c13.66-10.27,31.73-22.94,38.85-37.31,4.32-8.72,1.81-18.5-6.31-24.12-21.92-15.17-67.37-14.91-95.42-13.53-34.56,1.71-67.91,7.07-101.92,13.85l-8.85-17.17c24.03-7.58,47.82-13.05,72.69-17.17,47.59-7.88,101.7-13.38,148.74-3.97,19.51,3.9,39.99,10.69,52.16,26.44,19.35,25.05-6.63,55.25-27.76,73.22-16.87,14.25-34.53,26.78-53.61,38.9-1.24-15.11-7.25-28.42-18.57-39.15Z"
    }
}

extension Path {
    /// A path out of SVG path data (`SVGPathData`), in the SVG's own
    /// coordinates (y down, as in SwiftUI).
    init(svg d: String) {
        self.init()
        for step in SVGPathData.parse(d) {
            switch step {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .curve(let p, let c1, let c2): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
}
