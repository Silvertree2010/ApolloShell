import Foundation
import Testing
@testable import ApolloShellCore

@Suite struct LRCTests {
    @Test func parsesBasicLines() throws {
        let l = try #require(LRC.parse("[ar:X]\n[00:01.50]Hello\n[00:03.250]World\n[01:02.00]Late"))
        #expect(l.synced)
        #expect(l.lines.map(\.t) == [1.5, 3.25, 62])
        #expect(l.lines.map(\.s) == ["Hello", "World", "Late"])
    }

    @Test func repeatedTimestampsAreSorted() throws {
        let l = try #require(LRC.parse("[00:10.00][00:30.00]Chorus\n[00:20.00]Verse"))
        #expect(l.lines.map(\.s) == ["Chorus", "Verse", "Chorus"])
        #expect(l.lines.map(\.t) == [10, 20, 30])
    }

    @Test func offsetTagShiftsEarlier() throws {
        let l = try #require(LRC.parse("[offset:+500]\n[00:02.00]A"))
        #expect(l.lines[0].t == 1.5)
    }

    @Test func enhancedWordTimes() throws {
        let l = try #require(LRC.parse("[00:01.00]<00:01.00>Hey <00:01.40>you <00:02.00>there"))
        #expect(l.lines[0].s == "Hey you there")
        #expect(l.lines[0].w.map(\.t) == [1, 1.4, 2])
    }

    @Test func collapsesBreaksAndRejectsJunk() throws {
        let l = try #require(LRC.parse("[00:00.50]\n[00:01.00]A\n[00:02.00]\n[00:03.00]\n[00:04.00]B"))
        #expect(l.lines.map(\.s) == ["A", "", "B"])
        #expect(LRC.parse("just text") == nil)
        #expect(LRC.parse("[ti:Only tags]") == nil)
        #expect(LRC.time("00:61.00") == nil)
        #expect(LRC.time("1:02:03.5") == 3723.5)
    }

    @Test func plainText() {
        let l = Lyrics.plain("a\r\n\r\n\r\nb\n\n")
        #expect(l.lines.map(\.s) == ["a", "", "b"])
        #expect(!l.synced)
    }
}

@Suite struct TimelineTests {
    let tl = LyricsTimeline(LRC.parse("[00:02.00]A\n[00:04.00]B\n[00:10.00]C")!, duration: 12)

    @Test func indexAt() {
        #expect(tl.index(at: 1.99) == nil)
        #expect(tl.index(at: 2) == 0)
        #expect(tl.index(at: 3.999) == 0)
        #expect(tl.index(at: 4) == 1)
        #expect(tl.index(at: 100) == 2)
    }

    @Test func progressAndEnd() {
        #expect(tl.end(of: 2) == 12)
        #expect(tl.progress(of: 0, at: 3) == 0.5)
        #expect(tl.progress(of: 2, at: 11) == 0.5)
    }

    @Test func gaps() {
        #expect(tl.isInstrumentalGap(at: 0) == false)
        let g = LyricsTimeline(LRC.parse("[00:20.00]A\n[00:22.00]\n[00:40.00]B")!, duration: nil)
        #expect(g.isInstrumentalGap(at: 5))
        #expect(g.isInstrumentalGap(at: 30))
        #expect(!g.isInstrumentalGap(at: 21))
        #expect(g.nextStart(after: 23) == 40)
    }

    @Test func wordProgress() {
        let w = LyricsTimeline(LRC.parse("[00:01.00]<00:01.00>a <00:02.00>b\n[00:05.00]c")!, duration: nil)
        let p = w.wordProgress(line: 0, at: 1.5)
        #expect(p[0] == 0.5)
        #expect(p[1] == 0)
    }

    @Test func unsyncedHasNoIndex() {
        #expect(LyricsTimeline(.plain("x"), duration: 3).index(at: 1) == nil)
    }
}

@Suite struct LyricsQueryTests {
    @Test func cleaning() {
        let q = LyricsQuery(title: "Song (feat. Y) - Remastered 2011", artist: "A & B, C")
        #expect(q.cleanTitle == "Song")
        #expect(q.primaryArtist == "A")
        #expect(LyricsQuery(title: "(Intro)", artist: "x").cleanTitle == "(Intro)")
    }

