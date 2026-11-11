import AppKit
import ApolloShellCore
import CoreAudio
import CryptoKit
import Observation
import os

@MainActor
@Observable
final class LyricsModel {
    enum Phase: Equatable {
        case off, idle, loading, ready, missing, failed
    }

    private(set) var phase: Phase = .off
    private(set) var lyrics: Lyrics?
    private(set) var timeline: LyricsTimeline?
    private(set) var mood: LyricsMood = .neutral
    private(set) var style: LyricsStyle = .plain
    private(set) var key: String?
    private(set) var offsets = LyricsOffsets()

    @ObservationIgnored let media: MediaModel
    @ObservationIgnored let settings: ShellSettingsStore
    @ObservationIgnored private(set) var latency: TimeInterval = 0
    @ObservationIgnored let pulse = PulseBox()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var obs: [Task<Void, Never>] = []
    @ObservationIgnored private var want = false
    @ObservationIgnored private var tap: AudioTap?
    @ObservationIgnored private var sync: AutoSync? {
        didSet { syncRef.value = sync; pushClock() }
    }
    @ObservationIgnored private let syncRef = SyncRef()
    @ObservationIgnored private let log = Logger(category: "lyrics")
    @ObservationIgnored private var demand = 0
    @ObservationIgnored private var fixed: Date?

    init(media: MediaModel, settings: ShellSettingsStore) {
        self.media = media
        self.settings = settings
        offsets = Self.loadOffsets()
        obs.append(Task { [weak self, settings] in
            for await s in Observations({ settings.settings.lyrics }) { self?.apply(s) }
        })
        obs.append(Task { [weak self, media] in
            for await np in Observations({ media.nowPlaying }) {
                self?.track(np)
                self?.pushClock()
            }
        })
        LyricsAudio.onLatency { [weak self] l in self?.latency = l }
        latency = LyricsAudio.outputLatency()
    }

    private init(preview l: Lyrics, media: MediaModel, settings: ShellSettingsStore, mood: LyricsMood) {
        self.media = media
        self.settings = settings
        lyrics = l
        timeline = LyricsTimeline(l, duration: media.nowPlaying?.duration)
        phase = .ready
        self.mood = mood
        style = .from(mood)
        fixed = media.fixedNow
    }

    static func preview(_ l: Lyrics, media: MediaModel, mood: LyricsMood = .neutral) -> LyricsModel {
        LyricsModel(preview: l, media: media, settings: ShellSettingsStore(url: nil), mood: mood)
    }

    var enabled: Bool { settings.settings.lyrics.enabled }

    func acquire() {
        demand += 1
        refreshStream()
    }

    func release() {
        demand = max(0, demand - 1)
        refreshStream()
    }

    private func apply(_ s: ShellSettings.Lyrics) {
        if !s.enabled {
            phase = .off
            task?.cancel()
            lyrics = nil
            timeline = nil
        } else if phase == .off {
            phase = .idle
            track(media.nowPlaying)
        }
        style = s.moodStyles ? .from(mood) : .plain
        refreshStream()
    }

    private func refreshStream() {
        let s = settings.settings.lyrics
        let on = s.enabled && (demand > 0 || s.desktop)
        if on != want {
            want = on
            if on { media.startLyrics() } else { media.stopLyrics() }
        }
        let tapOn = on && (s.livePulse || (s.autoSync && timeline?.lyrics.synced == true))
        if tapOn, tap == nil {
            let t = AudioTap()
            tap = t
            let pb = pulse, sb = syncRef
            t.start { rms, dt, now, env in
                pb.feed(rms: rms, dt: dt, now: now)
                sb.value?.feed(env: env, at: now)
            }
            watchBeats(true)
        } else if !tapOn, let t = tap {
            t.stop()
            tap = nil
            pulse.reset()
            watchBeats(false)
        }
    }

    private func track(_ np: MediaNowPlaying?) {
        guard enabled else { return }
        guard let np, let q = LyricsQuery(np) else {
            if np == nil { reset(.idle) }
            return
        }
        if q.key == key, phase != .failed { return }
        reset(.loading)
        key = q.key
        let k = q.key
        task = Task { [weak self] in
            let r = await LyricsStore.shared.lyrics(for: q)
            guard let self, !Task.isCancelled, self.key == k else { return }
            self.loaded(r, np: np)
        }
    }

    private func reset(_ p: Phase) {
        task?.cancel()
        lyrics = nil
        timeline = nil
        key = nil
        sync = nil
        phase = p
        mood = .neutral
        style = settings.settings.lyrics.moodStyles ? .from(.neutral) : .plain
    }

