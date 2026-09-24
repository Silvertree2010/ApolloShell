import Foundation
import Testing
@testable import ApolloShellCore

/// Zeilen im Format des mediaremote-adapters (README "stream", Aufruf mit
/// --micros). Aufbau abgeschaut an echter Ausgabe vom 14.09. (pausiertes
/// Video im Browser); Inhalte erfunden.
private enum Fixture {
    /// Spielt seit 34 s, 3:05 lang, Zeitstempel 2026-09-14 10:00:00 UTC.
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

@Suite("Now Playing: Stream lesen")
struct MediaStreamTests {
    @Test("Volle Zeile ergibt den ganzen Zustand")
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

    @Test("Cover wird aus Base64 dekodiert (JSON-Escapes inklusive)")
    func artwork() throws {
        let state = Fixture.state(Fixture.full)
        let artwork = try #require(state.artwork)
        #expect(Array(artwork) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(state.artworkRevision == 1)
        #expect(state.fields["artworkData"] == nil)
        #expect(state.fields["artworkMimeType"] == .string("image/png"))
    }

    @Test("Bool und Zahl bleiben getrennt")
    func boolVersusNumber() {
        let state = Fixture.state(Fixture.full)
        #expect(state.fields["playing"] == .bool(true))
        #expect(state.fields["playbackRate"] == .number(1))
        #expect(state.fields["processIdentifier"] == .number(4242))
    }

    @Test("Leere Nutzlast: nichts laeuft")
    func emptyPayload() {
        #expect(Fixture.state(Fixture.empty).nowPlaying == nil)
        #expect(Fixture.state(Fixture.full, Fixture.empty).nowPlaying == nil)
        #expect(Fixture.state(Fixture.full, Fixture.empty).artwork == nil)
    }

    @Test("Diff wird in den Zustand gemischt, der Rest bleibt")
    func diffMerges() throws {
        let state = Fixture.state(Fixture.full, Fixture.paused)
        let playing = try #require(state.nowPlaying)
        #expect(!playing.isPlaying)
        #expect(playing.playbackRate == 0)
        #expect(playing.elapsed == 61)
        #expect(playing.title == "Bergwind")
        #expect(playing.album == "Nachtfahrt")
        #expect(playing.duration == 185)
        // Ein Diff ohne Cover laesst das Cover stehen und baut es nicht neu.
        #expect(state.artwork != nil)
        #expect(state.artworkRevision == 1)
    }

    @Test("null im Diff entfernt das Feld")
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

    @Test("Neue volle Zeile ersetzt alles, auch das Cover")
    func fullReplaces() throws {
        let next = #"{"type":"data","diff":false,"payload":{"title":"Föhn","playing":true,"processIdentifier":4242}}"#
        let state = Fixture.state(Fixture.full, next)
        let playing = try #require(state.nowPlaying)
        #expect(playing.title == "Föhn")
        #expect(playing.artist == nil)
        #expect(playing.duration == nil)
        #expect(state.artwork == nil)
    }

    @Test("Ungueltige Zeilen werden verworfen", arguments: [
        "",
        "kein json",
        #"{"type":"error","payload":{}}"#,
        #"{"diff":false,"payload":{}}"#,
        "[1,2,3]",
    ])
    func invalidLines(line: String) {
        #expect(MediaStreamMessage.parse(line) == nil)
    }

    @Test("Ohne Titel oder mit leerem Titel: nichts zu zeigen", arguments: [
        #"{"type":"data","diff":false,"payload":{"playing":true,"artist":"X"}}"#,
        #"{"type":"data","diff":false,"payload":{"playing":true,"title":""}}"#,
        #"{"type":"data","diff":false,"payload":{"playing":true,"title":"   "}}"#,
    ])
    func missingTitle(line: String) {
        #expect(Fixture.state(line).nowPlaying == nil)
    }

    @Test("Leeres Album (Browser-Video) zaehlt als nicht da")
    func emptyAlbum() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Video","album":"","artist":"Channel","playing":false}}"#
        let playing = try #require(Fixture.state(line).nowPlaying)
        #expect(playing.album == nil)
        #expect(playing.artist == "Channel")
    }

    @Test("Ohne --micros: Sekunden und ISO-Zeitstempel")
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

    @Test("Laenge 0 heisst unbekannt")
    func zeroDuration() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Live","playing":true,"durationMicros":0}}"#
        #expect(try #require(Fixture.state(line).nowPlaying).duration == nil)
    }

    @Test("Quelle: uebergeordnete App vor dem Hilfsprozess")
    func sourceApp() {
        var playing = MediaNowPlaying(title: "A", bundleIdentifier: "com.apple.WebKit.GPU", isPlaying: true)
        #expect(playing.sourceBundleIdentifier == "com.apple.WebKit.GPU")
        playing.parentBundleIdentifier = "com.apple.Safari"
        #expect(playing.sourceBundleIdentifier == "com.apple.Safari")
    }
}

