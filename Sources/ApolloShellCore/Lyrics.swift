import Foundation

public struct LyricWord: Sendable, Equatable, Codable {
    public var t: TimeInterval
    public var s: String
    public var e: TimeInterval?

    public init(t: TimeInterval, s: String, e: TimeInterval? = nil) {
        self.t = t
        self.s = s
        self.e = e
    }
}

public struct LyricLine: Sendable, Equatable, Codable {
    public var t: TimeInterval
    public var s: String
    public var w: [LyricWord]
    public var e: TimeInterval?

    public init(t: TimeInterval, s: String, w: [LyricWord] = [], e: TimeInterval? = nil) {
        self.t = t
        self.s = s
        self.w = w
        self.e = e
    }

    public var isBreak: Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct Lyrics: Sendable, Equatable, Codable {
    public var lines: [LyricLine]
    public var synced: Bool
    public var instrumental: Bool

    public init(lines: [LyricLine], synced: Bool, instrumental: Bool = false) {
        self.lines = lines
        self.synced = synced
        self.instrumental = instrumental
    }

    public static let instrumentalTrack = Lyrics(lines: [], synced: false, instrumental: true)

    public static func plain(_ text: String) -> Lyrics {
        let ls = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { LyricLine(t: 0, s: String($0).trimmingCharacters(in: .whitespaces)) }
        var out: [LyricLine] = []
        for l in ls where !(l.isBreak && (out.last?.isBreak ?? true)) { out.append(l) }
        while out.last?.isBreak == true { out.removeLast() }
        return Lyrics(lines: out, synced: false)
    }
}

public enum LRC {
    public static func parse(_ src: String) -> Lyrics? {
        var off: TimeInterval = 0
        var out: [LyricLine] = []
        for raw in src.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var ts: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = time(tag) {
                    ts.append(t)
                } else if tag.lowercased().hasPrefix("offset:") {
                    let v = tag.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    if let ms = Double(v) { off = ms / 1000 }
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !ts.isEmpty else { continue }
            let (text, words) = enhanced(String(rest))
            for t in ts { out.append(LyricLine(t: t, s: text, w: words)) }
        }
        guard !out.isEmpty else { return nil }
        if off != 0 {
            out = out.map { l in
                LyricLine(t: max(0, l.t - off), s: l.s, w: l.w.map { LyricWord(t: max(0, $0.t - off), s: $0.s) })
            }
        }
        out = out.enumerated().sorted { a, b in a.element.t == b.element.t ? a.offset < b.offset : a.element.t < b.element.t }.map(\.element)
        var tidy: [LyricLine] = []
        for l in out {
            if l.isBreak, let last = tidy.last, last.isBreak { continue }
            tidy.append(l)
        }
        while tidy.first?.isBreak == true { tidy.removeFirst() }
        guard !tidy.isEmpty else { return nil }
        return Lyrics(lines: tidy, synced: true)
    }

    static func time(_ tag: Substring) -> TimeInterval? {
        let p = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2 || p.count == 3 else { return nil }
        let nums = p.dropLast().map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.allSatisfy({ $0 != nil }) else { return nil }
        var sec = p.last!.trimmingCharacters(in: .whitespaces)
        sec = sec.replacingOccurrences(of: ",", with: ".")
        if sec.filter({ $0 == ":" }).count > 0 { return nil }
        guard let s = Double(sec), s >= 0, s < 60, sec.first?.isNumber == true else { return nil }
        let n = nums.compactMap { $0 }
        guard n.allSatisfy({ $0 >= 0 }) else { return nil }
        let m = n.count == 2 ? n[0] * 60 + n[1] : n[0]
        return TimeInterval(m) * 60 + s
    }

