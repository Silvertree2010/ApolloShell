import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Stage-3 bar modules: text, input sources, volume steps, lenient options")
struct BarModuleTextTests {
    // MARK: Text

    @Test("truncation keeps short text, cuts long text to the limit with an ellipsis")
    func truncation() {
        #expect(BarText.truncated("Hello", maxLength: 8) == "Hello")
        #expect(BarText.truncated("Exactly8", maxLength: 8) == "Exactly8")
        #expect(BarText.truncated("Bohemian Rhapsody", maxLength: 10) == "Bohemian…")
        #expect(BarText.truncated("Bohemian Rhapsody", maxLength: 10).count == 9)
        #expect(BarText.truncated("abcdefghij", maxLength: 5) == "abcd…")
        // A family emoji is one character and is never split.
        #expect(BarText.truncated("👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦", maxLength: 2) == "👨‍👩‍👧‍👦…")
    }

    @Test("lengths are clamped to the range", arguments: [(0, 8), (8, 8), (30, 30), (80, 80), (10_000, 80), (-5, 8)])
    func clampedLength(raw: Int, expected: Int) {
        #expect(BarText.clampedLength(raw) == expected)
    }

    @Test("now playing line: title and artist, either alone, nothing")
    func nowPlayingLine() {
        #expect(BarText.nowPlaying(title: "Song", artist: "Band") == "Song · Band")
        #expect(BarText.nowPlaying(title: "Song", artist: nil) == "Song")
        #expect(BarText.nowPlaying(title: " Song ", artist: "  ") == "Song")
        #expect(BarText.nowPlaying(title: "", artist: "Band") == "Band")
        #expect(BarText.nowPlaying(title: "", artist: nil) == "")
    }

    @Test("window line: title beside an icon, app first without one, app alone for empty or repeated titles")
    func windowLine() {
        #expect(BarText.windowLine(app: "Safari", title: "Apple", withIcon: true) == "Apple")
        #expect(BarText.windowLine(app: "Safari", title: "Apple", withIcon: false) == "Safari · Apple")
        #expect(BarText.windowLine(app: "Finder", title: "Finder", withIcon: false) == "Finder")
        #expect(BarText.windowLine(app: "Finder", title: "  ", withIcon: true) == "Finder")
        #expect(BarText.windowLine(app: "Finder", title: nil, withIcon: true) == "Finder")
    }

    @Test("percent and memory share")
    func percent() {
        #expect(BarText.percent(nil) == "–")
        #expect(BarText.percent(0.234) == "23%")
        #expect(BarText.percent(1.7) == "100%")
        #expect(BarText.percent(.nan) == "–")
        #expect(BarText.fraction(used: 8, total: 16) == 0.5)
        #expect(BarText.fraction(used: 8, total: 0) == nil)
        #expect(BarText.fraction(used: 20, total: 16) == 1)
    }

    // MARK: Input sources

    @Test("the next source wraps around; unknown current gives the first; alone gives nothing")
    func nextSource() {
        let ids = ["a", "b", "c"]
        #expect(InputSourceCycle.next(after: "a", in: ids) == "b")
        #expect(InputSourceCycle.next(after: "c", in: ids) == "a")
        #expect(InputSourceCycle.next(after: "x", in: ids) == "a")
        #expect(InputSourceCycle.next(after: nil, in: ids) == "a")
        #expect(InputSourceCycle.next(after: "a", in: ["a"]) == nil)
        #expect(InputSourceCycle.next(after: "a", in: []) == nil)
    }

    @Test("short names: language in capitals, numbered when they repeat, name letters without a language")
    func abbreviations() {
        let sources = [
            InputSourceInfo(id: "com.apple.keylayout.SwissGerman", name: "Swiss German", languages: ["de"]),
            InputSourceInfo(id: "com.apple.keylayout.US", name: "U.S.", languages: ["en"]),
            InputSourceInfo(id: "com.apple.keylayout.ABC", name: "ABC", languages: ["en-US"]),
            InputSourceInfo(id: "com.apple.inputmethod.SCIM", name: "Pinyin", languages: ["zh-Hans"]),
            InputSourceInfo(id: "x.custom", name: "my layout", languages: []),
            InputSourceInfo(id: "x.empty", name: "…", languages: [""]),
        ]
        #expect(InputSourceCycle.abbreviations(for: sources) == ["DE", "EN", "EN2", "ZH", "MY", "?"])
    }

