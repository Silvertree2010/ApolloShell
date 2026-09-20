import Foundation

// "Now Playing" from the mediaremote-adapter (extras/mediaremote-adapter).
// The adapter runs as `/usr/bin/perl ... stream` and writes one JSON line
// per change:
//
//   {"type":"data","diff":false,"payload":{"title":"…","playing":true,…}}
//
// `diff: false` is the whole state, `diff: true` only the changed fields;
// a field with `null` is gone. An empty payload means nothing is playing.
// Only the pure logic lives here (splitting lines, merging diffs,
// extrapolating time, formatting time); the process and the UI live in
// the app (MediaModel.swift).

// MARK: - JSON values

/// A value from the payload. A small dedicated type instead of
/// `[String: Any]`: that isn't Sendable, and the lines are decoded off
/// the main thread.
public enum MediaValue: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    /// Lists and objects: don't occur in the adapter, but shouldn't make
    /// a line unreadable.
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Double: JSONDecoder doesn't read `true` as a number
        // and `1` not as a bool, so the order cleanly separates the two.
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self, value.isFinite { value } else { nil }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        default: nil
        }
    }
}

/// Payload keys (adapter README, `get` command).
enum MediaKey {
    static let title = "title"
    static let artist = "artist"
    static let album = "album"
    static let bundleIdentifier = "bundleIdentifier"
    static let parentBundleIdentifier = "parentApplicationBundleIdentifier"
    static let playing = "playing"
    static let playbackRate = "playbackRate"
    static let artworkData = "artworkData"
    // With --micros (how the app starts the adapter): whole microseconds.
    static let durationMicros = "durationMicros"
    static let elapsedMicros = "elapsedTimeMicros"
    static let timestampMicros = "timestampEpochMicros"
    // Without --micros: seconds, the timestamp as ISO text - rounded to
    // the second, so only a fallback.
    static let duration = "duration"
    static let elapsed = "elapsedTime"
    static let timestamp = "timestamp"
}

// MARK: - Lines

/// One data line of the stream.
public struct MediaStreamMessage: Sendable, Equatable, Decodable {
    public var diff: Bool
    public var payload: [String: MediaValue]

    public init(diff: Bool, payload: [String: MediaValue]) {
        self.diff = diff
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case type, diff, payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Today there is only "data"; if a new type were added, it must
        // not be mistaken for state.
        let type = try container.decode(String.self, forKey: .type)
        guard type == "data" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Type \(type)")
        }
        diff = try container.decodeIfPresent(Bool.self, forKey: .diff) ?? false
        payload = try container.decodeIfPresent([String: MediaValue].self, forKey: .payload) ?? [:]
    }

    /// `nil` for anything that isn't a valid data line - a broken line
    /// shouldn't stop the stream.
    public static func parse(_ line: Data) -> MediaStreamMessage? {
        try? JSONDecoder().decode(MediaStreamMessage.self, from: line)
    }

    public static func parse(_ line: String) -> MediaStreamMessage? {
        parse(Data(line.utf8))
    }
}

/// Splits the pipe's output into lines. A line with a cover is a few
/// hundred KB and arrives in several chunks; whatever comes after the
/// last line break waits for the rest.
public struct MediaLineBuffer: Sendable {
    /// This much read without a line break: that's no longer adapter
    /// output, discard it instead of buffering forever.
    public static let maximumLineLength = 32 << 20

    private var pending = Data()
    /// Up to here, `pending` has already been searched for line breaks -
    /// otherwise a large line would be searched from the start on every
    /// chunk.
    private var searched = 0

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        var lineStart = pending.startIndex
        var searchFrom = pending.startIndex + searched
        while let newline = pending[searchFrom...].firstIndex(of: 0x0A) {
            // The adapter doesn't emit empty lines; if it did, they wouldn't hurt.
            if newline > lineStart { lines.append(pending.subdata(in: lineStart..<newline)) }
            lineStart = newline + 1
            searchFrom = lineStart
        }
        if lineStart > pending.startIndex {
            pending = pending.subdata(in: lineStart..<pending.endIndex)
        }
        searched = pending.count
        if pending.count > Self.maximumLineLength {
            pending = Data()
            searched = 0
        }
        return lines
    }
}

// MARK: - State

/// The merged state of a stream process. Every new process starts with a
/// fresh state: diffs only relate to the last full line of the same
/// process.
public struct MediaStreamState: Sendable {
    public private(set) var fields: [String: MediaValue] = [:]
    /// Cover as image data (base64 in the stream). Separate from `fields`
    /// so it's only decoded once and doesn't sit in memory twice.
    public private(set) var artwork: Data?
    /// Counts every change to the cover - the UI only rebuilds the image
    /// then, instead of comparing large data on every diff.
    public private(set) var artworkRevision = 0

    public init() {}