    static func enhanced(_ s: String) -> (String, [LyricWord]) {
        guard s.contains("<") else { return (s.trimmingCharacters(in: .whitespaces), []) }
        var words: [LyricWord] = []
        var plain = ""
        var cur: TimeInterval?
        var buf = ""
        var i = s.startIndex
        func flush() {
            if let c = cur, !buf.isEmpty { words.append(LyricWord(t: c, s: buf)) }
            plain += buf
            buf = ""
        }
        while i < s.endIndex {
            if s[i] == "<", let close = s[i...].firstIndex(of: ">"), let t = time(s[s.index(after: i)..<close]) {
                flush()
                cur = t
                i = s.index(after: close)
                continue
            }
            buf.append(s[i])
            i = s.index(after: i)
        }
        flush()
        let text = plain.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return (text, words.count >= 2 ? words : [])
    }
}

public struct LyricsTimeline: Sendable, Equatable {
    public let lyrics: Lyrics
    public let duration: TimeInterval?
    public static let lastLineHold: TimeInterval = 6
    public static let breakGap: TimeInterval = 8

    public init(_ l: Lyrics, duration: TimeInterval?) {
        lyrics = l
        self.duration = duration
    }

    public func index(at t: TimeInterval) -> Int? {
        let ls = lyrics.lines
        guard lyrics.synced, let first = ls.first, t >= first.t else { return nil }
        var lo = 0, hi = ls.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if ls[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func end(of i: Int) -> TimeInterval {
        let ls = lyrics.lines
        if let e = ls[i].e, e > ls[i].t { return e }
        let next = i + 1 < ls.count ? ls[i + 1].t : (duration ?? ls[i].t + Self.lastLineHold)
        return max(ls[i].t, next)
    }

    public func isSung(_ i: Int, at t: TimeInterval) -> Bool {
        t >= lyrics.lines[i].t && t < end(of: i)
    }

    public func progress(of i: Int, at t: TimeInterval) -> Double {
        let ls = lyrics.lines
        let a = ls[i].t
        var b = end(of: i)
        if !ls[i].w.isEmpty {
            let wb = wordEnd(i, ls[i].w.count - 1)
            b = min(b, wb)
        }
        guard b > a else { return 1 }
        return min(max((t - a) / (b - a), 0), 1)
    }

    func wordEnd(_ i: Int, _ k: Int) -> TimeInterval {
        let w = lyrics.lines[i].w
        if let e = w[k].e, e > w[k].t { return e }
        if k + 1 < w.count { return w[k + 1].t }
        let e = end(of: i)
        let est = w[k].t + max(0.25, min(1.2, Double(w[k].s.count) * 0.09))
        return min(e, est)
    }

    public func wordProgress(line i: Int, at t: TimeInterval) -> [Double] {
        let w = lyrics.lines[i].w
        return w.indices.map { k in
            let a = w[k].t, b = wordEnd(i, k)
            guard b > a else { return t >= a ? 1 : 0 }
            return min(max((t - a) / (b - a), 0), 1)
        }
    }

    public func isInstrumentalGap(at t: TimeInterval) -> Bool {
        guard let i = index(at: t) else {
            guard let f = lyrics.lines.first else { return false }
            return f.t - t > 3
        }
        if lyrics.lines[i].isBreak { return true }
        return end(of: i) - lyrics.lines[i].t > Self.breakGap && t - lyrics.lines[i].t > Self.breakGap * 0.6
    }

    public func nextStart(after t: TimeInterval) -> TimeInterval? {
        lyrics.lines.first { $0.t > t && !$0.isBreak }?.t
    }
}

public struct LyricsQuery: Sendable, Equatable, Hashable {
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: TimeInterval?

    public init(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    public init?(_ np: MediaNowPlaying) {
        guard let a = np.artist else { return nil }
        self.init(title: np.title, artist: a, album: np.album, duration: np.duration)
    }

    public var key: String {
        let d = duration.map { String(Int($0.rounded())) } ?? "?"
        return [Self.norm(artist), Self.norm(title), d].joined(separator: "|")
    }

    static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public var cleanTitle: String {
        var t = title
        let pats = [
            #"\s*[\(\[][^\)\]]*(feat\.?|ft\.?|with |remaster|live|version|edit|mix|mono|stereo|deluxe|bonus|explicit)[^\)\]]*[\)\]]"#,
            #"\s+-\s+.*(remaster|live|version|edit|mix|mono|stereo|single|radio).*$"#,
        ]
        for p in pats {
            t = t.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? title : t
    }

    public var primaryArtist: String {
        let seps = [", ", " & ", " feat. ", " ft. ", " x ", " X ", " featuring "]
        var a = artist
        for s in seps {
            if let r = a.range(of: s) { a = String(a[..<r.lowerBound]) }
        }
        return a.trimmingCharacters(in: .whitespaces)
    }
}

public struct LRCLIBRecord: Sendable, Equatable, Codable {
    public var id: Int?
    public var trackName: String?
    public var artistName: String?
    public var albumName: String?
    public var duration: Double?
    public var instrumental: Bool?
    public var plainLyrics: String?
    public var syncedLyrics: String?

    public init(id: Int? = nil, trackName: String? = nil, artistName: String? = nil, albumName: String? = nil,
                duration: Double? = nil, instrumental: Bool? = nil, plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.instrumental = instrumental
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
    }

    public var lyricsfile: String?
    public var hasWordSync: Bool?

    public var lyrics: Lyrics? {
        if let f = lyricsfile, let l = LyricsFile.parse(f) { return l }
        if let s = syncedLyrics, let l = LRC.parse(s) { return l }
        if instrumental == true { return .instrumentalTrack }
        if let p = plainLyrics, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .plain(p) }
        return nil
    }
}

public enum LRCLIB {
    public static let base = URL(string: "https://lrclib.net/api/")!
    public static let maxDurationDiff: TimeInterval = 2

    public static func getURL(_ q: LyricsQuery) -> URL? {
        guard let d = q.duration else { return nil }
        var c = URLComponents(url: base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: q.title),
            URLQueryItem(name: "artist_name", value: q.artist),
        ]
        if let a = q.album { items.append(URLQueryItem(name: "album_name", value: a)) }
        items.append(URLQueryItem(name: "duration", value: String(Int(d.rounded()))))
        c.queryItems = items
        return c.url
    }

    public static func searchURL(_ q: LyricsQuery) -> URL? {
        var c = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "track_name", value: q.cleanTitle),
            URLQueryItem(name: "artist_name", value: q.primaryArtist),
        ]
        return c.url
    }

