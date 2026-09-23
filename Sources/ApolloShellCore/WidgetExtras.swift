import Foundation

// The pure logic behind the widgets of 09/23 (timer, sun and moon,
// clipboard): no clock, no pasteboard, no system - the app feeds them.

// MARK: - Timer

/// Timer, stopwatch and pomodoro in one state. Time is not counted up in
/// steps but worked out from `runningSince`, so a closed dashboard (nothing
/// draws, nothing ticks) loses no second.
public struct ShellTimerState: Equatable, Sendable {
    public enum Mode: String, Sendable, CaseIterable { case timer, stopwatch, pomodoro }
    public enum Phase: Equatable, Sendable { case focus, shortBreak, longBreak }

    public static let focusLength: TimeInterval = 25 * 60
    public static let shortBreakLength: TimeInterval = 5 * 60
    public static let longBreakLength: TimeInterval = 15 * 60

    public private(set) var mode: Mode = .timer
    /// Length of the timer (the pomodoro phases have their own).
    public private(set) var length: TimeInterval = 10 * 60
    public private(set) var runningSince: Date?
    /// Time run before the last pause.
    public private(set) var banked: TimeInterval = 0
    public private(set) var phase: Phase = .focus
    /// Finished focus phases - every fourth break is a long one.
    public private(set) var focusCount = 0

    public init() {}

