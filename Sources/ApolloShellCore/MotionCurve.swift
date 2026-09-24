import Foundation

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

    public static let spatial = MotionCurve(0.38, 1.21, 0.22, 1)
    public static let spatialDuration: Double = 0.5
}
