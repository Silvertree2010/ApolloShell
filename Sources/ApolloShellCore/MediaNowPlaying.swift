import Foundation

public enum MediaValue: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
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

enum MediaKey {
    static let title = "title"
    static let artist = "artist"
    static let album = "album"
    static let bundleIdentifier = "bundleIdentifier"
    static let parentBundleIdentifier = "parentApplicationBundleIdentifier"
    static let playing = "playing"
    static let playbackRate = "playbackRate"
    static let artworkData = "artworkData"
    static let durationMicros = "durationMicros"
    static let elapsedMicros = "elapsedTimeMicros"
    static let timestampMicros = "timestampEpochMicros"
    static let duration = "duration"
    static let elapsed = "elapsedTime"
    static let timestamp = "timestamp"
}

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
        let type = try container.decode(String.self, forKey: .type)
        guard type == "data" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Typ \(type)")
        }
        diff = try container.decodeIfPresent(Bool.self, forKey: .diff) ?? false
        payload = try container.decodeIfPresent([String: MediaValue].self, forKey: .payload) ?? [:]
    }

    public static func parse(_ line: Data) -> MediaStreamMessage? {
        try? JSONDecoder().decode(MediaStreamMessage.self, from: line)
    }

    public static func parse(_ line: String) -> MediaStreamMessage? {
        parse(Data(line.utf8))
    }
}

public struct MediaLineBuffer: Sendable {
    public static let maximumLineLength = 32 << 20

    private var pending = Data()
    private var searched = 0

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        var lineStart = pending.startIndex
        var searchFrom = pending.startIndex + searched
        while let newline = pending[searchFrom...].firstIndex(of: 0x0A) {
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

public struct MediaStreamState: Sendable {
    public private(set) var fields: [String: MediaValue] = [:]
    public private(set) var artwork: Data?
    public private(set) var artworkRevision = 0

    public init() {}

    public mutating func apply(_ message: MediaStreamMessage) {
        if !message.diff { fields.removeAll() }
        for (key, value) in message.payload where key != MediaKey.artworkData {
            if value == .null {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
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

public struct MediaNowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var bundleIdentifier: String?
    public var parentBundleIdentifier: String?
    public var isPlaying: Bool
    public var duration: TimeInterval?
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

    public init?(fields: [String: MediaValue]) {
        guard let title = Self.text(fields[MediaKey.title]) else { return nil }
        self.title = title
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

    public var sourceBundleIdentifier: String? {
        parentBundleIdentifier ?? bundleIdentifier
    }

    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite else { return nil }
        var value = elapsed
        let rate = isPlaying ? (playbackRate ?? 1) : 0
        if rate > 0, let timestamp {
            value += max(0, now.timeIntervalSince(timestamp)) * rate
        }
        return min(max(value, 0), duration ?? .infinity)
    }

    public func progress(at now: Date) -> Double {
        guard let duration, let elapsed = elapsed(at: now) else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

public enum MediaTime {
    public static let unknown = "--:--"

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

    public static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let rest = max(0, duration - max(0, elapsed))
        return "-" + clock(rest.rounded(.up))
    }
}

public enum MediaCommand: Int, Sendable, CaseIterable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5

    public var arguments: [String] {
        ["send", String(rawValue)]
    }
}

public enum MediaAdapter {
    public static let streamArguments = ["stream", "--micros", "--debounce=100"]
}

public enum MediaRestart {
    public static let stableRuntime: TimeInterval = 30
    public static let maximumAttempts = 5

    public static func failures(previous: Int, runtime: TimeInterval) -> Int {
        runtime >= stableRuntime ? 1 : previous + 1
    }

    public static func delay(afterFailures failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= maximumAttempts else { return nil }
        return TimeInterval(1 << failures)
    }
}