    public var isRunning: Bool { runningSince != nil }
    /// Neither running nor run: the start value is shown.
    public var isIdle: Bool { runningSince == nil && banked == 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// The length that counts down right now; `nil` for the stopwatch.
    public var target: TimeInterval? {
        switch mode {
        case .timer: length
        case .stopwatch: nil
        case .pomodoro:
            switch phase {
            case .focus: Self.focusLength
            case .shortBreak: Self.shortBreakLength
            case .longBreak: Self.longBreakLength
            }
        }
    }

    public func remaining(at now: Date) -> TimeInterval? {
        target.map { max(0, $0 - elapsed(at: now)) }
    }

    /// 0...1 of the target, for rings and bars; the stopwatch goes round once a minute.
    public func progress(at now: Date) -> Double {
        guard let target, target > 0 else { return elapsed(at: now).truncatingRemainder(dividingBy: 60) / 60 }
        return min(elapsed(at: now) / target, 1)
    }

    public func isFinished(at now: Date) -> Bool {
        guard let remaining = remaining(at: now) else { return false }
        return isRunning && remaining <= 0
    }

    /// Another mode or length starts over.
    public mutating func set(mode: Mode, length: TimeInterval? = nil) {
        self = ShellTimerState()
        self.mode = mode
        if let length { self.length = max(1, length) }
    }

    public mutating func start(at now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(at now: Date) {
        guard let since = runningSince else { return }
        banked += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func reset() {
        runningSince = nil
        banked = 0
    }

    /// The target is reached: the timer stops at zero, the pomodoro goes on
    /// with the next phase (not started - a break begins when you want it).
    public mutating func finish() {
        runningSince = nil
        banked = 0
        guard mode == .pomodoro else { return }
        if phase == .focus {
            focusCount += 1
            phase = focusCount % 4 == 0 ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
    }

    /// "4:05", "1:02:03"; seconds rounded up while counting down, so the
    /// display reaches 0:00 only at the end.
    public static func text(_ seconds: TimeInterval, countingDown: Bool) -> String {
        let total = max(0, Int(countingDown ? seconds.rounded(.up) : seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        let s = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 { return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(s)" }
        return "\(minutes):\(s)"
    }
}

// MARK: - Sun and moon

/// Sunrise and sunset by the sunrise equation (NOAA's simplification, a
/// minute or two off - enough for a widget), and the moon's phase from the
/// mean synodic month. Computed, not fetched.
public enum SunMoon {
    public struct Day: Equatable, Sendable {
        /// `nil` in polar day or night.
        public var sunrise: Date?
        public var sunset: Date?
        public var noon: Date
        /// Sun above the horizon the whole day (and there is no sunrise).
        public var alwaysUp: Bool
    }

    private static let unixJulian = 2_440_587.5
    private static let j2000 = 2_451_545.0

    private static func julian(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + unixJulian }
    private static func moment(julian: Double) -> Date { Date(timeIntervalSince1970: (julian - unixJulian) * 86_400) }
    private static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func deg(_ radians: Double) -> Double { radians * 180 / .pi }

    /// The day that contains `date`, at `latitude`/`longitude` (east positive).
    public static func day(_ date: Date, latitude: Double, longitude: Double) -> Day {
        let n = (julian(date) - j2000 + 0.0008 - longitude / 360).rounded()
        let meanNoon = n - longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let m = rad(anomaly)
        let center = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let lambda = rad((anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360))
        let transit = j2000 + meanNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * lambda)
        let declination = asin(sin(lambda) * sin(rad(23.4397)))
        let phi = rad(latitude)
        let cosHour = (sin(rad(-0.833)) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        let noon = moment(julian: transit)
        guard cosHour >= -1, cosHour <= 1 else {
            return Day(sunrise: nil, sunset: nil, noon: noon, alwaysUp: cosHour < -1)
        }
        let hour = deg(acos(cosHour)) / 360
        return Day(sunrise: moment(julian: transit - hour), sunset: moment(julian: transit + hour), noon: noon, alwaysUp: false)
    }

    public static let synodicMonth = 29.530588853
    /// A new moon: 6 Jan 2000, 18:14 UTC.
    private static let knownNewMoon = 2_451_550.26

    /// 0 new moon, 0.25 first quarter, 0.5 full, 0.75 last quarter.
    public static func moonPhase(_ date: Date) -> Double {
        let cycles = (julian(date) - knownNewMoon) / synodicMonth
        let phase = cycles - cycles.rounded(.down)
        return phase
    }

    /// Lit part of the disc, 0...1.
    public static func illumination(phase: Double) -> Double { (1 - cos(2 * .pi * phase)) / 2 }

    /// SF Symbol of the phase (eight steps, as Apple names them).
    public static func moonSymbol(phase: Double) -> String {
        let names = ["moonphase.new.moon", "moonphase.waxing.crescent", "moonphase.first.quarter",
                     "moonphase.waxing.gibbous", "moonphase.full.moon", "moonphase.waning.gibbous",
                     "moonphase.last.quarter", "moonphase.waning.crescent"]
        return names[Int((phase * 8).rounded()) % 8]
    }

    public static func moonName(phase: Double) -> String {
        switch Int((phase * 8).rounded()) % 8 {
        case 0: String(localized: "New Moon")
        case 1: String(localized: "Waxing Crescent")
        case 2: String(localized: "First Quarter")
        case 3: String(localized: "Waxing Gibbous")
        case 4: String(localized: "Full Moon")
        case 5: String(localized: "Waning Gibbous")
        case 6: String(localized: "Last Quarter")
        default: String(localized: "Waning Crescent")
        }
    }
}

// MARK: - Clipboard

/// What the clipboard history keeps: text only, never what a password
/// manager marks as secret or passing (the nspasteboard.org conventions,
/// which 1Password, Bitwarden, KeePassXC and Apple's Passwords follow), at
/// most `limit` entries, the newest first, in memory only.
public struct ClipboardList: Equatable, Sendable {
    public static let limit = 20
    /// Longer text is kept, but only this much of it.
    public static let maxLength = 10_000

    /// Types that mean: do not remember this.
    public static let skippedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
    ]

    public private(set) var items: [String] = []

    public init() {}

    public static func records(types: [String]) -> Bool {
        !types.contains(where: skippedTypes.contains)
    }

    /// Adds a copied text; one already in the list moves to the top.
    public mutating func add(_ text: String) {
        let clipped = String(text.prefix(Self.maxLength))
        guard !clipped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == clipped }
        items.insert(clipped, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func remove(_ text: String) {
        items.removeAll { $0 == text }
    }

    public mutating func clear() {
        items.removeAll()
    }

    /// One line for the list: whitespace runs collapsed.
    public static func preview(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
