import AppKit
import QuartzCore
import ApolloShellCore

enum MotionEdge: Equatable {
    case top, bottom, left, right, center

    init(anchor: SurfacePlacement.Anchor) {
        switch anchor {
        case .top, .topLeft, .topRight: self = .top
        case .bottom, .bottomLeft, .bottomRight: self = .bottom
        case .left: self = .left
        case .right: self = .right
        case .center, .fill: self = .center
        }
    }
}

struct MotionGeometry: Equatable {
    var edge: MotionEdge
    var size: CGSize
    var topInset: CGFloat
    var flipped: Bool
}

@MainActor
protocol SurfaceAnimator: AnyObject {
    var name: String { get }
    func closedTransform(_ geometry: MotionGeometry) -> CATransform3D
    func transformAnimation(opening: Bool) -> CAAnimation?
    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction)
    func progress(at time: TimeInterval, opening: Bool) -> Double
    func duration(opening: Bool) -> TimeInterval
}

extension SurfaceAnimator {
    func visibleFrame(open frame: CGRect, geometry: MotionGeometry, progress: Double) -> CGRect {
        let closed = closedTransform(geometry)
        let p = CGFloat(progress)
        let scaleX = 1 + (closed.m11 - 1) * (1 - p)
        let scaleY = 1 + (closed.m22 - 1) * (1 - p)
        let width = frame.width * scaleX
        let height = frame.height * scaleY
        let dx = closed.m41 * (1 - p)
        let dy = (geometry.flipped ? -closed.m42 : closed.m42) * (1 - p)
        let pivotX = frame.midX
        let pivotY = frame.minY
        let originX = pivotX - (pivotX - frame.minX) * scaleX + dx
        let originY = pivotY + dy
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}

@MainActor
final class SlideAnimator: SurfaceAnimator {
    let name = "slide"

    func closedTransform(_ geometry: MotionGeometry) -> CATransform3D {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return CATransform3DIdentity }
        let size = geometry.size
        switch geometry.edge {
        case .top: return CATransform3DMakeTranslation(0, size.height + geometry.topInset + 5, 0)
        case .right: return CATransform3DMakeTranslation(size.width + 5, 0, 0)
        case .left: return CATransform3DMakeTranslation(-(size.width + 5), 0, 0)
        case .bottom: return CATransform3DMakeTranslation(0, -(size.height + 5), 0)
        case .center: return CATransform3DIdentity
        }
    }

    func transformAnimation(opening: Bool) -> CAAnimation? {
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.duration = MotionCurve.spatialDuration
        animation.timingFunction = .shellSpatial
        return animation
    }

    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        (MotionCurve.spatialDuration, .shellSpatial)
    }

    func duration(opening: Bool) -> TimeInterval { MotionCurve.spatialDuration }

    func progress(at time: TimeInterval, opening: Bool) -> Double {
        let t = min(1, max(0, time / MotionCurve.spatialDuration))
        let curve = MotionCurve.spatial
        let value = CubicBezier(x1: curve.x1, y1: curve.y1, x2: curve.x2, y2: curve.y2).value(at: t)
        return opening ? value : 1 - value
    }
}

@MainActor
final class GrowAnimator: SurfaceAnimator {
    let name = "grow"
    static let openResponse: Double = 0.42
    static let closeResponse: Double = 0.28
    static let fadeIn: TimeInterval = 0.16
    static let fadeOut: TimeInterval = 0.14
    static let travel: CGFloat = 40
    static let closedScale: CGFloat = 0.92
    static var easeOut: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }

    func closedTransform(_ geometry: MotionGeometry) -> CATransform3D {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return CATransform3DIdentity }
        let size = geometry.size
        let pivot = CGPoint(x: size.width / 2, y: size.height / 2)
        let bottomCenter = CGPoint(x: size.width / 2, y: geometry.flipped ? size.height : 0)
        let dx = bottomCenter.x - pivot.x
        let dy = bottomCenter.y - pivot.y
        let down: CGFloat = geometry.flipped ? 1 : -1
        var transform = CATransform3DMakeTranslation(-dx, -dy, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeScale(Self.closedScale, Self.closedScale, 1))
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(dx, dy + down * Self.travel, 0))
        return transform
    }

    func transformAnimation(opening: Bool) -> CAAnimation? {
        let response = opening ? Self.openResponse : Self.closeResponse
        let spring = CASpringAnimation(keyPath: "sublayerTransform")
        spring.mass = 1
        spring.stiffness = pow(2 * .pi / response, 2)
        spring.damping = 4 * .pi / response
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        return spring
    }

    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        (opening ? Self.fadeIn : Self.fadeOut, Self.easeOut)
    }

    func duration(opening: Bool) -> TimeInterval {
        let omega = 2 * Double.pi / (opening ? Self.openResponse : Self.closeResponse)
        return 10 / omega
    }

    func progress(at time: TimeInterval, opening: Bool) -> Double {
        let omega = 2 * Double.pi / (opening ? Self.openResponse : Self.closeResponse)
        let t = max(0, time)
        let value = 1 - (1 + omega * t) * exp(-omega * t)
        return opening ? value : 1 - value
    }
}

@MainActor
final class FadeAnimator: SurfaceAnimator {
    let name: String
    let seconds: TimeInterval

    init(name: String = "fade", seconds: TimeInterval = 0.2) {
        self.name = name
        self.seconds = seconds
    }

    func closedTransform(_ geometry: MotionGeometry) -> CATransform3D { CATransform3DIdentity }
    func transformAnimation(opening: Bool) -> CAAnimation? { nil }

    func fade(opening: Bool) -> (duration: TimeInterval, curve: CAMediaTimingFunction) {
        (seconds, CAMediaTimingFunction(name: .easeInEaseOut))
    }

    func duration(opening: Bool) -> TimeInterval { seconds }

    func progress(at time: TimeInterval, opening: Bool) -> Double {
        guard seconds > 0 else { return opening ? 1 : 0 }
        let t = min(1, max(0, time / seconds))
        return opening ? t : 1 - t
    }
}

@MainActor
final class AnimatorRegistry {
    private var entries: [String: any SurfaceAnimator] = [:]

    static func builtin() -> AnimatorRegistry {
        let registry = AnimatorRegistry()
        registry.register(SlideAnimator())
        registry.register(GrowAnimator())
        registry.register(FadeAnimator())
        registry.register(FadeAnimator(name: "none", seconds: 0))
        return registry
    }

    var names: [String] { entries.keys.sorted() }

    func register(_ animator: any SurfaceAnimator) {
        entries[animator.name] = animator
    }

    func animator(_ name: String) -> any SurfaceAnimator {
        entries[name] ?? entries["none"] ?? FadeAnimator(name: "none", seconds: 0)
    }
}

struct CubicBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    private func sample(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    func value(at x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<40 {
            let current = sample(x1, x2, t)
            if abs(current - x) < 1e-7 { break }
            if current < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return sample(y1, y2, t)
    }
}

extension CAMediaTimingFunction {
    static var shellSpatial: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(MotionCurve.spatial.x1), Float(MotionCurve.spatial.y1),
                              Float(MotionCurve.spatial.x2), Float(MotionCurve.spatial.y2))
    }
}
