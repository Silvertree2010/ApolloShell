import Foundation

/// What the emblem in the middle of the session menu is reacting to.
///
/// The emblem is a small planet in the accent color with a moon circling it on
/// a tilted orbit. Every reaction is only a different motion of the same
/// figure.
public enum EmblemReaction: String, CaseIterable, Sendable {
    /// The menu opens: the planet grows, the moon swings in quickly and
    /// settles at the resting speed.
    case greet
    /// At rest: a slow orbit, the glow of the planet breathes.
    case idle
    /// Sleep: the night side draws in, stars appear, the moon slows down and
    /// comes to a stop.
    case sleep
    /// Shut down and restart: one quick lap, the planet bounces.
    case farewell
    /// Log out: the orbit wobbles, three dots on the planet are thinking.
    case think

    /// The reaction to the button under the mouse or the keyboard selection.
    public static func reacting(to action: SessionAction?) -> EmblemReaction {
        switch action {
        case nil: .idle
        case .sleep: .sleep
        case .shutDown, .restart: .farewell
        case .logOut: .think
        }
    }

    /// What stays after a one-off motion, as long as `action` is active.
    public static func resting(for action: SessionAction?) -> EmblemReaction {
        let reaction = reacting(to: action)
        return reaction.isOneShot ? .idle : reaction
    }

    /// The length of the one-off motions in seconds; `nil` for loops.
    public var duration: Double? {
        switch self {
        case .greet: EmblemPose.greetDuration
        case .farewell: EmblemPose.farewellDuration
        case .idle, .sleep, .think: nil
        }
    }

    public var isOneShot: Bool { duration != nil }
}

/// A snapshot of the emblem. Plain numbers, the drawing happens in the app.
public struct EmblemPose: Equatable, Sendable {
    /// The position of the moon on the orbit in radians. `sin > 0`: in front
    /// of the planet, otherwise behind it.
    public var moonAngle: Double
    /// The angular speed in rad/s; from about twice the resting speed on, the
    /// moon draws a trail.
    public var moonSpeed: Double = EmblemPose.idleSpeed
    public var moonOpacity: Double = 1
    public var orbitOpacity: Double = 1
    /// The extra tilt of the orbit in degrees (the wobble while thinking).
    public var orbitTilt: Double = 0
    public var planetScale: Double = 1
    /// The strength of the glow around the planet, 0...1.
    public var glow: Double = EmblemPose.restGlow
    /// 0 = fully lit, 1 = only a crescent left.
    public var night: Double = 0
    /// The brightness of the three stars, 0...1.
    public var stars: [Double] = [0, 0, 0]
    /// The opacity of the three thinking dots, 0...1.
    public var dots: [Double] = [0, 0, 0]
    /// The one-off motion has arrived at its end.
    public var finished = false

    public init(moonAngle: Double) {
        self.moonAngle = moonAngle
    }

    // MARK: - Constants

    /// One orbit in nine seconds: visible, but calm.
    public static let idleSpeed = 2 * Double.pi / 9
    public static let restGlow = 0.45
    /// In sleep only a breath; more gives a pale halo on a light ground.
    static let sleepGlow = 0.04
    public static let greetDuration = 1.4
    public static let farewellDuration = 1.1
    /// This is how long the moon takes to come to a stop in sleep.
    public static let sleepSettle = 2.6
    /// Down to here the moon slows while thinking.
    static let thinkSettle = 0.8
    static let thinkSpeedFactor = 0.3
    static let wobbleDegrees = 7.0
    static let wobblePeriod = 2.8
    static let dotPeriod = 1.2

    // MARK: - Motion

