import Foundation

/// Control points of a CSS Bezier curve, `cubic-bezier(x1, y1, x2, y2)`.
public struct MotionCurve: Equatable, Sendable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    /// Caelestia's expressiveDefaultSpatial (plugin/src/Caelestia/Config/
    /// tokens.hpp): slightly overshoots (y1 = 1.21) and settles in. The
    /// shell's default motion for size and position - panels, popout,
    /// toasts, indicators.
    public static let spatial = MotionCurve(0.38, 1.21, 0.22, 1)
    /// Duration Caelestia uses for it.
    public static let spatialDuration: Double = 0.5
}
