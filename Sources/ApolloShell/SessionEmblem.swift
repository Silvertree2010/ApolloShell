import ApolloShellCore
import SwiftUI

/// The emblem in the middle of the session menu: a planet in the accent color
/// with a moon circling it on a tilted orbit ("Apollo"). The motion comes as
/// plain numbers out of `EmblemPose` (ApolloShellCore); only the drawing
/// happens here.
///
/// The clock only ticks while `animating` holds (the menu is visible). With
/// "reduce motion" the emblem stands in a fixed pose per reaction.
struct SessionEmblem: View {
    let timeline: EmblemTimeline
    var size: CGFloat = SessionMenu.buttonSize
    var animating = true
    /// A fixed point in time for image samples; `nil` = the real clock.
    var fixedTime: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let fixedTime {
                EmblemCanvas(pose: timeline.pose(at: fixedTime))
            } else if reduceMotion {
                EmblemCanvas(pose: timeline.still)
            } else {
                TimelineView(.animation(paused: !animating)) { context in
                    EmblemCanvas(pose: timeline.pose(at: context.date.timeIntervalSinceReferenceDate))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Draws one pose. The measurements in the 80 grid of the button, scaled to
/// the real size.
private struct EmblemCanvas: View {
    let pose: EmblemPose
    @Environment(\.colorScheme) private var scheme

    // The geometry in the 80 grid.
    private static let planetRadius = 16.5
    private static let orbitRadii = CGSize(width: 33, height: 10.5)
    private static let orbitBaseTilt = -16.0
    private static let moonRadius = 3.6
    /// The air between the moon and the planet when the moon stands in front of it.
    private static let moonGap = 1.3
    private static let lineWidth = 1.25
    /// The stars: the centre and the radius, clear of the planet and the orbit.
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (15, 17, 3.4), (62, 13, 2.4), (66, 64, 2.9),
    ]

    var body: some View {
        // Read once per drawing, see `Color.onAccent`.
        let onAccent = Color.onAccent
        // The moon is neutral; pulled back a little in the light, otherwise it
        // looks heavy next to the planet.
        let moon = Color.primary.opacity(scheme == .dark ? 0.9 : 0.62)
        Canvas { context, canvas in
            draw(in: &context, size: canvas, onAccent: onAccent, moon: moon)
        }
    }

    private struct Dot {
        let theta: Double
        let radius: Double
        let opacity: Double
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, onAccent: Color, moon: Color) {
        let k = size.width / 80
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let tilt = (Self.orbitBaseTilt + pose.orbitTilt) * .pi / 180
        let a = Self.orbitRadii.width * k
        let b = Self.orbitRadii.height * k

        /// A point on the tilted orbit.
        func orbitPoint(_ theta: Double) -> CGPoint {
            let x = a * cos(theta)
            let y = b * sin(theta)
            return CGPoint(
                x: center.x + x * cos(tilt) - y * sin(tilt),
                y: center.y + x * sin(tilt) + y * cos(tilt)
            )
        }
        func arc(from start: Double, to end: Double) -> Path {
            Path { path in
                let steps = 48
                for i in 0...steps {
                    let point = orbitPoint(start + (end - start) * Double(i) / Double(steps))
                    i == 0 ? path.move(to: point) : path.addLine(to: point)
                }
            }
        }
        func circle(_ c: CGPoint, _ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        /// A little bigger in front, smaller behind: a breath of depth.
        func moonRadius(_ dot: Dot) -> Double {
            dot.radius * k * (1 + 0.12 * sin(dot.theta))
        }

        let radius = Self.planetRadius * k * pose.planetScale
        let planet = circle(center, radius)
        // The lit part: a shadow circle moves in from the top left until only
        // a crescent is left at the bottom right.
        var lit = planet
        if pose.night > 0.001 {
            let offset = radius * (2.2 - 1.6 * pose.night)
            let shadow = circle(CGPoint(x: center.x - offset * 0.72, y: center.y - offset * 0.7), radius)
            lit = planet.subtracting(shadow)
        }
        let neutral = Color.primary
        let line = StrokeStyle(lineWidth: Self.lineWidth * k, lineCap: .round)

        // The moon with its trail; the trail only appears from twice the
        // resting speed on and is fully there from eight times on.
        let moonDot = Dot(theta: pose.moonAngle, radius: Self.moonRadius, opacity: 1)
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
                    radius: Self.moonRadius * (0.55 + 0.4 * fade),
                    opacity: 0.5 * fade * strength
                ))
            }
        }
        func fill(_ dots: [Dot]) {
            for dot in dots {
                context.fill(
                    circle(orbitPoint(dot.theta), moonRadius(dot)),
                    with: .color(moon.opacity(pose.moonOpacity * dot.opacity))
                )
            }
        }

