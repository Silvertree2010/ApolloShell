import Foundation

public struct LyricsAutoSync: Sendable {
    public static let hop: TimeInterval = 0.01
    public static let window: TimeInterval = 24
    public static let maxLag: TimeInterval = 0.35
    public static let minWords = 14
    public static let minPeak: Double = 1.2
    public static let minSep: Double = 0.15
    public static let agree: TimeInterval = 0.04

    let onsets: [TimeInterval]
    var buf: [(p: TimeInterval, v: Double)] = []
    var prevE: Double = 0
    var runs: [TimeInterval] = []
    public private(set) var offset: TimeInterval = 0
    public private(set) var locked = false
    public private(set) var lastConf: Double = 0
    public private(set) var lastPeak: Double = 0
    public private(set) var lastSep: Double = 0
    var lastEval: TimeInterval = -100

    public init(timeline: LyricsTimeline) {
        var o: [TimeInterval] = []
        for l in timeline.lyrics.lines where !l.isBreak {
            if l.w.isEmpty { o.append(l.t) } else { o.append(contentsOf: l.w.map(\.t)) }
        }
        onsets = o.sorted()
    }

    public mutating func feed(energy e: Double, pos p: TimeInterval, now: TimeInterval) {
        guard e.isFinite, p.isFinite else { return }
        let le = log(max(e, 1e-7))
        let flux = max(0, le - prevE)
        prevE = le
        if let last = buf.last, p < last.p - 1 || p > last.p + 2 {
            buf.removeAll()
            runs.removeAll()
        }
        buf.append((p, flux))
        if let f = buf.first, p - f.p > Self.window {
            let cut = buf.firstIndex { p - $0.p <= Self.window } ?? 0
            buf.removeFirst(cut)
        }
        if now - lastEval >= 2 {
            lastEval = now
            evaluate()
        }
    }

    public mutating func evaluate() {
        guard let a = buf.first?.p, let b = buf.last?.p, b - a > 8 else { return }
        let ws = onsets.filter { $0 > a + Self.maxLag && $0 < b - Self.maxLag }
        guard ws.count >= Self.minWords else { return }
        let n = Int(((b - a) / Self.hop).rounded()) + 1
        var grid = [Double](repeating: 0, count: n)
        for s in buf {
            let i = Int(((s.p - a) / Self.hop).rounded())
            if i >= 0 && i < n { grid[i] = max(grid[i], s.v) }
        }
        let mean = grid.reduce(0, +) / Double(n)
        let sd = (grid.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)).squareRoot()
        guard sd > 0 else { return }
        let steps = Int(Self.maxLag / Self.hop)
        var scores: [Double] = []
        for k in -steps...steps {
            let lag = Double(k) * Self.hop
            var s = 0.0
            for w in ws {
                let c = Int(((w + lag - a) / Self.hop).rounded())
                var m = 0.0
                for j in max(0, c - 2)...min(n - 1, c + 2) { m = max(m, grid[j]) }
                s += (m - mean) / sd
            }
            scores.append(s / Double(ws.count))
        }
        guard let bi = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return }
        let srt = scores.sorted()
        let med = srt[srt.count / 2]
        let spread = (scores.reduce(0) { $0 + ($1 - med) * ($1 - med) } / Double(scores.count)).squareRoot()
        let conf = spread > 0 ? (scores[bi] - med) / spread : 0
        lastConf = conf
        lastPeak = scores[bi] - med
        let far = scores.indices.filter { abs($0 - bi) > 6 }.map { scores[$0] }.max() ?? med
        lastSep = scores[bi] - med > 0 ? (scores[bi] - far) / (scores[bi] - med) : 0
        let lag = Double(bi - steps) * Self.hop
        guard lastPeak >= Self.minPeak, lastSep >= Self.minSep, abs(lag) < Self.maxLag - Self.hop * 2 else { return }
        runs.append(-lag)
        if runs.count > 3 { runs.removeFirst() }
        guard runs.count == 3, let lo = runs.min(), let hi = runs.max(), hi - lo <= Self.agree else { return }
        let target = runs.sorted()[1]
        offset = locked ? offset + (target - offset) * 0.5 : target
        locked = true
    }
}
