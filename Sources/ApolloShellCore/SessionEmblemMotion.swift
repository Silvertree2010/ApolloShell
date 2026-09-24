import Foundation

public enum EmblemReaction: String, CaseIterable, Sendable {
    case greet
    case idle
    case sleep
    case farewell
    case think

    public static func reacting(to action: SessionAction?) -> EmblemReaction {
        switch action {
        case nil: .idle
        case .sleep: .sleep
        case .shutDown, .restart: .farewell
        case .logOut: .think
        }
    }

    public static func resting(for action: SessionAction?) -> EmblemReaction {
        let reaction = reacting(to: action)
        return reaction.isOneShot ? .idle : reaction
    }

    public var duration: Double? {
        switch self {
        case .greet: EmblemPose.greetDuration
        case .farewell: EmblemPose.farewellDuration
        case .idle, .sleep, .think: nil
        }
    }

    public var isOneShot: Bool { duration != nil }
}

public struct EmblemPose: Equatable, Sendable {
    public var moonAngle: Double
    public var moonSpeed: Double = EmblemPose.idleSpeed
    public var moonOpacity: Double = 1
    public var orbitOpacity: Double = 1
    public var orbitTilt: Double = 0
    public var planetScale: Double = 1
    public var glow: Double = EmblemPose.restGlow
    public var night: Double = 0
    public var stars: [Double] = [0, 0, 0]
    public var dots: [Double] = [0, 0, 0]
    public var finished = false

    public init(moonAngle: Double) {
        self.moonAngle = moonAngle
    }

    public static let idleSpeed = 2 * Double.pi / 9
    public static let restGlow = 0.45
    static let sleepGlow = 0.04
    public static let greetDuration = 1.4
    public static let farewellDuration = 1.1
    public static let sleepSettle = 2.6
    static let thinkSettle = 0.8
    static let thinkSpeedFactor = 0.3
    static let wobbleDegrees = 7.0
    static let wobblePeriod = 2.8
    static let dotPeriod = 1.2

    public static func at(_ reaction: EmblemReaction, time: Double, startAngle: Double) -> EmblemPose {
        let t = max(0, time)
        var pose = EmblemPose(moonAngle: angle(reaction, t, startAngle))
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
                var phase = (t / dotPeriod - Double(i) * 0.16).truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }
                return ramp * (0.35 + 0.65 * max(0, sin(2 * .pi * phase)))
            }
        }
        return pose
    }

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

    static func angle(_ reaction: EmblemReaction, _ t: Double, _ start: Double) -> Double {
        let w = idleSpeed
        switch reaction {
        case .idle:
            return start + w * t
        case .greet:
            return start + w * t + 2 * .pi * 1.25 * easeOutCubic(clamp01(t / greetDuration))
        case .farewell:
            return start + w * t + 2 * .pi * easeInOutCubic(clamp01(t / farewellDuration))
        case .sleep:
            let p = clamp01(t / sleepSettle)
            return start + w * sleepSettle / 2 * (1 - (1 - p) * (1 - p))
        case .think:
            let p = clamp01(t / thinkSettle)
            let brake = w * (1 - thinkSpeedFactor) * thinkSettle / 2 * (1 - (1 - p) * (1 - p))
            return start + w * thinkSpeedFactor * t + brake
        }
    }

    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeInOutCubic(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
    static func easeInOutSine(_ x: Double) -> Double { (1 - cos(.pi * x)) / 2 }

    static func menuCurve(_ x: Double) -> Double {
        let curve = MotionCurve.spatial
        return cubicBezier(x, curve.x1, curve.y1, curve.x2, curve.y2)
    }

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

public struct EmblemTimeline: Equatable, Sendable {
    public static let restAngle = 0.12 * Double.pi

    public private(set) var reaction: EmblemReaction
    public private(set) var startAngle: Double
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

    public mutating func show(_ next: EmblemReaction, at time: Double) {
        guard next != reaction else { return }
        let angle = pose(at: time).moonAngle.truncatingRemainder(dividingBy: 2 * .pi)
        reaction = next
        startAngle = angle
        startTime = time
    }
}