    public static func decodeOne(_ d: Data) -> LRCLIBRecord? {
        try? JSONDecoder().decode(LRCLIBRecord.self, from: d)
    }

    public static func decodeMany(_ d: Data) -> [LRCLIBRecord] {
        (try? JSONDecoder().decode([LRCLIBRecord].self, from: d)) ?? []
    }

    public static func best(_ rs: [LRCLIBRecord], for q: LyricsQuery) -> LRCLIBRecord? {
        let ok = rs.filter { r in
            guard let d = q.duration, let rd = r.duration else { return q.duration == nil }
            return abs(rd - d) <= maxDurationDiff
        }
        let want = LyricsQuery.norm(q.cleanTitle)
        func score(_ r: LRCLIBRecord) -> Double {
            var s = 0.0
            if r.syncedLyrics?.isEmpty == false || r.lyricsfile?.isEmpty == false { s += 100 }
            if r.syncedLyrics?.contains("<") == true || r.hasWordSync == true { s += 10 }
            if let t = r.trackName, LyricsQuery.norm(LyricsQuery(title: t, artist: "").cleanTitle) == want { s += 20 }
            if let d = q.duration, let rd = r.duration { s -= abs(rd - d) * 5 }
            if r.plainLyrics?.isEmpty == false { s += 1 }
            if r.instrumental == true { s += 0.5 }
            return s
        }
        return ok.filter { $0.lyrics != nil }.max { score($0) < score($1) }
    }
}

public struct LyricsOffsets: Sendable, Equatable, Codable {
    public var songs: [String: Double] = [:]
    public var players: [String: Double] = [:]

    public init() {}

    public static let step: Double = 0.1
    public static let limit: Double = 5

