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
        ZStack {
            ApolloMarkPart(path: ApolloMarkGeometry.ringBack)
            ApolloMarkMoon(orbit: orbit, inFront: false)
            ApolloMarkPart(path: ApolloMarkGeometry.letter)
            ApolloMarkPart(path: ApolloMarkGeometry.ringFront)
            ApolloMarkMoon(orbit: orbit, inFront: true)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One fixed part of the mark, fitted from the artwork's view box into the
/// frame.
private struct ApolloMarkPart: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        path.applying(ApolloMarkGeometry.transform(into: rect))
    }
}

/// The moon, on its own layer: empty while it is on the other half of its
/// orbit. A shape so that `orbit` animates (a view would not).
private struct ApolloMarkMoon: Shape {
    var orbit: Double
    let inFront: Bool

    var animatableData: Double {
        get { orbit }
        set { orbit = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let moon = ApolloMarkGeometry.moon(at: orbit)
        guard moon.inFront == inFront else { return Path() }
        let circle = Path(ellipseIn: CGRect(x: moon.center.x - moon.radius, y: moon.center.y - moon.radius,
                                            width: 2 * moon.radius, height: 2 * moon.radius))
        return circle.applying(ApolloMarkGeometry.transform(into: rect))
    }
}

enum ApolloMarkGeometry {
    /// The artwork's bounding box is x 90...926, y 180...818 of its
    /// 1000 x 1000 canvas; this square leaves room for the moon at the far
    /// ends of its orbit.
    static let viewBox = CGRect(x: 60, y: 60, width: 880, height: 880)

    /// From the view box into a frame, centred and kept square.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let side = min(rect.width, rect.height)
        let scale = side / viewBox.width
        return CGAffineTransform(translationX: rect.minX + (rect.width - side) / 2 - viewBox.minX * scale,
                                 y: rect.minY + (rect.height - side) / 2 - viewBox.minY * scale)
            .scaledBy(x: scale, y: scale)
    }

    static let letter: Path = {
        var path = Path()
        for d in [SVG.aTop, SVG.rightLeg, SVG.leftLeg] { path.addPath(Path(svg: d)) }
        return path
    }()
    static let ringFront = Path(svg: SVG.ringFront)
    static let ringBack = Path(svg: SVG.ringBack)

    // The orbit.
    static let center = CGPoint(x: 501.4, y: 497.8)
    /// Along the long axis (to the upper right) and the short one (down).
    private static let major = CGVector(dx: 0.9488, dy: -0.3159)
    private static let minor = CGVector(dx: 0.3159, dy: 0.9488)
    private static let a: CGFloat = 400.4
    private static let b: CGFloat = 87.3
    /// Where the logo has the moon: cx 779.19, cy 472.95, r 51.29.
    static let restAngle = atan2(0.735, 0.678)
    static let radius: CGFloat = 51.29

    /// A point on the orbit. The near half (in front of the A) is where
    /// `sin(angle) > 0`, as with the old emblem's orbit.
    static func orbitPoint(_ angle: Double) -> CGPoint {
        let (c, s) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
        return CGPoint(x: center.x + a * c * major.dx + b * s * minor.dx,
                       y: center.y + a * c * major.dy + b * s * minor.dy)
    }

    /// The triangle inside the A, above the ring: room for the thinking dots.
    static let counter = CGPoint(x: 492, y: 505)

    /// Position, size and layer of the moon at `orbit` 0...1. In front while
    /// on the near half of the ring (the lower one); a touch smaller at the
    /// back, for depth.
    static func moon(at orbit: Double) -> (center: CGPoint, radius: CGFloat, inFront: Bool) {
        guard orbit > 0, orbit < 1 else {
            return (CGPoint(x: 779.19, y: 472.95), radius, true)
        }
        let angle = restAngle + 2 * .pi * orbit
        let s = CGFloat(sin(angle))
        let point = orbitPoint(angle)
        let depth = (s + 1) / 2
        let rest = (CGFloat(0.735) + 1) / 2
        let size = radius * (0.84 + 0.16 * depth) / (0.84 + 0.16 * rest)
        return (point, size, s > 0)
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