    private func loaded(_ r: LyricsStore.Result, np: MediaNowPlaying) {
        switch r {
        case .found(let l):
            lyrics = l
            timeline = LyricsTimeline(l, duration: np.duration)
            phase = l.lines.isEmpty && !l.instrumental ? .missing : .ready
            if l.synced { sync = AutoSync(timeline: timeline!) }
            let base = LyricsMood.guess(title: np.title, artist: np.artist, lines: l.lines)
            setMood(base)
            if let k = key {
                Task { [weak self] in
                    guard let m = await LyricsMoodReader.shared.mood(key: k, title: np.title, artist: np.artist,
                                                                   album: np.album, lines: l.lines, base: base) else { return }
                    guard let self, self.key == k else { return }
                    self.setMood(m)
                }
            }
        case .missing: phase = .missing
        case .failed: phase = .failed
        }
        refreshStream()
    }

    private func setMood(_ m: LyricsMood) {
        baseMood = m
        mood = m
        beats = BeatEnergy()
        style = settings.settings.lyrics.moodStyles ? .from(m) : .plain
    }

    @ObservationIgnored private var baseMood: LyricsMood = .neutral
    @ObservationIgnored private var beats = BeatEnergy()
    @ObservationIgnored private var beatTimer: Timer?

    private func watchBeats(_ on: Bool) {
        guard on != (beatTimer != nil) else { return }
        beatTimer?.invalidate()
        beatTimer = nil
        guard on else { return }
        beatTimer = .repeating(every: 0.1, owner: self) { m in m.sampleBeat() }
    }

    private func sampleBeat() {
        guard media.nowPlaying?.isPlaying == true else { return }
        beats.note(beatAt: pulse.lastBeat)
        guard let e = beats.energy else { return }
        let target = baseMood.energy * 0.4 + e * 0.6
        guard abs(target - mood.energy) > 0.08 else { return }
        mood = LyricsMood(genre: baseMood.genre, energy: target, valence: baseMood.valence, dark: baseMood.dark)
        style = settings.settings.lyrics.moodStyles ? .from(mood) : .plain
    }

    func position(at now: Date) -> TimeInterval? {
        guard let np = media.nowPlaying else { return nil }
        let off = key.map { offsets.total(key: $0, player: np.sourceBundleIdentifier) } ?? 0
        let auto = settings.settings.lyrics.autoSync ? (sync?.offset ?? 0) : 0
        return LyricsClock(np: np, outputLatency: latency, offset: off + auto).position(at: fixed ?? now)
    }

    var userOffset: Double { key.flatMap { offsets.songs[$0] } ?? 0 }

    func nudge(_ d: Double) {
        guard let k = key else { return }
        offsets.nudge(key: k, by: d)
        Self.saveOffsets(offsets)
        pushClock()
    }

    func seek(to t: TimeInterval) {
        media.seek(to: max(0, t + latency - (key.map { offsets.total(key: $0, player: media.nowPlaying?.sourceBundleIdentifier) } ?? 0) - (settings.settings.lyrics.autoSync ? (sync?.offset ?? 0) : 0)))
    }

    private func pushClock() {
        guard let s = sync else { return }
        let np = media.nowPlaying
        let off = key.map { offsets.total(key: $0, player: np?.sourceBundleIdentifier) } ?? 0
        s.clock(np, user: off)
    }

    var autoOffset: Double? { sync?.locked == true ? sync?.offset : nil }

    func retry() {
        key = nil
        track(media.nowPlaying)
    }

    private static var offsetsURL: URL { ShellFiles.live.directory.appendingPathComponent("lyrics-offsets.json") }

    private static func loadOffsets() -> LyricsOffsets {
        guard let d = try? Data(contentsOf: offsetsURL) else { return LyricsOffsets() }
        return (try? JSONDecoder().decode(LyricsOffsets.self, from: d)) ?? LyricsOffsets()
    }

    private static func saveOffsets(_ o: LyricsOffsets) {
        guard let d = try? JSONEncoder().encode(o) else { return }
        try? ShellFiles.write(d, to: offsetsURL)
    }
}

final class SyncRef: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<AutoSync?>(initialState: nil)
    var value: AutoSync? {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}

final class PulseBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AudioPulse())

    func feed(rms: Double, dt: Double, now: TimeInterval) {
        lock.withLock { $0.feed(rms: rms, dt: dt, now: now) }
    }

    func reset() { lock.withLock { $0 = AudioPulse() } }

    var lastBeat: TimeInterval { lock.withLock { $0.lastBeat } }

    var value: (level: Double, beat: Double) {
        lock.withLock { ($0.level, $0.beat) }
    }
}

