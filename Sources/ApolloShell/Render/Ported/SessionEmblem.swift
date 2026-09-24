import ApolloShellCore
import SwiftUI

struct SessionEmblem: View {
    let timeline: EmblemTimeline
    var size: CGFloat = 80
    var animating = true
    var fixedTime: TimeInterval?
    var accent: Color = .accentColor
    var track: Color?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let fixedTime {
                EmblemCanvas(pose: timeline.pose(at: fixedTime), accent: accent, track: track)
            } else if reduceMotion {
                EmblemCanvas(pose: timeline.still, accent: accent, track: track)
            } else {
                TimelineView(.animation(paused: !animating)) { context in
                    EmblemCanvas(pose: timeline.pose(at: context.date.timeIntervalSinceReferenceDate), accent: accent, track: track)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

private struct EmblemCanvas: View {
    let pose: EmblemPose
    let accent: Color
    let track: Color?
    @Environment(\.colorScheme) private var scheme

    private static let fill = 0.92
    private static let phaseOffset = ApolloMarkGeometry.phase(forAngle: ApolloMarkGeometry.restAngle)
        - EmblemTimeline.restAngle
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (12, 14, 3.4), (66, 11, 2.4), (68, 66, 2.9),
    ]

    var body: some View {
        let onAccent = Color.onAccent
        let neutral = track ?? Color.primary.opacity(scheme == .dark ? 0.9 : 0.62)
        Canvas { context, canvas in
            draw(in: &context, size: canvas, onAccent: onAccent, neutral: neutral)
        }
    }

    private struct Dot {
        let theta: Double
        let radius: Double
        let opacity: Double
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, onAccent: Color, neutral: Color) {
        let k = size.width / 80
        let box = ApolloMarkGeometry.viewBox
        let scale = size.width * Self.fill / box.width
        var mark = context
        mark.translateBy(x: size.width / 2, y: size.height / 2)
        mark.rotate(by: .degrees(pose.orbitTilt))
        mark.scaleBy(x: scale * pose.planetScale, y: scale * pose.planetScale)
        mark.translateBy(x: -box.midX, y: -box.midY)

        func circle(_ c: CGPoint, _ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        func orbitAngle(_ theta: Double) -> Double {
            ApolloMarkGeometry.angle(forPhase: theta + Self.phaseOffset)
        }
        func point(_ theta: Double) -> CGPoint {
            ApolloMarkGeometry.orbitPoint(orbitAngle(theta))
        }
        func moonRadius(_ dot: Dot) -> Double {
            dot.radius * (1 + 0.12 * sin(orbitAngle(dot.theta)))
        }
        func inFront(_ theta: Double) -> Bool { sin(orbitAngle(theta)) >= 0 }

        let letter = ApolloMarkGeometry.letter
        var lit = letter
        if pose.night > 0.001 {
            let r = 330.0
            let offset = r * (2.2 - 1.6 * pose.night)
            let c = ApolloMarkGeometry.center
            lit = letter.subtracting(circle(CGPoint(x: c.x - offset * 0.72, y: c.y - offset * 0.7), r))
        }

        let moonDot = Dot(theta: pose.moonAngle, radius: ApolloMarkGeometry.radius, opacity: 1)
        var trail: [Dot] = []
        let strength = min(max(
            (abs(pose.moonSpeed) - 2 * EmblemPose.idleSpeed) / (6 * EmblemPose.idleSpeed), 0
        ), 1)
        if strength > 0.01 {
            let spacing = min(abs(pose.moonSpeed) * 0.028, 0.24) * (pose.moonSpeed < 0 ? -1 : 1)
            for i in 1...5 {
                let fade = 1 - Double(i) / 6
                trail.append(Dot(
                    theta: pose.moonAngle - spacing * Double(i),
                    radius: ApolloMarkGeometry.radius * (0.55 + 0.4 * fade),
                    opacity: 0.5 * fade * strength
                ))
            }
        }
        func fill(_ dots: [Dot]) {
            for dot in dots {
                mark.fill(circle(point(dot.theta), moonRadius(dot)),
                          with: .color(neutral.opacity(pose.moonOpacity * dot.opacity)))
            }
        }
        let ring = neutral.opacity(pose.orbitOpacity)

        let gap = circle(point(moonDot.theta), moonRadius(moonDot) + ApolloMarkGeometry.moonGap)
        let moonBehind = !inFront(moonDot.theta)
        func cut(_ arc: Path) -> Path { pose.moonOpacity > 0.01 ? arc.subtracting(gap) : arc }

        fill(trail.reversed().filter { !inFront($0.theta) })
        mark.fill(cut(ApolloMarkGeometry.ringBack), with: .color(ring))
        if moonBehind { fill([moonDot]) }

        if pose.glow > 0.01 {
            mark.drawLayer { layer in
                layer.addFilter(.shadow(color: accent.opacity(pose.glow), radius: 9 * k / scale))
                layer.fill(lit, with: .color(accent))
            }
        }
        if pose.night > 0.001 {
            mark.fill(letter, with: .color(Color.primary.opacity(0.14)))
        }
        let bounds = letter.boundingRect
        mark.fill(lit, with: .linearGradient(
            Gradient(colors: [
                accent.mix(with: .white, by: 0.28),
                accent,
                accent.mix(with: .black, by: 0.18),
            ]),
            startPoint: CGPoint(x: bounds.minX + bounds.width * 0.2, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX - bounds.width * 0.2, y: bounds.maxY)
        ))

        for (i, opacity) in pose.dots.enumerated() where opacity > 0.01 {
            let c = ApolloMarkGeometry.counter
            mark.fill(circle(CGPoint(x: c.x + Double(i - 1) * 44, y: c.y), 17), with: .color(neutral.opacity(opacity)))
        }

        if inFront(moonDot.theta), pose.moonOpacity > 0.01 {
            var punch = mark
            punch.clip(to: letter)
            punch.blendMode = .destinationOut
            punch.fill(gap, with: .color(.black.opacity(pose.moonOpacity)))
        }
        fill(trail.reversed().filter { inFront($0.theta) })
        mark.fill(cut(ApolloMarkGeometry.ringFront), with: .color(ring))
        if !moonBehind { fill([moonDot]) }

        for (star, brightness) in zip(Self.stars, pose.stars) where brightness > 0.01 {
            let c = CGPoint(x: star.x * k, y: star.y * k)
            context.fill(sparkle(at: c, radius: star.r * k), with: .color(Color.primary.opacity(0.75 * brightness)))
        }
    }

    private func sparkle(at c: CGPoint, radius r: Double) -> Path {
        Path { path in
            let waist = r * 0.16
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
            path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
            path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
            path.closeSubpath()
        }
    }
}
