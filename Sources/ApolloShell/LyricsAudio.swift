import ApolloShellCore
import AVFoundation
import CoreMedia
import FoundationModels
import os
import ScreenCaptureKit

final class AudioTap: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    typealias Sink = @Sendable (_ rms: Double, _ dt: Double, _ now: TimeInterval, _ env: (energy: Double, at: Date)) -> Void

    private let q = DispatchQueue(label: "apolloshell.lyrics.audio", qos: .userInteractive)
    private var stream: SCStream?
    private var sink: Sink?
    private var hp = Biquad.highpass(fc: 1200, fs: 48000)
    private var lp = Biquad.lowpass(fc: 5000, fs: 48000)
    private let log = Logger(category: "lyrics")
    private let state = OSAllocatedUnfairLock(initialState: false)

    func start(_ s: @escaping Sink) {
        sink = s
        state.withLock { $0 = true }
        Task { [weak self] in await self?.open() }
    }

    func stop() {
        state.withLock { $0 = false }
        let st = stream
        stream = nil
        Task { try? await st?.stopCapture() }
    }

    private func open() async {
        guard CGPreflightScreenCaptureAccess() else {
            log.notice("Live pulse needs screen recording access")
            return
        }
        do {
            let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let d = c.displays.first, state.withLock({ $0 }) else { return }
            let f = SCContentFilter(display: d, excludingApplications: [], exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 48000
            cfg.channelCount = 1
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            cfg.queueDepth = 3
            let s = SCStream(filter: f, configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: q)
            try await s.startCapture()
            guard state.withLock({ $0 }) else {
                try? await s.stopCapture()
                return
            }
            stream = s
        } catch {
            log.error("Audio tap failed: \(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        log.notice("Audio tap stopped: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let sink, sb.isValid else { return }
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let pts = sb.presentationTimeStamp
        let age = pts.isValid ? max(0, CMTimeGetSeconds(CMTimeSubtract(host, pts))) : 0
        let start = Date().addingTimeInterval(-age)
        guard let fmt = sb.formatDescription?.audioStreamBasicDescription, fmt.mFormatID == kAudioFormatLinearPCM else { return }
        let fs = fmt.mSampleRate > 0 ? fmt.mSampleRate : 48000
        try? sb.withAudioBufferList { abl, _ in
            guard let b = abl.first, let p = b.mData else { return }
            let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let xs = UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n)
            let hop = Int(fs * LyricsAutoSync.hop)
            var i = 0
            while i < n {
                let j = min(n, i + hop)
                guard j - i >= hop / 4 else { break }
                let seg = UnsafeBufferPointer(rebasing: xs[i..<j])
                let r = AudioPulse.rms(seg)
                var e = 0.0
                for x in seg {
                    let y = lp.run(hp.run(Double(x)))
                    e += y * y
                }
                let at = start.addingTimeInterval(Double(i) / fs)
                sink(r, Double(j - i) / fs, at.timeIntervalSinceReferenceDate, (e / Double(j - i), at))
                i = j
            }
        }
    }
}

struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func highpass(fc: Double, fs: Double) -> Biquad { make(fc: fc, fs: fs, hp: true) }
    static func lowpass(fc: Double, fs: Double) -> Biquad { make(fc: fc, fs: fs, hp: false) }

    static func make(fc: Double, fs: Double, hp: Bool) -> Biquad {
        let w = 2 * Double.pi * fc / fs, c = cos(w), al = sin(w) / (2 * 0.7071)
        let a0 = 1 + al
        let b0 = hp ? (1 + c) / 2 : (1 - c) / 2
        let b1 = hp ? -(1 + c) : 1 - c
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b0 / a0, a1: -2 * c / a0, a2: (1 - al) / a0)
    }

    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

final class AutoSync: @unchecked Sendable {
    private struct S {
        var core: LyricsAutoSync
        var np: MediaNowPlaying?
        var user: Double = 0
    }

    private let lock: OSAllocatedUnfairLock<S>

    init(timeline: LyricsTimeline) {
        lock = OSAllocatedUnfairLock(initialState: S(core: LyricsAutoSync(timeline: timeline)))
    }

    func clock(_ np: MediaNowPlaying?, user: Double) {
        lock.withLock {
            $0.np = np
            $0.user = user
        }
    }

    func feed(env: (energy: Double, at: Date), at now: TimeInterval) {
        lock.withLock { s in
            guard let np = s.np, np.isPlaying, let e = np.elapsed(at: env.at) else { return }
            s.core.feed(energy: env.energy, pos: e + s.user, now: now)
        }
    }

    var offset: Double { lock.withLock { $0.core.locked ? $0.core.offset : 0 } }
    var locked: Bool { lock.withLock { $0.core.locked } }
    var confidence: Double { lock.withLock { $0.core.lastConf } }
}

actor LyricsMoodReader {
    static let shared = LyricsMoodReader()
    private var cache: [String: LyricsMood] = [:]
    private let log = Logger(category: "lyrics")

    private var url: URL {
        let c = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return c.appendingPathComponent("ApolloShell/lyrics/moods.json")
    }

    private var loaded = false

    func mood(key: String, title: String, artist: String?, album: String?, lines: [LyricLine]) async -> LyricsMood? {
        if !loaded {
            loaded = true
            if let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode([String: LyricsMood].self, from: d) { cache = m }
        }
        if let m = cache[key] { return m }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let text = lines.filter { !$0.isBreak }.prefix(40).map(\.s).joined(separator: "\n")
        let prompt = """
        Song: \(title)
        Artist: \(artist ?? "unknown")
        Album: \(album ?? "unknown")
        Lyrics excerpt:
        \(text)

        Classify this song. Answer with exactly one line in this format and nothing else:
        genre=<one of: \(LyricsGenre.allCases.map(\.rawValue).joined(separator: ", "))>; energy=<0.0-1.0>; valence=<0.0-1.0>; dark=<yes|no>
        """
        do {
            let s = LanguageModelSession(instructions: "You are a music expert. You classify songs by genre, energy (calm 0 to intense 1) and valence (sad 0 to happy 1). You know most artists.")
            let r = try await s.respond(to: prompt, options: GenerationOptions(temperature: 0))
            guard let m = LyricsMoodParse.parse(r.content) else { return nil }
            cache[key] = m
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: url, options: .atomic) }
            return m
        } catch {
            log.notice("Mood model: \(error.localizedDescription)")
            return nil
        }
    }
}
