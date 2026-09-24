import Foundation

// "Now Playing" aus dem mediaremote-adapter (extras/mediaremote-adapter).
// Der Adapter laeuft als `/usr/bin/perl ... stream` und schreibt pro
// Aenderung eine JSON-Zeile:
//
//   {"type":"data","diff":false,"payload":{"title":"…","playing":true,…}}
//
// `diff: false` ist der ganze Zustand, `diff: true` nur die geaenderten
// Felder; ein Feld mit `null` ist weggefallen. Leere Nutzlast = nichts
// laeuft. Hier steht nur die reine Logik (Zeilen zerlegen, Diffs
// zusammenfuehren, Zeit hochrechnen, Zeit formatieren); Prozess und
// Oberflaeche liegen in der App (MediaModel.swift).

// MARK: - JSON-Werte

/// Ein Wert aus der Nutzlast. Eigener kleiner Typ statt `[String: Any]`:
/// der ist nicht Sendable, und die Zeilen werden abseits des Hauptthreads
/// dekodiert.
public enum MediaValue: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    /// Listen und Objekte: kommen im Adapter nicht vor, sollen eine Zeile
    /// aber nicht unlesbar machen.
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool vor Double: JSONDecoder liest `true` nicht als Zahl und `1`
        // nicht als Bool, die Reihenfolge trennt die beiden also sauber.
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

/// Schluessel der Nutzlast (README des Adapters, Befehl `get`).
enum MediaKey {
    static let title = "title"
    static let artist = "artist"
    static let album = "album"
    static let bundleIdentifier = "bundleIdentifier"
    static let parentBundleIdentifier = "parentApplicationBundleIdentifier"
    static let playing = "playing"
    static let playbackRate = "playbackRate"
    static let artworkData = "artworkData"
    // Mit --micros (so startet die App den Adapter): ganze Mikrosekunden.
    static let durationMicros = "durationMicros"
    static let elapsedMicros = "elapsedTimeMicros"
    static let timestampMicros = "timestampEpochMicros"
    // Ohne --micros: Sekunden, der Zeitstempel als ISO-Text - auf die
    // Sekunde gerundet, deshalb nur Rueckfall.
    static let duration = "duration"
    static let elapsed = "elapsedTime"
    static let timestamp = "timestamp"
}

// MARK: - Zeilen

/// Eine Datenzeile des Streams.
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
        // Heute gibt es nur "data"; kaeme ein neuer Typ dazu, darf er nicht
        // als Zustand missverstanden werden.
        let type = try container.decode(String.self, forKey: .type)
        guard type == "data" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Typ \(type)")
        }
        diff = try container.decodeIfPresent(Bool.self, forKey: .diff) ?? false
        payload = try container.decodeIfPresent([String: MediaValue].self, forKey: .payload) ?? [:]
    }

    /// `nil` fuer alles, was keine gueltige Datenzeile ist - eine kaputte
    /// Zeile soll den Stream nicht anhalten.
    public static func parse(_ line: Data) -> MediaStreamMessage? {
        try? JSONDecoder().decode(MediaStreamMessage.self, from: line)
    }

    public static func parse(_ line: String) -> MediaStreamMessage? {
        parse(Data(line.utf8))
    }
}

/// Zerlegt die Ausgabe der Pipe in Zeilen. Eine Zeile mit Cover ist einige
/// hundert KB gross und kommt in mehreren Stuecken an; was nach dem letzten
/// Zeilenumbruch steht, wartet auf den Rest.
public struct MediaLineBuffer: Sendable {
    /// Ohne Zeilenumbruch so viel gelesen: das ist kein Adapter-Output mehr,
    /// verwerfen statt endlos puffern.
    public static let maximumLineLength = 32 << 20