        // 1. The back half of the orbit and what can be seen of the moon there.
        context.stroke(arc(from: .pi, to: 2 * .pi), with: .color(neutral.opacity(0.2 * pose.orbitOpacity)), style: line)
        fill((trail.reversed() + [moonDot]).filter { sin($0.theta) < 0 })

        // 2. The glow, then the planet. The night side is neutral, only the
        //    lit part carries the accent.
        if pose.glow > 0.01 {
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.accentColor.opacity(pose.glow), radius: 9 * k))
                layer.fill(lit, with: .color(.accentColor))
            }
        }
        if pose.night > 0.001 {
            context.fill(planet, with: .color(neutral.opacity(0.14)))
        }
        let box = planet.boundingRect
        context.fill(lit, with: .linearGradient(
            Gradient(colors: [
                Color.accentColor.mix(with: .white, by: 0.28),
                Color.accentColor,
                Color.accentColor.mix(with: .black, by: 0.18),
            ]),
            startPoint: CGPoint(x: box.minX + box.width * 0.2, y: box.minY),
            endPoint: CGPoint(x: box.maxX - box.width * 0.2, y: box.maxY)
        ))
        // The thinking dots in the middle of the planet, in the color for accent areas.
        for (i, opacity) in pose.dots.enumerated() where opacity > 0.01 {
            let x = center.x + Double(i - 1) * 6.2 * k
            context.fill(circle(CGPoint(x: x, y: center.y - 1.5 * k), 2.1 * k), with: .color(onAccent.opacity(opacity)))
        }

        // 3. The front half of the orbit: on the planet in the color for
        //    accent areas, next to it neutral.
        let front = arc(from: 0, to: .pi)
        context.drawLayer { layer in
            layer.clip(to: planet, options: .inverse)
            layer.stroke(front, with: .color(neutral.opacity(0.32 * pose.orbitOpacity)), style: line)
        }
        context.drawLayer { layer in
            layer.clip(to: planet)
            layer.stroke(front, with: .color(onAccent.opacity(0.5 * pose.orbitOpacity)), style: line)
        }

        // 4. The front moon. When it stands in front of the planet, it punches
        //    a narrow gap into it (like badges with SF Symbols) and stays one color.
        if sin(moonDot.theta) >= 0, pose.moonOpacity > 0.01 {
            var cut = context
            cut.clip(to: planet)
            // destinationOut instead of clear: it respects the opacity, so
            // that the gap fades in and out with the moon.
            cut.blendMode = .destinationOut
            cut.fill(
                circle(orbitPoint(moonDot.theta), moonRadius(moonDot) + Self.moonGap * k),
                with: .color(.black.opacity(pose.moonOpacity))
            )
        }
        fill((trail.reversed() + [moonDot]).filter { sin($0.theta) >= 0 })

        // 5. The stars (only in sleep).
        for (star, brightness) in zip(Self.stars, pose.stars) where brightness > 0.01 {
            let point = CGPoint(x: star.x * k, y: star.y * k)
            context.fill(sparkle(at: point, radius: star.r * k), with: .color(neutral.opacity(0.75 * brightness)))
        }
    }

    /// A four-pointed star with drawn-in flanks.
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
