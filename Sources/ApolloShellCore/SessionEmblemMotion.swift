import Foundation

/// Worauf das Emblem in der Mitte des Sitzungsmenues gerade reagiert.
///
/// Das Emblem ist ein kleiner Planet in der Akzentfarbe, um den ein Mond auf
/// einer geneigten Bahn kreist. Jede Reaktion ist nur eine andere Bewegung
/// derselben Figur.
public enum EmblemReaction: String, CaseIterable, Sendable {
    /// Menue geht auf: der Planet waechst an, der Mond schwingt schnell ein
    /// und pendelt sich auf die Ruhegeschwindigkeit ein.
    case greet
    /// Ruhe: langsamer Umlauf, der Schein des Planeten atmet.
    case idle
    /// Ruhezustand: die Nachtseite zieht auf, Sterne erscheinen, der Mond
    /// wird langsamer und bleibt stehen.
    case sleep
    /// Ausschalten und Neustart: eine schnelle Runde, der Planet federt.
    case farewell
    /// Abmelden: die Bahn kippelt, drei Punkte auf dem Planeten denken nach.
    case think

    /// Reaktion auf den Knopf unter der Maus oder die Tastatur-Auswahl.
    public static func reacting(to action: SessionAction?) -> EmblemReaction {
        switch action {
        case nil: .idle
        case .sleep: .sleep
        case .shutDown, .restart: .farewell
        case .logOut: .think
        }
    }

    /// Was nach einer Einmal-Bewegung bleibt, solange `action` aktiv ist.
    public static func resting(for action: SessionAction?) -> EmblemReaction {
        let reaction = reacting(to: action)
        return reaction.isOneShot ? .idle : reaction
    }

    /// Dauer der Einmal-Bewegungen in Sekunden; `nil` fuer Schleifen.
    public var duration: Double? {
        switch self {
        case .greet: EmblemPose.greetDuration
        case .farewell: EmblemPose.farewellDuration
        case .idle, .sleep, .think: nil
        }
    }

    public var isOneShot: Bool { duration != nil }
}

/// Eine Momentaufnahme des Emblems. Reine Zahlen, gezeichnet wird in der App.
public struct EmblemPose: Equatable, Sendable {
    /// Position des Mondes auf der Bahn im Bogenmass. `sin > 0`: vor dem
    /// Planeten, sonst dahinter.
    public var moonAngle: Double
    /// Winkelgeschwindigkeit in rad/s; ab etwa dem Doppelten der Ruhe zieht
    /// der Mond eine Spur.
    public var moonSpeed: Double = EmblemPose.idleSpeed
    public var moonOpacity: Double = 1
    public var orbitOpacity: Double = 1
    /// Zusaetzliche Neigung der Bahn in Grad (Kippeln beim Nachdenken).
    public var orbitTilt: Double = 0
    public var planetScale: Double = 1
    /// Staerke des Scheins um den Planeten, 0...1.
    public var glow: Double = EmblemPose.restGlow
    /// 0 = voll beleuchtet, 1 = nur noch eine Sichel.
    public var night: Double = 0
    /// Helligkeit der drei Sterne, 0...1.
    public var stars: [Double] = [0, 0, 0]
    /// Deckkraft der drei Denk-Punkte, 0...1.
    public var dots: [Double] = [0, 0, 0]
    /// Einmal-Bewegung am Ende angekommen.
    public var finished = false

    public init(moonAngle: Double) {
        self.moonAngle = moonAngle
    }

    // MARK: - Konstanten

    /// Ein Umlauf in neun Sekunden: sichtbar, aber ruhig.
    public static let idleSpeed = 2 * Double.pi / 9
    public static let restGlow = 0.45
    /// Im Schlaf nur ein Hauch; mehr gibt auf hellem Grund einen blassen Hof.
    static let sleepGlow = 0.04
    public static let greetDuration = 1.4
    public static let farewellDuration = 1.1
    /// So lange braucht der Mond im Ruhezustand bis zum Stillstand.
    public static let sleepSettle = 2.6
    /// Bis hierhin bremst der Mond beim Nachdenken ab.
    static let thinkSettle = 0.8
    static let thinkSpeedFactor = 0.3
    static let wobbleDegrees = 7.0
    static let wobblePeriod = 2.8
    static let dotPeriod = 1.2

