import Foundation
import Testing
@testable import ApolloShellCore

/// Lines in the format of the mediaremote-adapter (README "stream", called
/// with --micros). The shape taken from real output of 14.09. (a paused video
/// in the browser); the contents made up.
private enum Fixture {
    /// Playing for 34 s, 3:05 long, the timestamp 2026-09-14 10:00:00 UTC.
    static let full = """
    {"type":"data","diff":false,"payload":{"playbackRate":1,"timestampEpochMicros":1789380000000000,\
    "album":"Nachtfahrt","elapsedTimeMicros":34000000,"playing":true,"bundleIdentifier":"com.spotify.client",\
    "processIdentifier":4242,"artworkData":"iVBORw0KGgo=","title":"Bergwind","artworkMimeType":"image\\/png",\
    "artist":"Die Rheintaler","durationMicros":185000000}}
    """

    static let paused = """
    {"type":"data","diff":true,"payload":{"playing":false,"playbackRate":0,\
    "elapsedTimeMicros":61000000,"timestampEpochMicros":1789380027000000}}
    """

    static let empty = #"{"type":"data","diff":false,"payload":{}}"#

    static var referenceDate: Date { Date(timeIntervalSince1970: 1_789_380_000) }

    static func state(_ lines: String...) -> MediaStreamState {
        var state = MediaStreamState()
        for line in lines {
            if let message = MediaStreamMessage.parse(line) { state.apply(message) }
        }
        return state
    }
}

@Suite("Now Playing: reading the stream")
struct MediaStreamTests {
    @Test("A full line gives the whole state")
    func fullLine() throws {
        let playing = try #require(Fixture.state(Fixture.full).nowPlaying)
        #expect(playing.title == "Bergwind")
        #expect(playing.artist == "Die Rheintaler")
        #expect(playing.album == "Nachtfahrt")
        #expect(playing.bundleIdentifier == "com.spotify.client")
        #expect(playing.isPlaying)
        #expect(playing.duration == 185)
        #expect(playing.elapsed == 34)
        #expect(playing.playbackRate == 1)
        #expect(playing.timestamp == Fixture.referenceDate)
    }

    @Test("The cover is decoded out of Base64 (JSON escapes included)")
    func artwork() throws {
        let state = Fixture.state(Fixture.full)
        let artwork = try #require(state.artwork)
        #expect(Array(artwork) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(state.artworkRevision == 1)
        #expect(state.fields["artworkData"] == nil)
        #expect(state.fields["artworkMimeType"] == .string("image/png"))
    }

    @Test("Bool and number stay apart")
    func boolVersusNumber() {
        let state = Fixture.state(Fixture.full)
        #expect(state.fields["playing"] == .bool(true))
        #expect(state.fields["playbackRate"] == .number(1))
        #expect(state.fields["processIdentifier"] == .number(4242))
    }

    @Test("An empty payload: nothing is playing")
    func emptyPayload() {
        #expect(Fixture.state(Fixture.empty).nowPlaying == nil)
        #expect(Fixture.state(Fixture.full, Fixture.empty).nowPlaying == nil)
        #expect(Fixture.state(Fixture.full, Fixture.empty).artwork == nil)
    }

    @Test("A diff is mixed into the state, the rest stays")
    func diffMerges() throws {
        let state = Fixture.state(Fixture.full, Fixture.paused)
        let playing = try #require(state.nowPlaying)
        #expect(!playing.isPlaying)
        #expect(playing.playbackRate == 0)
        #expect(playing.elapsed == 61)
        #expect(playing.title == "Bergwind")
        #expect(playing.album == "Nachtfahrt")
        #expect(playing.duration == 185)
        // A diff without a cover leaves the cover standing and does not rebuild it.
        #expect(state.artwork != nil)
        #expect(state.artworkRevision == 1)
    }

    @Test("null in the diff removes the field")
    func diffNullRemoves() throws {
        let line = #"{"type":"data","diff":true,"payload":{"album":null,"artworkData":null,"artworkMimeType":null}}"#
        let state = Fixture.state(Fixture.full, line)
        let playing = try #require(state.nowPlaying)
        #expect(playing.album == nil)
        #expect(playing.artist == "Die Rheintaler")
        #expect(state.artwork == nil)
        #expect(state.artworkRevision == 2)
        #expect(state.fields["artworkMimeType"] == nil)
    }