    public func total(key: String, player: String?) -> Double {
        (songs[key] ?? 0) + (player.flatMap { players[$0] } ?? 0)
    }

    public mutating func nudge(key: String, by d: Double) {
        let v = min(max((songs[key] ?? 0) + d, -Self.limit), Self.limit)
        let r = (v * 100).rounded() / 100
        songs[key] = abs(r) < 0.001 ? nil : r
    }
}

public struct LyricsClock: Sendable, Equatable {
    public var np: MediaNowPlaying
    public var outputLatency: TimeInterval
    public var offset: TimeInterval

    public init(np: MediaNowPlaying, outputLatency: TimeInterval = 0, offset: TimeInterval = 0) {
        self.np = np
        self.outputLatency = outputLatency
        self.offset = offset
    }

    public func position(at now: Date) -> TimeInterval? {
        guard let e = np.elapsed(at: now) else { return nil }
        let heard = np.isPlaying ? e - outputLatency : e
        return max(0, heard + offset)
    }
}

public enum LyricsFile {
    public static func parse(_ src: String) -> Lyrics? {
        var lines: [LyricLine] = []
        var cur: LyricLine?
        var word: LyricWord?
        var inLines = false, inst = false
        var li = -1, wi = -1
        func endWord() {
            if let w = word, cur != nil { cur!.w.append(w) }
            word = nil
        }
        func endLine() {
            endWord()
            if let l = cur { lines.append(l) }
            cur = nil
            wi = -1
        }
        for raw in src.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true) {
            let ind = raw.prefix { $0 == " " }.count
            var ln = raw.drop { $0 == " " }
            let item = ln.hasPrefix("- ")
            if ind == 0 && !item {
                endLine()
                inLines = ln.hasPrefix("lines:")
                continue
            }
            guard inLines else {
                if let v = field(ln, "instrumental") { inst = v == "true" }
                continue
            }
            if item {
                ln = ln.dropFirst(2)
                if li < 0 { li = ind }
                if ind == li {
                    endLine()
                    cur = LyricLine(t: 0, s: "")
                } else if wi >= 0 && ind >= wi {
                    endWord()
                    word = LyricWord(t: 0, s: "")
                } else {
                    continue
                }
            } else if wi >= 0 && ind <= wi {
                endWord()
                wi = -1
            }
            if ln.hasPrefix("words:") {
                endWord()
                wi = ind
                continue
            }
            guard let k = ln.firstIndex(of: ":") else { continue }
            let key = ln[..<k].trimmingCharacters(in: .whitespaces)
            let val = scalar(ln[ln.index(after: k)...])
            if word != nil {
                switch key {
                case "text": word!.s = val
                case "start_ms": word!.t = (Double(val) ?? 0) / 1000
                case "end_ms": word!.e = Double(val).map { $0 / 1000 }
                default: break
                }
            } else if cur != nil {
                switch key {
                case "text": cur!.s = val
                case "start_ms": cur!.t = (Double(val) ?? 0) / 1000
                case "end_ms": cur!.e = Double(val).map { $0 / 1000 }
                default: break
                }
            }
        }
        endLine()
        lines = lines.map { l in
            var l = l
            l.s = l.s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            if l.w.count < 2 { l.w = [] }
            return l
        }.sorted { $0.t < $1.t }
        guard !lines.isEmpty else { return inst ? .instrumentalTrack : nil }
        return Lyrics(lines: lines, synced: true)
    }

    static func field(_ ln: Substring, _ k: String) -> String? {
        guard ln.hasPrefix(k + ":") else { return nil }
        return scalar(ln.dropFirst(k.count + 1))
    }

    static func scalar(_ v: Substring) -> String {
        let t = v.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, t.first == "'", t.last == "'" {
            return String(t.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if t.count >= 2, t.first == "\"", t.last == "\"" {
            let j = "[" + t + "]"
            if let a = try? JSONDecoder().decode([String].self, from: Data(j.utf8)), let f = a.first { return f }
            return String(t.dropFirst().dropLast())
        }
        return t
    }
}