    private var pending = Data()
    /// Bis hierhin ist `pending` schon nach Umbruechen abgesucht - sonst
    /// wuerde eine grosse Zeile bei jedem Stueck von vorn durchsucht.
    private var searched = 0

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        var lineStart = pending.startIndex
        var searchFrom = pending.startIndex + searched
        while let newline = pending[searchFrom...].firstIndex(of: 0x0A) {
            // Leere Zeilen gibt der Adapter nicht aus; falls doch, stoeren sie nicht.
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

// MARK: - Zustand

/// Der zusammengefuehrte Zustand eines Stream-Prozesses. Jeder neue Prozess
/// beginnt mit einem neuen Zustand: Diffs beziehen sich nur auf die letzte
/// volle Zeile desselben Prozesses.
public struct MediaStreamState: Sendable {
    public private(set) var fields: [String: MediaValue] = [:]
    /// Cover als Bilddaten (im Stream Base64). Getrennt von `fields`, damit
    /// es nur einmal dekodiert wird und nicht doppelt im Speicher liegt.
    public private(set) var artwork: Data?
    /// Zaehlt jede Aenderung am Cover - die Oberflaeche baut das Bild nur
    /// dann neu, statt bei jedem Diff grosse Daten zu vergleichen.
    public private(set) var artworkRevision = 0

    public init() {}

    public mutating func apply(_ message: MediaStreamMessage) {
        if !message.diff { fields.removeAll() }
        for (key, value) in message.payload where key != MediaKey.artworkData {
            // null heisst im Diff "weggefallen"; in einer vollen Zeile meldet
            // der Player das Feld leer - beides bedeutet: nicht da.
            if value == .null {
                fields.removeValue(forKey: key)
            } else {
                fields[key] = value
            }
        }
        // Eine volle Zeile ohne Cover heisst: kein Cover. Ein Diff ohne den
        // Schluessel laesst es stehen.
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

/// Was gerade laeuft, fertig fuer die Oberflaeche.
public struct MediaNowPlaying: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var bundleIdentifier: String?
    /// Z. B. der Browser, wenn ein Hilfsprozess von ihm die Wiedergabe meldet.
    public var parentBundleIdentifier: String?
    public var isPlaying: Bool
    /// `nil` = unbekannt (Livestream) - dann keine Restzeit.
    public var duration: TimeInterval?
    /// Abgespielte Zeit zum Zeitpunkt `timestamp`, nicht jetzt.
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

    /// `nil` ohne Titel: der Adapter gibt dann ohnehin nichts aus, und ohne
    /// Titel gibt es nichts Sinnvolles zu zeigen.
    public init?(fields: [String: MediaValue]) {
        guard let title = Self.text(fields[MediaKey.title]) else { return nil }
        self.title = title
        // Browser melden bei Videos oft "" als Album (gemessen: YouTube in
        // Vivaldi) - leer zaehlt als nicht da.
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

    /// Welche App als Quelle gezeigt wird: die uebergeordnete, wenn es sie
    /// gibt (Browser statt seines Hilfsprozesses).
    public var sourceBundleIdentifier: String? {
        parentBundleIdentifier ?? bundleIdentifier
    }

    /// Abgespielte Zeit jetzt. Der Adapter meldet nur bei Aenderungen
    /// (Pause, Sprung, neuer Titel), dazwischen wird hochgerechnet: Stand zum
    /// Zeitstempel plus vergangene Zeit mal Tempo. Pausiert oder Tempo 0
    /// (Puffern) bleibt die Zeit stehen. Begrenzt auf 0 bis Laenge, damit
    /// ein verspaeteter Titelwechsel nicht ueber das Ende hinauszaehlt.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite else { return nil }
        var value = elapsed
        let rate = isPlaying ? (playbackRate ?? 1) : 0
        if rate > 0, let timestamp {
            // Zeitstempel in der Zukunft (Uhr des Players voraus): nicht zurueck.
            value += max(0, now.timeIntervalSince(timestamp)) * rate
        }
        return min(max(value, 0), duration ?? .infinity)
    }

    /// Anteil 0...1 fuer Balken und Bogen; 0, wenn die Laenge unbekannt ist.
    public func progress(at now: Date) -> Double {
        guard let duration, let elapsed = elapsed(at: now) else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}

// MARK: - Zeit

/// Zeiten wie in Apple Music: "1:05", ab einer Stunde "1:02:03", Restzeit
/// mit Minus davor.
public enum MediaTime {
    /// Anzeige, wenn die Laenge unbekannt ist (Caelestia: "--:--").
    public static let unknown = "--:--"

    /// Abgespielte Zeit, abgerundet: "0:59" bis die volle Sekunde erreicht ist.
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

    /// Restzeit, aufgerundet - so ergeben beide Anzeigen zusammen immer die
    /// Laenge (0:34 und -2:31 bei 3:05).
    public static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let rest = max(0, duration - max(0, elapsed))
        return "-" + clock(rest.rounded(.up))
    }
}

// MARK: - Adapter-Aufrufe

/// Steuerbefehle fuer `send` (README des Adapters, Tabelle "send COMMAND").
public enum MediaCommand: Int, Sendable, CaseIterable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5

    /// Argumente nach Skript und Framework, z. B. `send 2`.
    public var arguments: [String] {
        ["send", String(rawValue)]
    }
}

public enum MediaAdapter {
    /// `--micros`: Zeitstempel auf die Mikrosekunde statt als auf Sekunden
    /// gerundeter Text. `--debounce=100`: ein Titelwechsel kommt sonst als
    /// Salve kleiner Zeilen (Titel, dann Kuenstler, dann Cover).
    /// Diff bleibt an: sonst kaeme das Cover bei jeder Pause erneut mit.
    public static let streamArguments = ["stream", "--micros", "--debounce=100"]
}

/// Neustart, wenn der Stream-Prozess stirbt, obwohl das Dashboard offen
/// ist. Der Adapter raet, nach einem fatalen Fehler nicht endlos neu zu
/// starten - deshalb wachsende Pausen und nach fuenf fruehen Toden Schluss
/// (bis zum naechsten Oeffnen).
public enum MediaRestart {
    /// So lange gelaufen: das war kein Startfehler, der Zaehler beginnt neu.
    public static let stableRuntime: TimeInterval = 30
    public static let maximumAttempts = 5

    /// Zaehlerstand nach einem Tod nach `runtime` Sekunden.
    public static func failures(previous: Int, runtime: TimeInterval) -> Int {
        runtime >= stableRuntime ? 1 : previous + 1
    }

    /// Wartezeit vor dem naechsten Versuch: 2, 4, 8, 16, 32 s; danach `nil`.
    public static func delay(afterFailures failures: Int) -> TimeInterval? {
        guard failures >= 1, failures <= maximumAttempts else { return nil }
        return TimeInterval(1 << failures)
    }
}