    @Test("A new full line replaces everything, the cover included")
    func fullReplaces() throws {
        let next = #"{"type":"data","diff":false,"payload":{"title":"Föhn","playing":true,"processIdentifier":4242}}"#
        let state = Fixture.state(Fixture.full, next)
        let playing = try #require(state.nowPlaying)
        #expect(playing.title == "Föhn")
        #expect(playing.artist == nil)
        #expect(playing.duration == nil)
        #expect(state.artwork == nil)
    }

    @Test("Invalid lines are thrown away", arguments: [
        "",
        "kein json",
        #"{"type":"error","payload":{}}"#,
        #"{"diff":false,"payload":{}}"#,
        "[1,2,3]",
    ])
    func invalidLines(line: String) {
        #expect(MediaStreamMessage.parse(line) == nil)
    }

    @Test("Without a title or with an empty title: nothing to show", arguments: [
        #"{"type":"data","diff":false,"payload":{"playing":true,"artist":"X"}}"#,
        #"{"type":"data","diff":false,"payload":{"playing":true,"title":""}}"#,
        #"{"type":"data","diff":false,"payload":{"playing":true,"title":"   "}}"#,
    ])
    func missingTitle(line: String) {
        #expect(Fixture.state(line).nowPlaying == nil)
    }

    @Test("An empty album (a browser video) counts as not there")
    func emptyAlbum() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Video","album":"","artist":"Kanal","playing":false}}"#
        let playing = try #require(Fixture.state(line).nowPlaying)
        #expect(playing.album == nil)
        #expect(playing.artist == "Kanal")
    }

    @Test("Without --micros: seconds and an ISO timestamp")
    func secondsFormat() throws {
        let line = """
        {"type":"data","diff":false,"payload":{"title":"A","playing":true,"duration":185.5,\
        "elapsedTime":34.25,"timestamp":"2026-09-14T10:00:00Z"}}
        """
        let playing = try #require(Fixture.state(line).nowPlaying)
        #expect(playing.duration == 185.5)
        #expect(playing.elapsed == 34.25)
        #expect(playing.timestamp == Fixture.referenceDate)
    }

    @Test("A length of 0 means unknown")
    func zeroDuration() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Live","playing":true,"durationMicros":0}}"#
        #expect(try #require(Fixture.state(line).nowPlaying).duration == nil)
    }

    @Test("The source: the parent app before the helper process")
    func sourceApp() {
        var playing = MediaNowPlaying(title: "A", bundleIdentifier: "com.apple.WebKit.GPU", isPlaying: true)
        #expect(playing.sourceBundleIdentifier == "com.apple.WebKit.GPU")
        playing.parentBundleIdentifier = "com.apple.Safari"
        #expect(playing.sourceBundleIdentifier == "com.apple.Safari")
    }
}

@Suite("Now Playing: buffering lines")
struct MediaLineBufferTests {
    /// Append every chunk one by one, the result as texts.
    private func feed(_ chunks: [String]) -> [[String]] {
        var buffer = MediaLineBuffer()
        var result: [[String]] = []
        for chunk in chunks {
            let lines = buffer.append(Data(chunk.utf8))
            result.append(lines.map { String(decoding: $0, as: UTF8.self) })
        }
        return result
    }

    @Test("A line over several chunks, several lines in one chunk")
    func splitsAcrossChunks() {
        let result = feed(["{\"a\":", "1}\n{\"b\"", ":2}\n\n{\"c\":3}\n{\"d", "\":4}\n"])
        #expect(result == [[], ["{\"a\":1}"], ["{\"b\":2}", "{\"c\":3}"], ["{\"d\":4}"]])
    }

    @Test("Without a break everything stays in the buffer")
    func keepsPartial() {
        #expect(feed(["abc", "def", "\n"]) == [[], [], ["abcdef"]])
    }

    @Test("A big line in many chunks stays whole")
    func largeLine() {
        let payload = String(repeating: "x", count: 200_000)
        var chunks: [String] = []
        var rest = Substring(payload + "\n")
        while !rest.isEmpty {
            chunks.append(String(rest.prefix(65_536)))
            rest = rest.dropFirst(65_536)
        }
        #expect(feed(chunks).flatMap { $0 } == [payload])
    }
}

@Suite("Now Playing: time")
struct MediaTimeTests {
    private func playing(elapsed: TimeInterval, rate: Double?, isPlaying: Bool) -> MediaNowPlaying {
        MediaNowPlaying(title: "A", isPlaying: isPlaying, duration: 185, elapsed: elapsed,
                        timestamp: Fixture.referenceDate, playbackRate: rate)
    }