actor LyricsStore {
    static let shared = LyricsStore()

    enum Result: Sendable {
        case found(Lyrics)
        case missing
        case failed
    }

    private struct Entry: Codable {
        var lyrics: Lyrics?
        var at: Date
    }

    private let log = Logger(category: "lyrics")
    static let retryMissing: TimeInterval = 3 * 24 * 3600
    private var inflight: [String: Task<Result, Never>] = [:]

    private var dir: URL {
        let c = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return c.appendingPathComponent("ApolloShell/lyrics", isDirectory: true)
    }

    private func file(_ k: String) -> URL {
        let h = SHA256.hash(data: Data(k.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h + ".json")
    }

    func lyrics(for q: LyricsQuery) async -> Result {
        if let d = try? Data(contentsOf: file(q.key)), let e = try? JSONDecoder().decode(Entry.self, from: d) {
            if let l = e.lyrics { return .found(l) }
            if Date().timeIntervalSince(e.at) < Self.retryMissing { return .missing }
        }
        if let t = inflight[q.key] { return await t.value }
        let t = Task { await fetch(q) }
        inflight[q.key] = t
        let r = await t.value
        inflight[q.key] = nil
        switch r {
        case .found(let l): store(q.key, l)
        case .missing: store(q.key, nil)
        case .failed: break
        }
        return r
    }

    private func store(_ k: String, _ l: Lyrics?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let d = try? JSONEncoder().encode(Entry(lyrics: l, at: Date())) else { return }
        try? d.write(to: file(k), options: .atomic)
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = ["User-Agent": "ApolloShell/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") (https://github.com/Silvertree2010/ApolloShell)"]
        return URLSession(configuration: c)
    }()

    private func get(_ u: URL) async -> (Data, Int)? {
        guard let (d, r) = try? await Self.session.data(from: u) else { return nil }
        return (d, (r as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func fetch(_ q: LyricsQuery) async -> Result {
        var failed = false
        if let u = LRCLIB.getURL(q) {
            if let (d, c) = await get(u) {
                if c == 200, let r = LRCLIB.decodeOne(d), let l = r.lyrics,
                   q.duration.map({ d in r.duration.map { abs($0 - d) <= LRCLIB.maxDurationDiff } ?? true }) ?? true {
                    if l.synced || l.instrumental { return .found(l) }
                    if let s = await search(q), s.synced { return .found(s) }
                    return .found(l)
                }
                if c != 404 && c != 200 { failed = true }
            } else {
                failed = true
            }
        }
        if let s = await search(q) { return .found(s) }
        return failed ? .failed : .missing
    }

    private func search(_ q: LyricsQuery) async -> Lyrics? {
        guard let u = LRCLIB.searchURL(q), let (d, c) = await get(u), c == 200 else { return nil }
        return LRCLIB.best(LRCLIB.decodeMany(d), for: q)?.lyrics
    }
}

enum LyricsAudio {
    static func outputLatency() -> TimeInterval {
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr else { return 0 }
        func u32(_ sel: AudioObjectPropertySelector, _ obj: AudioObjectID) -> UInt32 {
            var v: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            var ad = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            return AudioObjectGetPropertyData(obj, &ad, 0, nil, &s, &v) == noErr ? v : 0
        }
        var rate: Float64 = 0
        var rs = UInt32(MemoryLayout<Float64>.size)
        var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(dev, &ra, 0, nil, &rs, &rate) == noErr, rate > 0 else { return 0 }
        var frames = u32(kAudioDevicePropertyLatency, dev) + u32(kAudioDevicePropertySafetyOffset, dev) + u32(kAudioDevicePropertyBufferFrameSize, dev)
        var ss: UInt32 = 0
        var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyDataSize(dev, &sa, 0, nil, &ss) == noErr, ss >= UInt32(MemoryLayout<AudioStreamID>.size) {
            var ids = [AudioStreamID](repeating: 0, count: Int(ss) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(dev, &sa, 0, nil, &ss, &ids) == noErr, let f = ids.first {
                var v: UInt32 = 0
                var s = UInt32(MemoryLayout<UInt32>.size)
                var ad = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyLatency, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                if AudioObjectGetPropertyData(f, &ad, 0, nil, &s, &v) == noErr { frames += v }
            }
        }
        return min(Double(frames) / rate, 0.5)
    }

    @MainActor private static var listeners: [(TimeInterval) -> Void] = []
    @MainActor private static var installed = false

    @MainActor static func onLatency(_ f: @escaping (TimeInterval) -> Void) {
        listeners.append(f)
        guard !installed else { return }
        installed = true
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { _, _ in
            MainActor.assumeIsolated {
                let l = outputLatency()
                for f in listeners { f(l) }
            }
        }
    }
}