    @Test func keyIsNormalised() {
        let a = LyricsQuery(title: "Café!", artist: "BEYONCÉ", duration: 200.4)
        let b = LyricsQuery(title: "cafe", artist: "beyonce", duration: 199.6)
        #expect(a.key == b.key)
    }

    @Test func urls() throws {
        let q = LyricsQuery(title: "A B", artist: "C&D", album: "E", duration: 180.6)
        let u = try #require(LRCLIB.getURL(q)).absoluteString
        #expect(u.hasPrefix("https://lrclib.net/api/get?"))
        #expect(u.contains("duration=181"))
        #expect(u.contains("artist_name=C%26D"))
        #expect(LRCLIB.getURL(LyricsQuery(title: "x", artist: "y")) == nil)
    }

    @Test func bestPrefersSyncedWithinDuration() {
        let q = LyricsQuery(title: "Song", artist: "A", duration: 200)
        let rs = [
            LRCLIBRecord(id: 1, trackName: "Song", duration: 200, plainLyrics: "x"),
            LRCLIBRecord(id: 2, trackName: "Song", duration: 201, syncedLyrics: "[00:01.00]x"),
            LRCLIBRecord(id: 3, trackName: "Song", duration: 230, syncedLyrics: "[00:01.00]x"),
        ]
        #expect(LRCLIB.best(rs, for: q)?.id == 2)
    }

    @Test func recordDecoding() throws {
        let j = #"{"id":7,"trackName":"T","duration":180,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        let r = try #require(LRCLIB.decodeOne(Data(j.utf8)))
        #expect(r.lyrics == .instrumentalTrack)
        #expect(LRCLIB.decodeMany(Data("nope".utf8)).isEmpty)
    }
}

@Suite struct LyricsClockTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func latencyAndOffset() throws {
        let np = MediaNowPlaying(title: "x", isPlaying: true, duration: 300, elapsed: 10, timestamp: t0, playbackRate: 1)
        let c = LyricsClock(np: np, outputLatency: 0.2, offset: 0.1)
        #expect(abs(try #require(c.position(at: t0.addingTimeInterval(1))) - 10.9) < 1e-9)
    }

    @Test func pausedIgnoresLatency() throws {
        let np = MediaNowPlaying(title: "x", isPlaying: false, duration: 300, elapsed: 10, timestamp: t0, playbackRate: 0)
        #expect(LyricsClock(np: np, outputLatency: 0.2).position(at: t0.addingTimeInterval(5)) == 10)
    }

    @Test func offsets() {
        var o = LyricsOffsets()
        o.nudge(key: "k", by: 0.1)
        o.nudge(key: "k", by: 0.1)
        #expect(o.songs["k"] == 0.2)
        o.nudge(key: "k", by: -0.2)
        #expect(o.songs["k"] == nil)
        o.players["p"] = 0.05
        o.nudge(key: "k", by: 99)
        #expect(o.total(key: "k", player: "p") == 5.05)
    }
}

@Suite struct LyricsStyleTests {
    @Test func moodMapping() {
        let rap = LyricsStyle.from(LyricsMood(genre: .rap, energy: 0.9, valence: 0.4))
        #expect(rap.upper && rap.motion == .slam && rap.trans <= 0.16)
        let ballad = LyricsStyle.from(LyricsMood(genre: .ballad, energy: 0.1, valence: 0.3))
        #expect(ballad.face == .serif && ballad.motion == .drift && ballad.trans >= 0.6)
        #expect(LyricsMood(genre: .pop, energy: 3, valence: -1).energy == 1)
    }

    @Test func pulseDetectsBeat() {
        var p = AudioPulse()
        var t = 0.0
        for _ in 0..<200 { p.feed(rms: 0.05, dt: 0.01, now: t); t += 0.01 }
        #expect(p.beat < 0.05)
        for _ in 0..<3 { p.feed(rms: 0.4, dt: 0.01, now: t); t += 0.01 }
        #expect(p.beat > 0.3)
        #expect(p.level > 0.9)
    }