    // MARK: Volume

    @Test("volume steps land on the 5 % grid and stay within 0...1", arguments: [
        (Float(0.50), 1, Float(0.55)), (0.52, 1, 0.55), (0.52, -1, 0.50), (0.55, -1, 0.50), (0.55, 1, 0.60),
        (0.98, 1, 1.0), (1.0, 1, 1.0), (0.02, -1, 0.0), (0.0, -1, 0.0), (0.3, 3, 0.45), (0.3, 0, 0.3),
    ])
    func volumeSteps(start: Float, steps: Int, expected: Float) {
        #expect(abs(VolumeStep.stepped(start, by: steps) - expected) < 0.0001)
    }

    @Test("a wheel notch is one step, trackpad deltas add up, direction follows natural scrolling")
    func scrollStepper() {
        var wheel = ScrollStepper()
        #expect(wheel.steps(delta: 3, precise: false, inverted: false) == 1)
        #expect(wheel.steps(delta: -0.1, precise: false, inverted: false) == -1)
        #expect(wheel.steps(delta: 1, precise: false, inverted: true) == -1)
        #expect(wheel.steps(delta: 0, precise: false, inverted: false) == 0)

        var pad = ScrollStepper(threshold: 10)
        #expect(pad.steps(delta: 4, precise: true, inverted: false) == 0)
        #expect(pad.steps(delta: 4, precise: true, inverted: false) == 0)
        #expect(pad.steps(delta: 4, precise: true, inverted: false) == 1)
        #expect(pad.steps(delta: 25, precise: true, inverted: false) == 2)
        // Turning back throws away what gathered upwards (here 7).
        #expect(pad.steps(delta: -6, precise: true, inverted: false) == 0)
        #expect(pad.steps(delta: -6, precise: true, inverted: false) == -1)
        // Natural scrolling: fingers pushing up arrive as negative deltas.
        var natural = ScrollStepper(threshold: 10)
        #expect(natural.steps(delta: -12, precise: true, inverted: true) == 1)
    }

    // MARK: Options

    @Test("new options read leniently and clamp their lengths")
    func lenientOptions() throws {
        func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        let playing: BarNowPlayingOptions = try decode(#"{"maxLength": 5000, "showControls": "yes"}"#)
        #expect(playing == BarNowPlayingOptions(maxLength: 80, showControls: true))
        let title: BarWindowTitleOptions = try decode(#"{"showTitle": false, "maxLength": 2}"#)
        #expect(title == BarWindowTitleOptions(showIcon: true, showTitle: false, maxLength: 8))
        let volume: BarVolumeOptions = try decode(#"{"showDevice": true, "future": 1}"#)
        #expect(volume == BarVolumeOptions(showPercent: true, showDevice: true))
        let keyboard: BarKeyboardLayoutOptions = try decode(#"{"showIcon": 7}"#)
        #expect(keyboard == BarKeyboardLayoutOptions())
        let stats: BarSystemStatsOptions = try decode(#"{"showCPU": false, "showMemory": false}"#)
        #expect(stats.shownCPU && !stats.showMemory)
        var set = BarNowPlayingOptions()
        set.maxLength = 1
        #expect(set.maxLength == 8)
    }

    @Test("a bar written with the new kinds reads back the same")
    func roundTrip() throws {
        let layout = BarLayout([
            BarEntry(module: .nowPlaying(.init(maxLength: 20, showControls: false))),
            BarEntry(module: .windowTitle(.init(showIcon: false))), BarEntry(.keyboardLayout),
            BarEntry(module: .volume(.init(showDevice: true))), BarEntry(.wifi), BarEntry(.bluetooth),
            BarEntry(module: .systemStats(.init(showMemory: false))),
        ])
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(BarLayout.self, from: data) == layout)
        // Raw values are the file format: pinned here so a rename shows up.
        #expect(layout.entries.map(\.kind.rawValue) == ["nowPlaying", "windowTitle", "keyboardLayout", "volume",
                                                        "wifi", "bluetooth", "systemStats"])
    }
}
