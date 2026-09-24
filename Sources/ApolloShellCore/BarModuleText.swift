import Foundation

// The pure parts of the stage-3 bar modules (now playing, window title,
// input source, volume, system stats): what text they show and how a click
// or a scroll turns into a value. Kept out of the views so the rules can be
// tested without a screen, CoreAudio or the text input system.

// MARK: - Text

public enum BarText {
    /// How long a text in a bar may grow, in characters. Below 8 even a
    /// short title is only an ellipsis; above 80 one block would push every
    /// other one out of the menu bar.
    public static let lengthRange: ClosedRange<Int> = 8...80

    public static func clampedLength(_ value: Int) -> Int {
        min(max(value, lengthRange.lowerBound), lengthRange.upperBound)
    }

    /// At most `maxLength` characters, the ellipsis included, cut at a whole
    /// character (an emoji or an accented letter never breaks in two) and
    /// without a space dangling before the ellipsis. Cut by count instead of
    /// letting SwiftUI truncate: a bar gives its blocks their ideal width, so
    /// a long title would otherwise take all of it.
    public static func truncated(_ text: String, maxLength: Int) -> String {
        let limit = max(maxLength, 1)
        guard text.count > limit else { return text }
        let kept = text.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return kept + "…"
    }

    /// "Title · Artist", like the menu bar extras of music apps; just the
    /// title when there is no artist (a web video, a podcast without one).
    public static func nowPlaying(title: String, artist: String?) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (title.isEmpty, artist.isEmpty) {
        case (false, false): return "\(title) · \(artist)"
        case (false, true): return title
        case (true, false): return artist
        case (true, true): return ""
        }
    }

    /// The window title block's line. With the app's icon beside it the
    /// title alone says enough (the icon names the app); without the icon
    /// the app's name leads. A title that is empty or just repeats the app's
    /// name (Finder windows without a folder, most settings windows) falls
    /// back to the name alone.
    public static func windowLine(app: String, title: String?, withIcon: Bool) -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, title != app else { return app }
        return withIcon ? title : "\(app) · \(title)"
    }

    /// Whole percent for the stats blocks, "–" before the first reading.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "–" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// Used memory as a share of all of it; `nil` when there is nothing to
    /// divide by.
    public static func fraction(used: UInt64, total: UInt64) -> Double? {
        guard total > 0 else { return nil }
        return min(Double(used) / Double(total), 1)
    }
}

// MARK: - Input sources

/// One keyboard input source as the text input system reports it.
public struct InputSourceInfo: Equatable, Sendable {
    public var id: String
    public var name: String
    /// BCP 47 codes, most important first ("de", "en", "zh-Hans").
    public var languages: [String]

    public init(id: String, name: String, languages: [String]) {
        self.id = id
        self.name = name
        self.languages = languages
    }
}

public enum InputSourceCycle {
    /// The source a click switches to: the one after the current, wrapping
    /// around at the end. The first one when the current is not in the list
    /// (an input method's own mode, a palette); `nil` when there is nothing
    /// else to switch to.
    public static func next(after current: String?, in ids: [String]) -> String? {
        guard let first = ids.first else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return first }
        let next = ids[(index + 1) % ids.count]
        return next == current ? nil : next
    }

    /// The short name drawn in the bar: the primary language in capitals
    /// ("DE", "EN"), like the letters macOS shows for layouts without a flag.
    /// Two sources of the same language (U.S. and ABC, German and Swiss
    /// German) would read the same, so later ones get a number ("EN2"); the
    /// tooltip carries the full name. Without a language: the first two
    /// letters of the name.
    public static func abbreviations(for sources: [InputSourceInfo]) -> [String] {
        var seen: [String: Int] = [:]
        return sources.map { source in
            let base = abbreviation(source)
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            return count == 1 ? base : "\(base)\(count)"
        }
    }

    static func abbreviation(_ source: InputSourceInfo) -> String {
        if let language = source.languages.first,
           let primary = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first,
           !primary.isEmpty {
            return String(primary.prefix(3)).uppercased()
        }
        let letters = source.name.filter { $0.isLetter || $0.isNumber }
        return letters.isEmpty ? "?" : String(letters.prefix(2)).uppercased()
    }
}

// MARK: - Volume

public enum VolumeStep {
    /// 5 % a step, like the spec's "scroll = ±5 %" (Apple's volume keys
    /// step by 1/16, which does not land on round numbers).
    public static let step: Float = 0.05

    /// `steps` steps up (positive) or down, landing on the grid: from 52 %
    /// one up is 55 %, not 57 % - otherwise an odd value set elsewhere would
    /// stay odd forever. Clamped to 0...1.
    public static func stepped(_ volume: Float, by steps: Int, step: Float = step) -> Float {
        guard steps != 0, step > 0 else { return min(max(volume, 0), 1) }
        let position = volume / step
        // A hair of tolerance: 0.55 / 0.05 is 10.999... in Float.
        let base = steps > 0 ? (position + 0.001).rounded(.down) : (position - 0.001).rounded(.up)
        let target = (base + Float(steps)) * step
        return min(max(target, 0), 1)
    }
}

/// Turns scroll events into whole volume steps.
///
/// A mouse wheel sends one event per notch - one step each. A trackpad
/// (precise deltas) sends a stream of small ones; they add up until a
/// step's worth has come together, so a slow swipe does not jump by one
/// step per event. A change of direction starts the sum over, the way a
/// swipe that turns back should not first have to undo what it gathered.
public struct ScrollStepper: Sendable {
    /// Points of trackpad travel per step.
    public var threshold: Double
    private var accumulated = 0.0

    public init(threshold: Double = 14) {
        self.threshold = threshold
    }

    /// `delta` is the event's vertical delta; `inverted` whether "natural"
    /// scrolling flipped it. Up - the wheel away from you, two fingers
    /// pushed up - is louder either way.
    public mutating func steps(delta: Double, precise: Bool, inverted: Bool) -> Int {
        let up = inverted ? -delta : delta
        guard up != 0, up.isFinite else { return 0 }
        guard precise else {
            accumulated = 0
            return up > 0 ? 1 : -1
        }
        if accumulated != 0, (accumulated > 0) != (up > 0) { accumulated = 0 }
        accumulated += up
        let whole = Int(accumulated / threshold)
        accumulated -= Double(whole) * threshold
        return whole
    }
}