    public mutating func apply(_ message: MediaStreamMessage) {
        if !message.diff { fields.removeAll() }
        for (key, value) in message.payload where key != MediaKey.artworkData {
            // null means "removed" in a diff; in a full line the player
            // reports the field as empty - both mean: not present.
            if value == .null {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
        // A full line without a cover means: no cover. A diff without the
        // key leaves it as is.
        if !message.diff || message.payload[MediaKey.artworkData] != nil {
            let data = message.payload[MediaKey.artworkData]?.string.flatMap { Data(base64Encoded: $0) }
            if data != artwork {
                artwork = data
                artworkRevision += 1
            }
        }
    }

    public var nowPlaying: MediaNowPlaying? {
        MediaNowPlaying(fields: fields)
    }
}

/// What's currently playing, ready for the UI.
public struct MediaNowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var bundleIdentifier: String?
    /// E.g. the browser, if one of its helper processes reports playback.
    public var parentBundleIdentifier: String?
    public var isPlaying: Bool
    /// `nil` = unknown (livestream) - then no remaining time.
    public var duration: TimeInterval?
    /// Elapsed time at the point `timestamp`, not now.
    public var elapsed: TimeInterval?
    public var timestamp: Date?
    public var playbackRate: Double?

    public init(
        title: String,
        artist: String? = nil,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        parentBundleIdentifier: String? = nil,
        isPlaying: Bool,
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        timestamp: Date? = nil,
        playbackRate: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.bundleIdentifier = bundleIdentifier
        self.parentBundleIdentifier = parentBundleIdentifier
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.playbackRate = playbackRate
    }

    /// `nil` without a title: the adapter doesn't emit anything then
    /// anyway, and without a title there's nothing useful to show.
    public init?(fields: [String: MediaValue]) {
        guard let title = Self.text(fields[MediaKey.title]) else { return nil }
        self.title = title
        // Browsers often report "" as album for videos (measured: YouTube
        // in Vivaldi) - empty counts as not present.
        artist = Self.text(fields[MediaKey.artist])
        album = Self.text(fields[MediaKey.album])
        bundleIdentifier = Self.text(fields[MediaKey.bundleIdentifier])
        parentBundleIdentifier = Self.text(fields[MediaKey.parentBundleIdentifier])
        isPlaying = fields[MediaKey.playing]?.bool ?? false
        playbackRate = fields[MediaKey.playbackRate]?.number

        let duration = fields[MediaKey.durationMicros]?.number.map { $0 / 1_000_000 } ?? fields[MediaKey.duration]?.number
        self.duration = duration.flatMap { $0 > 0 ? $0 : nil }
        elapsed = fields[MediaKey.elapsedMicros]?.number.map { $0 / 1_000_000 } ?? fields[MediaKey.elapsed]?.number
        if let micros = fields[MediaKey.timestampMicros]?.number {
            timestamp = Date(timeIntervalSince1970: micros / 1_000_000)
        } else if let text = fields[MediaKey.timestamp]?.string {
            timestamp = try? Date(text, strategy: .iso8601)
        } else {
            timestamp = nil
        }
    }

    private static func text(_ value: MediaValue?) -> String? {
        guard let text = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Which app is shown as the source: the parent one, if there is one
    /// (browser instead of its helper process).
    public var sourceBundleIdentifier: String? {
        parentBundleIdentifier ?? bundleIdentifier
    }

    /// Elapsed time right now. The adapter only reports on changes
    /// (pause, seek, new title), extrapolated in between: the value at
    /// `timestamp` plus elapsed time times rate. Paused or rate 0
    /// (buffering) leaves the time standing still. Clamped to 0 through
    /// duration, so a delayed title change doesn't count past the end.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite else { return nil }
        var value = elapsed
        let rate = isPlaying ? (playbackRate ?? 1) : 0
        if rate > 0, let timestamp {
            // Timestamp in the future (player's clock ahead): don't go back.
            value += max(0, now.timeIntervalSince(timestamp)) * rate
        }
        return min(max(value, 0), duration ?? .infinity)
    }

    /// Fraction 0...1 for the bar and arc; 0 if the length is unknown.
    public func progress(at now: Date) -> Double {
        guard let duration, let elapsed = elapsed(at: now) else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

// MARK: - Time

/// Times like in Apple Music: "1:05", from one hour on "1:02:03",
/// remaining time with a minus in front.
public enum MediaTime {
    /// Display when the length is unknown (Caelestia: "--:--").
    public static let unknown = "--:--"

    /// Elapsed time, rounded down: "0:59" until the full second is reached.
    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        let paddedSeconds = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }
        return "\(minutes):\(paddedSeconds)"
    }

    /// Remaining time, rounded up - so both displays together always add
    /// up to the length (0:34 and -2:31 at 3:05).
    public static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let rest = max(0, duration - max(0, elapsed))
        return "-" + clock(rest.rounded(.up))
    }
}

// MARK: - Adapter calls

/// Control commands for `send` (adapter README, "send COMMAND" table).
public enum MediaCommand: Int, Sendable, CaseIterable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5

    /// Arguments per script and framework, e.g. `send 2`.
    public var arguments: [String] {
        ["send", String(rawValue)]
    }
}

public enum MediaAdapter {
    /// `--micros`: timestamp down to the microsecond instead of text
    /// rounded to the second. `--debounce=100`: otherwise a title change
    /// arrives as a burst of small lines (title, then artist, then cover).
    /// Diff stays on: otherwise the cover would come along again on every
    /// pause.
    public static let streamArguments = ["stream", "--micros", "--debounce=100"]
}

/// Restart when the stream process dies while the dashboard is open. The
/// adapter advises against restarting endlessly after a fatal error -
/// hence growing pauses and giving up after five early deaths (until the
/// next time it's opened).
public enum MediaRestart {
    /// Ran this long: that wasn't a startup error, the counter resets.
    public static let stableRuntime: TimeInterval = 30
    public static let maximumAttempts = 5

    /// Counter value after a death following `runtime` seconds.
    public static func failures(previous: Int, runtime: TimeInterval) -> Int {
        runtime >= stableRuntime ? 1 : previous + 1
    }

    /// Wait time before the next attempt: 2, 4, 8, 16, 32 s; `nil` after that.
    public static func delay(afterFailures failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= maximumAttempts else { return nil }
        return TimeInterval(1 << failures)
    }
}
