import ApolloShellCore
import QuartzCore
import SwiftUI

extension Animation {
    /// Die Standardbewegung der Shell (`MotionCurve.spatial`, 500 ms).
    static let shellSpatial = Animation.timingCurve(
        MotionCurve.spatial.x1, MotionCurve.spatial.y1, MotionCurve.spatial.x2, MotionCurve.spatial.y2,
        duration: MotionCurve.spatialDuration
    )
}

extension CAMediaTimingFunction {
    /// Dieselbe Kurve fuer Core Animation (Fenster, die gleiten).
    static var shellSpatial: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(MotionCurve.spatial.x1), Float(MotionCurve.spatial.y1),
                              Float(MotionCurve.spatial.x2), Float(MotionCurve.spatial.y2))
    }
}