    @Test("Working it out from the timestamp and the rate", arguments: [
        (10.0, Double?.some(1), true, 5.0, 15.0),     // normal
        (10.0, Double?.some(2), true, 5.0, 20.0),     // doppeltes Tempo
        (10.0, Double?.none, true, 5.0, 15.0),        // Tempo fehlt: 1
        (10.0, Double?.some(1), false, 5.0, 10.0),    // pausiert
        (10.0, Double?.some(0), true, 5.0, 10.0),     // puffert
        (180.0, Double?.some(1), true, 30.0, 185.0),  // nicht ueber das Ende
        (10.0, Double?.some(1), true, -3.0, 10.0),    // Zeitstempel in der Zukunft
    ])
    func extrapolation(elapsed: TimeInterval, rate: Double?, isPlaying: Bool, later: TimeInterval, expected: TimeInterval) {
        let now = Fixture.referenceDate.addingTimeInterval(later)
        #expect(playing(elapsed: elapsed, rate: rate, isPlaying: isPlaying).elapsed(at: now) == expected)
    }

    @Test("Without a timestamp or a position")
    func extrapolationMissing() {
        let now = Fixture.referenceDate.addingTimeInterval(5)
        let noTimestamp = MediaNowPlaying(title: "A", isPlaying: true, duration: 185, elapsed: 10)
        #expect(noTimestamp.elapsed(at: now) == 10)
        let noElapsed = MediaNowPlaying(title: "A", isPlaying: true, duration: 185, timestamp: Fixture.referenceDate)
        #expect(noElapsed.elapsed(at: now) == nil)
        #expect(noElapsed.progress(at: now) == 0)
    }

    @Test("The progress as a share, limited")
    func progress() {
        let now = Fixture.referenceDate.addingTimeInterval(27)
        #expect(playing(elapsed: 10, rate: 1, isPlaying: true).progress(at: now) == 37.0 / 185.0)
        let live = MediaNowPlaying(title: "A", isPlaying: true, elapsed: 10, timestamp: Fixture.referenceDate)
        #expect(live.progress(at: now) == 0)
    }

    @Test("The time played", arguments: [
        (0.0, "0:00"),
        (5.0, "0:05"),
        (65.0, "1:05"),
        (65.9, "1:05"),
        (600.0, "10:00"),
        (3723.0, "1:02:03"),
        (-3.0, "0:00"),
    ])
    func clock(seconds: TimeInterval, text: String) {
        #expect(MediaTime.clock(seconds) == text)
    }

    @Test("Infinity and NaN become 0:00")
    func clockDegenerate() {
        #expect(MediaTime.clock(.nan) == "0:00")
        #expect(MediaTime.clock(.infinity) == "0:00")
    }

    @Test("The time left", arguments: [
        (34.0, 185.0, "-2:31"),
        (34.4, 185.0, "-2:31"),
        (0.0, 185.0, "-3:05"),
        (185.0, 185.0, "-0:00"),
        (200.0, 185.0, "-0:00"),
        (10.0, 3725.0, "-1:01:55"),
    ])
    func remaining(elapsed: TimeInterval, duration: TimeInterval, text: String) {
        #expect(MediaTime.remaining(elapsed: elapsed, duration: duration) == text)
    }
}

@Suite("Now Playing: adapter calls")
struct MediaAdapterTests {
    @Test("The control commands by the README table", arguments: [
        (2, "2"),
        (4, "4"),
        (5, "5"),
    ])
    func commands(rawValue: Int, argument: String) throws {
        let command = try #require(MediaCommand(rawValue: rawValue))
        #expect(command.arguments == ["send", argument])
    }

    @Test("Only play, next, previous - nothing that plays without a click")
    func commandSet() {
        #expect(MediaCommand.allCases.map(\.rawValue) == [2, 4, 5])
    }

    @Test("The stream with microseconds and debouncing, diffs on")
    func streamArguments() {
        #expect(MediaAdapter.streamArguments == ["stream", "--micros", "--debounce=100"])
    }

    @Test("The restart pauses grow, then it is over", arguments: [
        (1, TimeInterval?.some(2)),
        (2, TimeInterval?.some(4)),
        (5, TimeInterval?.some(32)),
        (6, TimeInterval?.none),
        (0, TimeInterval?.none),
    ])
    func restartDelay(failures: Int, delay: TimeInterval?) {
        #expect(MediaRestart.delay(afterFailures: failures) == delay)
    }

    @Test("Running for a long time: the counter starts anew", arguments: [
        (4, 2.0, 5),
        (4, 30.0, 1),
        (0, 0.5, 1),
    ])
    func restartCounter(previous: Int, runtime: TimeInterval, expected: Int) {
        #expect(MediaRestart.failures(previous: previous, runtime: runtime) == expected)
    }
}
