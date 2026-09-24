import ApolloShellCore
import QuartzCore
import SwiftUI

extension Animation {
    static let shellSpatial = Animation.timingCurve(
        MotionCurve.spatial.x1, MotionCurve.spatial.y1, MotionCurve.spatial.x2, MotionCurve.spatial.y2,
        duration: MotionCurve.spatialDuration
    )
}

extension CAMediaTimingFunction {
    static var shellSpatial: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(MotionCurve.spatial.x1), Float(MotionCurve.spatial.y1),
                              Float(MotionCurve.spatial.x2), Float(MotionCurve.spatial.y2))
    }
}
