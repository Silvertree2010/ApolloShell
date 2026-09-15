import ApolloShellCore
import SwiftUI

/// Das Emblem in der Mitte des Sitzungsmenues: ein Planet in der
/// Akzentfarbe, um den ein Mond auf einer geneigten Bahn kreist ("Apollo").
/// Die Bewegung kommt als reine Zahlen aus `EmblemPose` (ApolloShellCore);
/// hier wird nur gezeichnet.
///
/// Die Uhr tickt nur, solange `animating` gilt (Menue sichtbar). Mit
/// "Bewegung reduzieren" steht das Emblem in einer festen Pose je Reaktion.
struct SessionEmblem: View {
    let timeline: EmblemTimeline
    var size: CGFloat = SessionMenu.buttonSize
    var animating = true
    /// Fester Zeitpunkt fuer Bildproben; `nil` = echte Uhr.
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

/// Zeichnet eine Pose. Masse im 80er-Raster des Knopfs, skaliert auf die
/// tatsaechliche Groesse.
private struct EmblemCanvas: View {
    let pose: EmblemPose
    @Environment(\.colorScheme) private var scheme

    // Geometrie im 80er-Raster.
    private static let planetRadius = 16.5
    private static let orbitRadii = CGSize(width: 33, height: 10.5)
    private static let orbitBaseTilt = -16.0
    private static let moonRadius = 3.6
    /// Luft zwischen Mond und Planet, wenn der Mond vor ihm steht.
    private static let moonGap = 1.3
    private static let lineWidth = 1.25
    /// Sterne: Mitte und Radius, frei von Planet und Bahn.
    private static let stars: [(x: Double, y: Double, r: Double)] = [
        (15, 17, 3.4), (62, 13, 2.4), (66, 64, 2.9),
    ]

    var body: some View {
        // Einmal pro Zeichnung gelesen, siehe `Color.onAccent`.
        let onAccent = Color.onAccent
        // Der Mond ist neutral; hell etwas zurueckgenommen, sonst wirkt er
        // neben dem Planeten schwer.
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

        /// Punkt auf der geneigten Bahn.
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
        /// Vorne etwas groesser, hinten kleiner: ein Hauch Tiefe.
        func moonRadius(_ dot: Dot) -> Double {
            dot.radius * k * (1 + 0.12 * sin(dot.theta))
        }

        let radius = Self.planetRadius * k * pose.planetScale
        let planet = circle(center, radius)
        // Beleuchteter Teil: ein Schattenkreis wandert von oben links herein,
        // bis nur eine Sichel unten rechts bleibt.
        var lit = planet
        if pose.night > 0.001 {
            let offset = radius * (2.2 - 1.6 * pose.night)
            let shadow = circle(CGPoint(x: center.x - offset * 0.72, y: center.y - offset * 0.7), radius)
            lit = planet.subtracting(shadow)
        }
        let neutral = Color.primary
        let line = StrokeStyle(lineWidth: Self.lineWidth * k, lineCap: .round)

        // Mond samt Spur; die Spur erscheint erst ab doppelter
        // Ruhegeschwindigkeit und ist ab der achtfachen voll da.
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

        // 1. Hintere Bahnhaelfte und was dort vom Mond zu sehen ist.
        context.stroke(arc(from: .pi, to: 2 * .pi), with: .color(neutral.opacity(0.2 * pose.orbitOpacity)), style: line)
        fill((trail.reversed() + [moonDot]).filter { sin($0.theta) < 0 })

        // 2. Schein, dann der Planet. Die Nachtseite ist neutral, nur der
        //    beleuchtete Teil traegt den Akzent.
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
        // Denk-Punkte mitten auf dem Planeten, in der Farbe fuer Akzentflaechen.
        for (i, opacity) in pose.dots.enumerated() where opacity > 0.01 {
            let x = center.x + Double(i - 1) * 6.2 * k
            context.fill(circle(CGPoint(x: x, y: center.y - 1.5 * k), 2.1 * k), with: .color(onAccent.opacity(opacity)))
        }

        // 3. Vordere Bahnhaelfte: auf dem Planeten in der Farbe fuer
        //    Akzentflaechen, daneben neutral.
        let front = arc(from: 0, to: .pi)
        context.drawLayer { layer in
            layer.clip(to: planet, options: .inverse)
            layer.stroke(front, with: .color(neutral.opacity(0.32 * pose.orbitOpacity)), style: line)
        }
        context.drawLayer { layer in
            layer.clip(to: planet)
            layer.stroke(front, with: .color(onAccent.opacity(0.5 * pose.orbitOpacity)), style: line)
        }

        // 4. Vorderer Mond. Steht er vor dem Planeten, stanzt er eine schmale
        //    Luecke hinein (wie Badges bei SF Symbols) und bleibt einfarbig.
        if sin(moonDot.theta) >= 0, pose.moonOpacity > 0.01 {
            var cut = context
            cut.clip(to: planet)
            // destinationOut statt clear: beachtet die Deckkraft, damit die
            // Luecke mit dem Mond ein- und ausblendet.
            cut.blendMode = .destinationOut
            cut.fill(
                circle(orbitPoint(moonDot.theta), moonRadius(moonDot) + Self.moonGap * k),
                with: .color(.black.opacity(pose.moonOpacity))
            )
        }
        fill((trail.reversed() + [moonDot]).filter { sin($0.theta) >= 0 })

        // 5. Sterne (nur im Ruhezustand).
        for (star, brightness) in zip(Self.stars, pose.stars) where brightness > 0.01 {
            let point = CGPoint(x: star.x * k, y: star.y * k)
            context.fill(sparkle(at: point, radius: star.r * k), with: .color(neutral.opacity(0.75 * brightness)))
        }
    }

    /// Vierzackiger Stern mit eingezogenen Flanken.
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