    @Test func settingsDefaultOff() throws {
        #expect(!ShellSettings().lyrics.enabled && !ShellSettings().lyrics.desktop)
        let s = ShellSettings.load(from: Data(#"{"lyrics":{"enabled":true,"desktop":"x"}}"#.utf8))
        #expect(s.lyrics.enabled && !s.lyrics.desktop && !ShellSettings.firstLaunch.lyrics.enabled)
    }
}

@Suite struct LyricsFileTests {
    @Test func parsesWordSync() throws {
        let src = #"""
        version: '1.0'
        metadata:
          title: Adam
          instrumental: false
        lines:
        - text: I'll make a bet
          start_ms: 11040
          end_ms: 14991
          words:
          - text: 'I''ll '
            start_ms: 11040
          - text: 'make '
            start_ms: 11962
          - text: bet
            start_ms: 14122
            end_ms: 14900
        - text: "Second \"line\""
          start_ms: 15010
          end_ms: 19792
        """#
        let l = try #require(LyricsFile.parse(src))
        #expect(l.lines.count == 2)
        #expect(l.lines[0].s == "I'll make a bet")
        #expect(l.lines[0].e == 14.991)
        #expect(l.lines[0].w.map(\.s) == ["I'll ", "make ", "bet"])
        #expect(l.lines[0].w.map(\.t) == [11.04, 11.962, 14.122])
        #expect(l.lines[0].w[2].e == 14.9)
        #expect(l.lines[1].s == "Second \"line\"")
        #expect(l.lines[1].w.isEmpty)
        let tl = LyricsTimeline(l, duration: 108)
        #expect(tl.end(of: 0) == 14.991)
        #expect(!tl.isSung(0, at: 15))
    }

    @Test func instrumentalOnly() {
        #expect(LyricsFile.parse("metadata:\n  instrumental: true\nlines: []") == .instrumentalTrack)
    }
}

@Suite struct AutoSyncTests {
    func run(lag: Double, noise: Bool) -> LyricsAutoSync {
        var src = ""
        var t = 1.0
        var lines = 0
        while t < 60 {
            src += "[" + String(format: "%02d:%05.2f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60)) + "]"
            var ws = ""
            for k in 0..<4 {
                let wt = t + Double(k) * 0.37 + Double(lines % 3) * 0.05
                ws += "<" + String(format: "%02d:%05.2f", Int(wt) / 60, wt.truncatingRemainder(dividingBy: 60)) + ">w\(k) "
            }
            src += ws + "\n"
            t += 2.3
            lines += 1
        }
        let tl = LyricsTimeline(LRC.parse(src)!, duration: 70)
        var s = LyricsAutoSync(timeline: tl)
        let on = Set(s.onsets.map { Int((($0 + lag) / 0.01).rounded()) })
        var g = SystemRandomNumberGenerator()
        var p = 0.0
        while p < 60 {
            let i = Int((p / 0.01).rounded())
            var e = 0.01
            if on.contains(i) { e = 1 }
            if noise, i % 50 == 0 { e = 0.8 }
            if noise { e *= Double.random(in: 0.7...1.3, using: &g) }
            s.feed(energy: e, pos: p, now: p)
            p += 0.01
        }
        return s
    }

    @Test func findsLag() {
        let s = run(lag: 0.12, noise: true)
        #expect(s.locked)
        #expect(abs(s.offset + 0.12) <= 0.02)
    }

    @Test func zeroLag() {
        let s = run(lag: 0, noise: false)
        #expect(s.locked && abs(s.offset) <= 0.02)
    }

    @Test func staysUnlockedOnNoise() {
        let tl = LyricsTimeline(LRC.parse((1...40).map { "[00:\(String(format: "%02d", $0)).00]x" }.joined(separator: "\n"))!, duration: 60)
        var s = LyricsAutoSync(timeline: tl)
        var p = 0.0
        while p < 50 {
            s.feed(energy: Double.random(in: 0.01...1), pos: p, now: p)
            p += 0.01
        }
        #expect(!s.locked)
    }
}

@Suite struct MoodParseTests {
    @Test func parses() throws {
        let m = try #require(LyricsMoodParse.parse("genre=Rap; energy=0.85; valence=0.3; dark=yes"))
        #expect(m.genre == .rap && m.energy == 0.85 && m.valence == 0.3 && m.dark)
        #expect(LyricsMoodParse.parse("genre=indie rock; energy=1.4; valence=0.5; dark=no")?.genre == .rock)
        #expect(LyricsMoodParse.parse("I cannot help") == nil)
    }
}

@Suite struct GenreTests {
    @Test func itunesMapping() {
        #expect(LyricsGenre(itunes: "Hip-Hop/Rap") == .rap)
        #expect(LyricsGenre(itunes: "Alternative") == .rock)
        #expect(LyricsGenre(itunes: "Heavy Metal") == .metal)
        #expect(LyricsGenre(itunes: "Singer/Songwriter") == .acoustic)
        #expect(LyricsGenre(itunes: "K-Pop") == .pop)
        #expect(LyricsGenre(itunes: "Spoken Word") == .other)
    }

    @Test func picksMatchingArtist() {
        let j = #"{"results":[{"artistName":"Neko","primaryGenreName":"Pop"},{"artistName":"Vundabar","primaryGenreName":"Alternative"}]}"#
        #expect(ITunesGenre.pick(Data(j.utf8), for: LyricsQuery(title: "Alien Blues", artist: "Vundabar")) == .rock)
        #expect(ITunesGenre.pick(Data(j.utf8), for: LyricsQuery(title: "x", artist: "Nobody")) == nil)
    }

    @Test func beatEnergy() {
        var b = BeatEnergy()
        #expect(b.energy == nil)
        for k in 0..<20 { b.note(beatAt: Double(k) * 0.5) }
        let e = b.energy!
        #expect(e > 0.5 && e < 0.7)
    }
}

@Suite struct PlayerScriptTests {
    @Test func scriptAndParsing() {
        #expect(PlayerScript.source("com.spotify.client")?.contains("\"Spotify\"") == true)
        #expect(PlayerScript.source("com.google.Chrome") == nil)
        #expect(PlayerScript.position("49,569\n") == 49.569)
        #expect(PlayerScript.position("") == nil)
    }

    @Test func correctionUsesFastestSample() {
        let s = [PlayerScript.Sample(pos: 10, rtt: 0.2, reported: 9.0),
                 PlayerScript.Sample(pos: 20, rtt: 0.05, reported: 19.1),
                 PlayerScript.Sample(pos: 30, rtt: 0.9, reported: 0)]
        #expect(abs(PlayerScript.correction(s)! - 0.9) < 1e-9)
        #expect(PlayerScript.correction([PlayerScript.Sample(pos: 99, rtt: 0.01, reported: 0)]) == nil)
        #expect(PlayerScript.correction([]) == nil)
    }
}

@Suite struct LyricHostileInputTests {
    @Test func hugeAndOddTimesAreDropped() {
        #expect(LRC.time("99999999999999999999:00.00") == nil)
        #expect(LRC.time("9223372036854775807:00") == nil)
        #expect(LRC.time("9999:59.99") == nil)
        #expect(LRC.time("1439:59.99") != nil)
        #expect(LRC.parse("[9999999999999999:00.00]x\n[00:01.00]ok")?.lines.map(\.s) == ["ok"])
    }

    @Test func lyricsfileDropsNonFinite() {
        let src = """
        lines:
        - text: bad
          start_ms: inf
        - text: late
          start_ms: 99999999999999
        - text: fine
          start_ms: 1000
          end_ms: nan
        """
        let l = LyricsFile.parse(src)
        #expect(l?.lines.map(\.s) == ["fine"])
        #expect(l?.lines.first?.e == nil)
    }

    @Test func huge_duration_does_not_trap() {
        let q = LyricsQuery(title: "x", artist: "y", duration: 1e30)
        #expect(!q.key.isEmpty)
        #expect(LRCLIB.getURL(q) != nil)
        #expect(LyricTime.seconds(.nan) == 0)
    }
}
