import ApolloShellCore
import SwiftUI

/// The emblem in the middle of the session menu: the ApolloShell mark, the A
/// in the accent colour with its moon circling on the logo's orbit. The
/// motion comes as
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

/// Draws one pose: the ApolloShell mark (0.2 logo, `ApolloMarkGeometry`)
/// with the old emblem's motion. The A takes the planet's part - the
/// accent colour, the glow, the night side while sleeping - and the moon
/// goes round the logo's orbit, behind the A on the far half.
private struct EmblemCanvas: View {
    let pose: EmblemPose
    @Environment(\.colorScheme) private var scheme

    /// How much of the button the mark fills.
    private static let fill = 0.92
    /// The moon in the logo sits here on its orbit; the emblem's clock
    /// starts at `EmblemTimeline.restAngle`, so this offset lines the two up.
    private static let angleOffset = ApolloMarkGeometry.restAngle - EmblemTimeline.restAngle
    /// The air between the moon and the A when the moon is in front of it,
    /// in the logo's units.
    private static let moonGap = 14.0
    /// The stars in the 80 grid of the button: clear of the mark.
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (12, 14, 3.4), (66, 11, 2.4), (68, 66, 2.9),
    ]

    var body: some View {
        // Read once per drawing, see `Color.onAccent`.
        let onAccent = Color.onAccent
        // The moon and the ring are neutral; pulled back a little in the
        // light, otherwise they look heavy next to the A.
        let neutral = Color.primary.opacity(scheme == .dark ? 0.9 : 0.62)
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
        // Into the logo's coordinates: centred, scaled by the pose (greet,
        // farewell), tilted by the pose (the thinking wobble).
        var mark = context
        mark.translateBy(x: size.width / 2, y: size.height / 2)
        mark.rotate(by: .degrees(pose.orbitTilt))
        mark.scaleBy(x: scale * pose.planetScale, y: scale * pose.planetScale)
        mark.translateBy(x: -box.midX, y: -box.midY)

        func circle(_ c: CGPoint, _ r: Double) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        func point(_ theta: Double) -> CGPoint {
            ApolloMarkGeometry.orbitPoint(theta + Self.angleOffset)
        }
        /// A little bigger in front, smaller behind: a breath of depth.
        func moonRadius(_ dot: Dot) -> Double {
            dot.radius * (1 + 0.12 * sin(dot.theta + Self.angleOffset))
        }
        func inFront(_ theta: Double) -> Bool { sin(theta + Self.angleOffset) >= 0 }

        let letter = ApolloMarkGeometry.letter
        // The lit part: a shadow circle moves in from the top left until only
        // a crescent is left at the bottom right.
        var lit = letter
        if pose.night > 0.001 {
            let r = 330.0
            let offset = r * (2.2 - 1.6 * pose.night)
            let c = ApolloMarkGeometry.center
            lit = letter.subtracting(circle(CGPoint(x: c.x - offset * 0.72, y: c.y - offset * 0.7), r))
        }

        // The moon with its trail; the trail only appears from twice the
        // resting speed on and is fully there from eight times on.
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

        // 1. The back arc of the ring and what can be seen of the moon there.
        mark.fill(ApolloMarkGeometry.ringBack, with: .color(ring))
        fill((trail.reversed() + [moonDot]).filter { !inFront($0.theta) })

        // 2. The glow, then the A. The night side is neutral, only the lit
        //    part carries the accent.
        if pose.glow > 0.01 {
            mark.drawLayer { layer in
                layer.addFilter(.shadow(color: Color.accentColor.opacity(pose.glow), radius: 9 * k / scale))
                layer.fill(lit, with: .color(.accentColor))
            }
        }
        if pose.night > 0.001 {
            mark.fill(letter, with: .color(Color.primary.opacity(0.14)))
        }
        let bounds = letter.boundingRect
        mark.fill(lit, with: .linearGradient(
            Gradient(colors: [
                Color.accentColor.mix(with: .white, by: 0.28),
                Color.accentColor,
                Color.accentColor.mix(with: .black, by: 0.18),
            ]),
            startPoint: CGPoint(x: bounds.minX + bounds.width * 0.2, y: bounds.minY),
            endPoint: CGPoint(x: bounds.maxX - bounds.width * 0.2, y: bounds.maxY)
        ))

        // 3. The front arc of the ring.
        mark.fill(ApolloMarkGeometry.ringFront, with: .color(ring))

        // 4. The thinking dots, in the triangle inside the A.
        for (i, opacity) in pose.dots.enumerated() where opacity > 0.01 {
            let c = ApolloMarkGeometry.counter
            mark.fill(circle(CGPoint(x: c.x + Double(i - 1) * 44, y: c.y), 17), with: .color(neutral.opacity(opacity)))
        }

        // 5. The front moon. In front of the A it punches a narrow gap into
        //    it (like badges with SF Symbols) and stays one colour.
        if inFront(moonDot.theta), pose.moonOpacity > 0.01 {
            var cut = mark
            cut.clip(to: letter)
            // destinationOut instead of clear: it respects the opacity, so
            // that the gap fades in and out with the moon.
            cut.blendMode = .destinationOut
            cut.fill(circle(point(moonDot.theta), moonRadius(moonDot) + Self.moonGap),
                     with: .color(.black.opacity(pose.moonOpacity)))
        }
        fill((trail.reversed() + [moonDot]).filter { inFront($0.theta) })

        // 6. The stars (only in sleep), in the button's own grid.
        for (star, brightness) in zip(Self.stars, pose.stars) where brightness > 0.01 {
            let c = CGPoint(x: star.x * k, y: star.y * k)
            context.fill(sparkle(at: c, radius: star.r * k), with: .color(Color.primary.opacity(0.75 * brightness)))
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
