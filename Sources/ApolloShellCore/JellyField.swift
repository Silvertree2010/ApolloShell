import CoreGraphics
import Foundation

public enum JellyStrength: String, CaseIterable, Equatable, Sendable {
    case off
    case subtle
    case strong
}

public struct JellySpringParameters: Equatable, Sendable {
    public var stiffness: Double
    public var dampingRatio: Double

    public init(stiffness: Double, dampingRatio: Double) {
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    public init?(strength: JellyStrength, speed: Double, reduceMotion: Bool = false) {
        guard !reduceMotion, speed > 0 else { return nil }
        switch strength {
        case .off: return nil
        case .subtle: self.init(stiffness: 320 * speed * speed, dampingRatio: 0.8)
        case .strong: self.init(stiffness: 220 * speed * speed, dampingRatio: 0.45)
        }
    }

    var omega: Double { stiffness.squareRoot() }
    var damping: Double { 2 * dampingRatio * omega }
}

public enum JellySide: Equatable, Sendable {
    case minX, maxX, minY, maxY
}

public struct JellyField: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var id: String
        public var piece: FusionPiece
    }

    struct Spring: Equatable, Sendable {
        var value: Double
        var velocity: Double = 0
        var target: Double

        init(_ value: Double) {
            self.value = value
            target = value
        }

        var isResting: Bool { abs(value - target) < 0.25 && abs(velocity) < 1 }
    }

    struct Body: Equatable, Sendable {
        var minX: Spring, minY: Spring, maxX: Spring, maxY: Spring
        var radius: CGFloat
        var leaving = false

        init(_ rect: CGRect, radius: CGFloat) {
            minX = Spring(rect.minX)
            minY = Spring(rect.minY)
            maxX = Spring(rect.maxX)
            maxY = Spring(rect.maxY)
            self.radius = radius
        }

        var rect: CGRect {
            let x0 = min(minX.value, maxX.value), x1 = max(minX.value, maxX.value)
            let y0 = min(minY.value, maxY.value), y1 = max(minY.value, maxY.value)
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }

        var isResting: Bool { minX.isResting && minY.isResting && maxX.isResting && maxY.isResting }

        mutating func aim(at rect: CGRect) {
            minX.target = rect.minX
            minY.target = rect.minY
            maxX.target = rect.maxX
            maxY.target = rect.maxY
        }

        mutating func place(at rect: CGRect) {
            let radius = radius
            self = Body(rect, radius: radius)
        }
    }

    public var parameters: JellySpringParameters? {
        didSet { if parameters == nil { settle() } }
    }

    private(set) var bodies: [String: Body] = [:]

    static let neighbourShare = 0.2
    static let maxStep = 1.0 / 30
    static let subStep = 1.0 / 240

    public init(parameters: JellySpringParameters?) {
        self.parameters = parameters
    }

    public var pieces: [Entry] {
        bodies.keys.sorted().compactMap { id in
            bodies[id].map { Entry(id: id, piece: FusionPiece(rect: $0.rect, radius: $0.radius)) }
        }
    }

    public var isResting: Bool { bodies.values.allSatisfy(\.isResting) }

    public mutating func set(_ id: String, rect: CGRect, radius: CGFloat, grow: JellySide?) {
        guard let parameters else {
            bodies[id] = Body(rect, radius: radius)
            return
        }
        guard var body = bodies[id] else {
            let start = grow.map { Self.collapsed(rect, into: $0) } ?? rect
            var body = Body(start, radius: radius)
            body.aim(at: rect)
            bodies[id] = body
            return
        }
        let old = CGRect(x: body.minX.target, y: body.minY.target,
                         width: body.maxX.target - body.minX.target, height: body.maxY.target - body.minY.target)
        body.leaving = false
        body.radius = radius
        body.aim(at: rect)
        bodies[id] = body
        push(neighboursOf: id, from: old, to: rect, omega: parameters.omega)
    }

    public mutating func remove(_ id: String, into side: JellySide?) {
        guard var body = bodies[id] else { return }
        guard parameters != nil, let side else {
            bodies[id] = nil
            return
        }
        let target = CGRect(x: body.minX.target, y: body.minY.target,
                            width: body.maxX.target - body.minX.target, height: body.maxY.target - body.minY.target)
        body.aim(at: Self.collapsed(target, into: side))
        body.leaving = true
        bodies[id] = body
    }

    public mutating func removeAll() {
        bodies.removeAll()
    }

    public mutating func step(_ seconds: Double) {
        guard let parameters else { return }
        var left = min(max(seconds, 0), Self.maxStep)
        while left > 0 {
            let dt = min(left, Self.subStep)
            for id in bodies.keys {
                guard var body = bodies[id] else { continue }
                Self.advance(&body.minX, dt, parameters)
                Self.advance(&body.minY, dt, parameters)
                Self.advance(&body.maxX, dt, parameters)
                Self.advance(&body.maxY, dt, parameters)
                bodies[id] = body
            }
            left -= dt
        }
        for (id, body) in bodies where body.isResting {
            if body.leaving {
                bodies[id] = nil
            } else {
                var still = body
                still.place(at: CGRect(x: body.minX.target, y: body.minY.target,
                                       width: body.maxX.target - body.minX.target,
                                       height: body.maxY.target - body.minY.target))
                bodies[id] = still
            }
        }
    }

    private static func advance(_ spring: inout Spring, _ dt: Double, _ parameters: JellySpringParameters) {
        guard !spring.isResting else {
            spring.value = spring.target
            spring.velocity = 0
            return
        }
        let force = -parameters.stiffness * (spring.value - spring.target) - parameters.damping * spring.velocity
        spring.velocity += force * dt
        spring.value += spring.velocity * dt
    }

    private mutating func settle() {
        for (id, body) in bodies {
            if body.leaving {
                bodies[id] = nil
            } else {
                var still = body
                still.place(at: CGRect(x: body.minX.target, y: body.minY.target,
                                       width: body.maxX.target - body.minX.target,
                                       height: body.maxY.target - body.minY.target))
                bodies[id] = still
            }
        }
    }

    static func collapsed(_ rect: CGRect, into side: JellySide) -> CGRect {
        switch side {
        case .minX: CGRect(x: rect.minX, y: rect.minY, width: 0, height: rect.height)
        case .maxX: CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height)
        case .minY: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0)
        case .maxY: CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: 0)
        }
    }

    private mutating func push(neighboursOf id: String, from old: CGRect, to new: CGRect, omega: Double) {
        let touch = FusedOutline.touching
        func overlaps(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> Bool {
            min(a1, b1) - max(a0, b0) > touch
        }
        for other in bodies.keys where other != id {
            guard var body = bodies[other], !body.leaving else { continue }
            let target = CGRect(x: body.minX.target, y: body.minY.target,
                                width: body.maxX.target - body.minX.target, height: body.maxY.target - body.minY.target)
            let share = Self.neighbourShare * omega
            if overlaps(old.minY, old.maxY, target.minY, target.maxY) {
                if new.maxX != old.maxX, abs(target.minX - old.maxX) <= touch {
                    body.minX.velocity += share * (new.maxX - old.maxX)
                }
                if new.minX != old.minX, abs(target.maxX - old.minX) <= touch {
                    body.maxX.velocity += share * (new.minX - old.minX)
                }
            }
            if overlaps(old.minX, old.maxX, target.minX, target.maxX) {
                if new.maxY != old.maxY, abs(target.minY - old.maxY) <= touch {
                    body.minY.velocity += share * (new.maxY - old.maxY)
                }
                if new.minY != old.minY, abs(target.maxY - old.minY) <= touch {
                    body.maxY.velocity += share * (new.minY - old.minY)
                }
            }
            bodies[other] = body
        }
    }
}
