import Foundation

public enum LyricsGenre: String, Sendable, Codable, CaseIterable {
    case rap, rock, metal, pop, electronic, rnb, ballad, acoustic, classical, jazz, other
}

public struct LyricsMood: Sendable, Equatable, Codable {
    public var genre: LyricsGenre
    public var energy: Double
    public var valence: Double
    public var dark: Bool

    public init(genre: LyricsGenre, energy: Double, valence: Double, dark: Bool = false) {
        self.genre = genre
        self.energy = min(max(energy, 0), 1)
        self.valence = min(max(valence, 0), 1)
        self.dark = dark
    }

    public static let neutral = LyricsMood(genre: .other, energy: 0.5, valence: 0.5)

    public static func guess(title: String, artist: String?, lines: [LyricLine]) -> LyricsMood {
        let txt = (lines.map(\.s).joined(separator: " ") + " " + title).lowercased()
        let words = txt.split { !$0.isLetter && $0 != "'" }.map(String.init)
        guard !words.isEmpty else { return .neutral }
        let set = Set(words)
        func hits(_ l: [String]) -> Double { Double(l.filter(set.contains).count) }
        let darkW = ["die", "dead", "death", "blood", "kill", "pain", "dark", "hell", "cry", "alone", "tears", "lost", "grave", "hate", "broken"]
        let happyW = ["love", "happy", "sun", "smile", "dance", "party", "tonight", "baby", "shine", "fun", "summer", "good"]
        let rapW = ["money", "bitch", "flow", "rap", "shit", "fuck", "homie", "gang", "drip", "ice", "bars", "hood"]
        let calmW = ["slow", "quiet", "soft", "dream", "sleep", "rain", "ocean", "moon", "stars", "gentle"]
        let d = hits(darkW), h = hits(happyW), r = hits(rapW), c = hits(calmW)
        let dens = Double(words.count) / Double(max(lines.filter { !$0.isBreak }.count, 1))
        var g = LyricsGenre.other
        if r >= 3 || dens > 11 { g = .rap } else if c >= 3 { g = .ballad } else if h >= 4 { g = .pop }
        let e = min(1, max(0, 0.35 + (dens - 6) * 0.05 + r * 0.04 - c * 0.05))
        let v = min(1, max(0, 0.5 + (h - d) * 0.06))
        return LyricsMood(genre: g, energy: e, valence: v, dark: d > h + 2)
    }
}

public enum LyricsMotion: String, Sendable, Codable {
    case fade, rise, pop, slam, drift
}

public enum LyricsFace: String, Sendable, Codable {
    case standard, rounded, serif, mono, condensed
}

public struct LyricsStyle: Sendable, Equatable {
    public var face: LyricsFace
    public var weight: Double
    public var size: Double
    public var tracking: Double
    public var upper: Bool
    public var motion: LyricsMotion
    public var trans: Double
    public var pulse: Double
    public var blur: Double
    public var fill: Bool
    public var shake: Double

    public init(face: LyricsFace, weight: Double, size: Double, tracking: Double, upper: Bool,
                motion: LyricsMotion, trans: Double, pulse: Double, blur: Double, fill: Bool, shake: Double) {
        self.face = face
        self.weight = weight
        self.size = size
        self.tracking = tracking
        self.upper = upper
        self.motion = motion
        self.trans = trans
        self.pulse = pulse
        self.blur = blur
        self.fill = fill
        self.shake = shake
    }

    public static let plain = LyricsStyle(face: .standard, weight: 0.6, size: 1, tracking: 0, upper: false,
                                          motion: .rise, trans: 0.35, pulse: 0, blur: 1.5, fill: true, shake: 0)

    public static func from(_ m: LyricsMood) -> LyricsStyle {
        let e = m.energy
        var s = LyricsStyle.plain
        s.weight = 0.35 + e * 0.6
        s.size = 0.92 + e * 0.22
        s.trans = 0.55 - e * 0.37
        s.pulse = 0.25 + e * 0.75
        s.blur = 2.5 - e * 1.5
        s.motion = e > 0.75 ? .pop : e < 0.3 ? .drift : .rise
        switch m.genre {
        case .rap:
            s.face = .condensed
            s.upper = true
            s.tracking = 0.02
            s.motion = .slam
            s.trans = min(s.trans, 0.16)
        case .metal:
            s.face = .condensed
            s.upper = true
            s.weight = max(s.weight, 0.9)
            s.motion = .slam
            s.shake = 0.6 + e * 0.4
        case .rock:
            s.face = .condensed
            s.weight = max(s.weight, 0.7)
            s.shake = e * 0.35
        case .electronic:
            s.face = .mono
            s.tracking = 0.06
            s.motion = e > 0.5 ? .pop : .fade
        case .ballad, .classical:
            s.face = .serif
            s.weight = min(s.weight, 0.45)
            s.motion = .drift
            s.trans = max(s.trans, 0.6)
            s.pulse = min(s.pulse, 0.3)
        case .acoustic, .jazz:
            s.face = .serif
            s.motion = .fade
        case .rnb:
            s.face = .rounded
            s.motion = .drift
        case .pop:
            s.face = .rounded
        case .other:
            break
        }
        if m.dark { s.tracking += 0.01 }
        return s
    }
}

public struct AudioPulse: Sendable {
    public private(set) var level: Double = 0
    public private(set) var beat: Double = 0
    public private(set) var lastBeat: TimeInterval = -10
    var env: Double = 0
    var peak: Double = 1e-4
    var avg: Double = 0
    var prev: Double = 0

    public init() {}

    public static let refractory: TimeInterval = 0.22

    public mutating func feed(rms: Double, dt: Double, now: TimeInterval) {
        guard rms.isFinite, dt > 0 else { return }
        let r = max(rms, 0)
        let atk = 1 - exp(-dt / 0.012), rel = 1 - exp(-dt / 0.18)
        env += (r - env) * (r > env ? atk : rel)
        peak = max(env, peak * exp(-dt / 6), 1e-4)
        level = min(1, env / peak)
        avg += (env - avg) * (1 - exp(-dt / 0.45))
        let flux = max(0, env - prev)
        prev = env
        beat *= exp(-dt / 0.12)
        if env > avg * 1.35, flux > peak * 0.02, env > peak * 0.25, now - lastBeat > Self.refractory {
            beat = min(1, (env / max(avg, 1e-6) - 1) * 1.2)
            lastBeat = now
        }
    }

    public static func rms(_ xs: UnsafeBufferPointer<Float>) -> Double {
        guard !xs.isEmpty else { return 0 }
        var s: Double = 0
        for x in xs { s += Double(x) * Double(x) }
        return (s / Double(xs.count)).squareRoot()
    }
}

public enum LyricsMoodParse {
    public static func parse(_ s: String) -> LyricsMood? {
        var kv: [String: String] = [:]
        for part in s.lowercased().split(whereSeparator: { $0 == ";" || $0 == "\n" || $0 == "," }) {
            let p = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: ".")))) }
            if p.count == 2 { kv[p[0]] = p[1] }
        }
        guard let g = kv["genre"], let e = kv["energy"].flatMap(Double.init), let v = kv["valence"].flatMap(Double.init) else { return nil }
        let genre = LyricsGenre(rawValue: g) ?? LyricsGenre.allCases.first { g.contains($0.rawValue) } ?? .other
        return LyricsMood(genre: genre, energy: e, valence: v, dark: kv["dark"]?.hasPrefix("y") == true)
    }
}