@Suite("Now Playing: Zeilen puffern")
struct MediaLineBufferTests {
    /// Jedes Stueck einzeln anhaengen, Ergebnis als Texte.
    private func feed(_ chunks: [String]) -> [[String]] {
        var buffer = MediaLineBuffer()
        var result: [[String]] = []
        for chunk in chunks {
            let lines = buffer.append(Data(chunk.utf8))
            result.append(lines.map { String(decoding: $0, as: UTF8.self) })
        }
        return result
    }

    @Test("Zeile ueber mehrere Stuecke, mehrere Zeilen in einem Stueck")
    func splitsAcrossChunks() {
        let result = feed(["{\"a\":", "1}\n{\"b\"", ":2}\n\n{\"c\":3}\n{\"d", "\":4}\n"])
        #expect(result == [[], ["{\"a\":1}"], ["{\"b\":2}", "{\"c\":3}"], ["{\"d\":4}"]])
    }

    @Test("Ohne Umbruch bleibt alles im Puffer")
    func keepsPartial() {
        #expect(feed(["abc", "def", "\n"]) == [[], [], ["abcdef"]])
    }

    @Test("Grosse Zeile in vielen Stuecken bleibt heil")
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

@Suite("Now Playing: Zeit")
struct MediaTimeTests {
    private func playing(elapsed: TimeInterval, rate: Double?, isPlaying: Bool) -> MediaNowPlaying {
        MediaNowPlaying(title: "A", isPlaying: isPlaying, duration: 185, elapsed: elapsed,
                        timestamp: Fixture.referenceDate, playbackRate: rate)
    }

    @Test("Hochrechnen aus Zeitstempel und Tempo", arguments: [
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

    @Test("Ohne Zeitstempel oder Stand")
    func extrapolationMissing() {
        let now = Fixture.referenceDate.addingTimeInterval(5)
        let noTimestamp = MediaNowPlaying(title: "A", isPlaying: true, duration: 185, elapsed: 10)
        #expect(noTimestamp.elapsed(at: now) == 10)
        let noElapsed = MediaNowPlaying(title: "A", isPlaying: true, duration: 185, timestamp: Fixture.referenceDate)
        #expect(noElapsed.elapsed(at: now) == nil)
        #expect(noElapsed.progress(at: now) == 0)
    }

    @Test("Fortschritt als Anteil, begrenzt")
    func progress() {
        let now = Fixture.referenceDate.addingTimeInterval(27)
        #expect(playing(elapsed: 10, rate: 1, isPlaying: true).progress(at: now) == 37.0 / 185.0)
        let live = MediaNowPlaying(title: "A", isPlaying: true, elapsed: 10, timestamp: Fixture.referenceDate)
        #expect(live.progress(at: now) == 0)
    }

    @Test("Abgespielte Zeit", arguments: [
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

    @Test("Unendlich und NaN werden 0:00")
    func clockDegenerate() {
        #expect(MediaTime.clock(.nan) == "0:00")
        #expect(MediaTime.clock(.infinity) == "0:00")
    }

    @Test("Restzeit", arguments: [
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

@Suite("Now Playing: Adapter-Aufrufe")
struct MediaAdapterTests {
    @Test("Steuerbefehle nach der README-Tabelle", arguments: [
        (2, "2"),
        (4, "4"),
        (5, "5"),
    ])
    func commands(rawValue: Int, argument: String) throws {
        let command = try #require(MediaCommand(rawValue: rawValue))
        #expect(command.arguments == ["send", argument])
    }

    @Test("Nur Wiedergabe, weiter, zurueck - nichts, was abspielt ohne Klick")
    func commandSet() {
        #expect(MediaCommand.allCases.map(\.rawValue) == [2, 4, 5])
    }

    @Test("Stream mit Mikrosekunden und Entprellung, Diff an")
    func streamArguments() {
        #expect(MediaAdapter.streamArguments == ["stream", "--micros", "--debounce=100"])
    }

    @Test("Neustart-Pausen wachsen, dann ist Schluss", arguments: [
        (1, TimeInterval?.some(2)),
        (2, TimeInterval?.some(4)),
        (5, TimeInterval?.some(32)),
        (6, TimeInterval?.none),
        (0, TimeInterval?.none),
    ])
    func restartDelay(failures: Int, delay: TimeInterval?) {
        #expect(MediaRestart.delay(afterFailures: failures) == delay)
    }

    @Test("Lange gelaufen: Zaehler beginnt neu", arguments: [
        (4, 2.0, 5),
        (4, 30.0, 1),
        (0, 0.5, 1),
    ])
    func restartCounter(previous: Int, runtime: TimeInterval, expected: Int) {
        #expect(MediaRestart.failures(previous: previous, runtime: runtime) == expected)
    }
}
