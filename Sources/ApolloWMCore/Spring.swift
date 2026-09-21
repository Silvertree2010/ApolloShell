import CoreGraphics
import Foundation

/// A critically damped spring: reaches its target as fast as possible without
/// overshooting. Changing the target mid-flight keeps the current velocity,
/// so interrupted animations (drag start, drop) stay smooth instead of jumping.
public struct Spring: Sendable, Equatable {
    public var value: CGFloat
    public var velocity: CGFloat = 0
    public var target: CGFloat

    public init(_ value: CGFloat) {
        self.value = value
        self.target = value
    }

    public var isSettled: Bool {
        abs(value - target) < 0.5 && abs(velocity) < 5
    }

    /// Advances by `dt` seconds. `response` is roughly how long a move takes.
    /// Uses the closed-form solution, so large or uneven steps stay stable.
    public mutating func step(_ dt: CGFloat, response: CGFloat) {
        let omega = 2 * .pi / response
        let delta = value - target
        let c = velocity + omega * delta
        let decay = exp(-omega * dt)
        value = target + (delta + c * dt) * decay
        velocity = (velocity - omega * c * dt) * decay
        if isSettled {
            value = target
            velocity = 0
        }
    }
}

/// Four springs, one per frame component.
public struct AnimatedRect: Sendable, Equatable {
    public var x, y, width, height: Spring

    public init(_ rect: CGRect) {
        x = Spring(rect.minX)
        y = Spring(rect.minY)
        width = Spring(rect.width)
        height = Spring(rect.height)
    }

    public var current: CGRect {
        CGRect(x: x.value, y: y.value, width: width.value, height: height.value)
    }

    public var target: CGRect {
        get { CGRect(x: x.target, y: y.target, width: width.target, height: height.target) }
        set {
            x.target = newValue.minX
            y.target = newValue.minY
            width.target = newValue.width
            height.target = newValue.height
        }
    }

    public var isSettled: Bool {
        x.isSettled && y.isSettled && width.isSettled && height.isSettled
    }

    public mutating func step(_ dt: CGFloat, response: CGFloat) {
        x.step(dt, response: response)
        y.step(dt, response: response)
        width.step(dt, response: response)
        height.step(dt, response: response)
    }
}