    // MARK: - Bewegung

    /// Pose `time` Sekunden nach Beginn der Reaktion, mit dem Mond anfangs
    /// bei `startAngle`. Alle Reaktionen ausser dem Oeffnen beginnen in der
    /// Ruhepose, damit ein Wechsel nur die Bewegung aendert, nicht die Figur.
    public static func at(_ reaction: EmblemReaction, time: Double, startAngle: Double) -> EmblemPose {
        let t = max(0, time)
        var pose = EmblemPose(moonAngle: angle(reaction, t, startAngle))
        // Mittlere Ableitung; vor t = 0 steht die Pose, deshalb einseitig.
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
            // Erst eindruecken, dann leicht ueberschiessen und zurueck.
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
                // Die Punkte leuchten nacheinander auf, wie beim Tippen.
                var phase = (t / dotPeriod - Double(i) * 0.16).truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }
                return ramp * (0.35 + 0.65 * max(0, sin(2 * .pi * phase)))
            }
        }
        return pose
    }

    /// Stehende Pose fuer "Bewegung reduzieren": gleiche Aussage, keine
    /// Bewegung, der Mond immer an derselben Stelle.
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

    /// Mondposition; stetig und ohne Knick an jedem Reaktionswechsel, weil
    /// jede Reaktion mit Ruhegeschwindigkeit beginnt (und die Einmal-
    /// Bewegungen mit ihr enden).
    static func angle(_ reaction: EmblemReaction, _ t: Double, _ start: Double) -> Double {
        let w = idleSpeed
        switch reaction {
        case .idle:
            return start + w * t
        case .greet:
            // Eineinviertel Extrarunden, die sanft auslaufen.
            return start + w * t + 2 * .pi * 1.25 * easeOutCubic(clamp01(t / greetDuration))
        case .farewell:
            return start + w * t + 2 * .pi * easeInOutCubic(clamp01(t / farewellDuration))
        case .sleep:
            // Gleichmaessig bis zum Stillstand abbremsen.
            let p = clamp01(t / sleepSettle)
            return start + w * sleepSettle / 2 * (1 - (1 - p) * (1 - p))
        case .think:
            let p = clamp01(t / thinkSettle)
            let brake = w * (1 - thinkSpeedFactor) * thinkSettle / 2 * (1 - (1 - p) * (1 - p))
            return start + w * thinkSpeedFactor * t + brake
        }
    }

    // MARK: - Kurven

    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeInOutCubic(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
    static func easeInOutSine(_ x: Double) -> Double { (1 - cos(.pi * x)) / 2 }

    /// Die Kurve, mit der das Menue hereinfaehrt: cubic-bezier(0.38, 1.21,
    /// 0.22, 1), leicht ueberschiessend.
    static func menuCurve(_ x: Double) -> Double {
        cubicBezier(x, 0.38, 1.21, 0.22, 1)
    }

    /// y(x) einer CSS-Bezierkurve; x per Newton aus dem Kurvenparameter.
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

/// Die laufende Reaktion samt Startzeit. Beim Wechsel uebernimmt die neue
/// Reaktion die aktuelle Mondposition, damit der Mond nicht springt.
public struct EmblemTimeline: Equatable, Sendable {
    /// Hier steht der Mond ohne Bewegung: rechts neben dem Planeten, knapp
    /// vor ihm auf der Bahn.
    public static let restAngle = 0.12 * Double.pi

    public private(set) var reaction: EmblemReaction
    public private(set) var startAngle: Double
    /// Sekunden, Zeitbasis frei (die App nimmt timeIntervalSinceReferenceDate).
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

    /// Wechselt zu `next`; dieselbe Reaktion laeuft ungestoert weiter.
    public mutating func show(_ next: EmblemReaction, at time: Double) {
        guard next != reaction else { return }
        let angle = pose(at: time).moonAngle.truncatingRemainder(dividingBy: 2 * .pi)
        reaction = next
        startAngle = angle
        startTime = time
    }
}