    /// The pose `time` seconds after the reaction began, with the moon at
    /// `startAngle` at the start. Every reaction but the opening begins in the
    /// resting pose, so that a switch only changes the motion, not the figure.
    public static func at(_ reaction: EmblemReaction, time: Double, startAngle: Double) -> EmblemPose {
        let t = max(0, time)
        var pose = EmblemPose(moonAngle: angle(reaction, t, startAngle))
        // A central difference; before t = 0 the pose stands, hence one-sided.
        let h = 0.01
        pose.moonSpeed = (angle(reaction, t + h, startAngle) - angle(reaction, max(0, t - h), startAngle))
            / (t + h - max(0, t - h))

        switch reaction {
        case .idle:
            let breath = sin(2 * .pi * t / 4.4)
            pose.glow = restGlow + 0.15 * breath
            pose.planetScale = 1 + 0.012 * breath

        case .greet:
            pose.planetScale = 0.7 + 0.3 * menuCurve(clamp01(t / 0.5))
            pose.orbitOpacity = easeOutCubic(clamp01((t - 0.1) / 0.45))
            pose.moonOpacity = easeOutCubic(clamp01((t - 0.15) / 0.35))
            pose.glow = restGlow + 0.4 * pow(sin(.pi * clamp01((t - 0.1) / 1.1)), 2)
            pose.finished = t >= greetDuration

        case .farewell:
            // Press in first, then overshoot slightly and come back.
            let dip = t < 0.35 ? sin(.pi * t / 0.35) : 0
            let rebound = t >= 0.35 ? sin(.pi * clamp01((t - 0.35) / 0.55)) : 0
            pose.planetScale = 1 - 0.1 * dip + 0.04 * rebound
            pose.glow = restGlow + 0.45 * pow(sin(.pi * clamp01(t / farewellDuration)), 2)
            pose.finished = t >= farewellDuration

        case .sleep:
            let dusk = easeInOutSine(clamp01(t / 1.6))
            pose.night = easeInOutSine(clamp01((t - 0.1) / 1.6))
            pose.glow = restGlow - (restGlow - sleepGlow) * dusk
            pose.orbitOpacity = 1 - 0.55 * dusk
            pose.moonOpacity = 1 - 0.35 * dusk
            pose.planetScale = 1 - 0.04 * dusk + 0.006 * sin(2 * .pi * t / 5) * dusk
            let starsIn = easeInOutSine(clamp01((t - 0.5) / 1.2))
            let periods = [2.3, 3.1, 2.7]
            let phases = [0.0, 2.1, 4.0]
            pose.stars = (0..<3).map { i in
                starsIn * (0.6 + 0.4 * sin(2 * .pi * t / periods[i] + phases[i]))
            }

        case .think:
            let ramp = easeInOutSine(clamp01(t / 0.5))
            pose.orbitTilt = wobbleDegrees * sin(2 * .pi * t / wobblePeriod) * ramp
            pose.glow = restGlow + 0.08 * sin(2 * .pi * t / dotPeriod) * ramp
            pose.dots = (0..<3).map { i in
                // The dots light up one after another, as while typing.
                var phase = (t / dotPeriod - Double(i) * 0.16).truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }
                return ramp * (0.35 + 0.65 * max(0, sin(2 * .pi * phase)))
            }
        }
        return pose
    }

    /// A standing pose for "reduce motion": the same statement, no motion, the
    /// moon always in the same place.
    public static func still(_ reaction: EmblemReaction) -> EmblemPose {
        var pose = EmblemPose(moonAngle: EmblemTimeline.restAngle)
        pose.moonSpeed = 0
        switch reaction {
        case .idle, .greet, .farewell:
            break
        case .sleep:
            pose.night = 1
            pose.glow = sleepGlow
            pose.orbitOpacity = 0.45
            pose.moonOpacity = 0.65
            pose.planetScale = 0.96
            pose.stars = [0.95, 0.65, 0.8]
        case .think:
            pose.dots = [1, 0.7, 0.4]
        }
        return pose
    }

    /// The moon position; continuous and without a kink at every change of
    /// reaction, because every reaction begins at the resting speed (and the
    /// one-off motions end at it).
    static func angle(_ reaction: EmblemReaction, _ t: Double, _ start: Double) -> Double {
        let w = idleSpeed
        switch reaction {
        case .idle:
            return start + w * t
        case .greet:
            // One and a quarter extra laps that run out gently.
            return start + w * t + 2 * .pi * 1.25 * easeOutCubic(clamp01(t / greetDuration))
        case .farewell:
            return start + w * t + 2 * .pi * easeInOutCubic(clamp01(t / farewellDuration))
        case .sleep:
            // Slow evenly down to a standstill.
            let p = clamp01(t / sleepSettle)
            return start + w * sleepSettle / 2 * (1 - (1 - p) * (1 - p))
        case .think:
            let p = clamp01(t / thinkSettle)
            let brake = w * (1 - thinkSpeedFactor) * thinkSettle / 2 * (1 - (1 - p) * (1 - p))
            return start + w * thinkSpeedFactor * t + brake
        }
    }

    // MARK: - Curves

    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeInOutCubic(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
    static func easeInOutSine(_ x: Double) -> Double { (1 - cos(.pi * x)) / 2 }

    /// The curve the menu comes in with: cubic-bezier(0.38, 1.21, 0.22, 1),
    /// slightly overshooting.
    static func menuCurve(_ x: Double) -> Double {
        let curve = MotionCurve.spatial
        return cubicBezier(x, curve.x1, curve.y1, curve.x2, curve.y2)
    }

    /// y(x) of a CSS bezier curve; x out of the curve parameter through Newton.
    static func cubicBezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func coordinate(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        func slope(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * a + 6 * (1 - s) * s * (b - a) + 3 * s * s * (1 - b)
        }
        var s = x
        for _ in 0..<8 {
            let d = slope(s, x1, x2)
            guard abs(d) > 1e-6 else { break }
            s -= (coordinate(s, x1, x2) - x) / d
            s = clamp01(s)
        }
        return coordinate(s, y1, y2)
    }
}

/// The running reaction together with its start time. On a switch the new
/// reaction takes over the current moon position, so the moon does not jump.
public struct EmblemTimeline: Equatable, Sendable {
    /// This is where the moon stands without motion: to the right of the
    /// planet, just in front of it on the orbit.
    public static let restAngle = 0.12 * Double.pi

    public private(set) var reaction: EmblemReaction
    public private(set) var startAngle: Double
    /// Seconds, on any time base (the app takes timeIntervalSinceReferenceDate).
    public private(set) var startTime: Double

    public init(_ reaction: EmblemReaction, at time: Double, angle: Double = EmblemTimeline.restAngle) {
        self.reaction = reaction
        self.startTime = time
        self.startAngle = angle
    }

    public func pose(at time: Double) -> EmblemPose {
        EmblemPose.at(reaction, time: time - startTime, startAngle: startAngle)
    }

    public var still: EmblemPose { EmblemPose.still(reaction) }

    /// Switches to `next`; the same reaction goes on undisturbed.
    public mutating func show(_ next: EmblemReaction, at time: Double) {
        guard next != reaction else { return }
        let angle = pose(at: time).moonAngle.truncatingRemainder(dividingBy: 2 * .pi)
        reaction = next
        startAngle = angle
        startTime = time
    }
}
