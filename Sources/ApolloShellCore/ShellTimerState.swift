import Foundation

public struct ShellTimerState: Equatable, Sendable {
    public enum Mode: String, Sendable, CaseIterable {
        case standard, stopwatch, pomodoro
    }

    public enum Phase: String, Equatable, Sendable {
        case focus
        case shortBreak = "short-break"
        case longBreak = "long-break"
    }

    public static let focusLength: TimeInterval = 25 * 60
    public static let shortBreakLength: TimeInterval = 5 * 60
    public static let longBreakLength: TimeInterval = 15 * 60
    public static let defaultLength: TimeInterval = 10 * 60
    public static let minutesRange: ClosedRange<Double> = 1...600

    public private(set) var mode: Mode = .standard
    public private(set) var length: TimeInterval = defaultLength
    public private(set) var runningSince: Date?
    public private(set) var banked: TimeInterval = 0
    public private(set) var phase: Phase = .focus
    public private(set) var focusCount = 0

    public init() {}

    public var isRunning: Bool { runningSince != nil }

    public var isIdle: Bool { runningSince == nil && banked == 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public var target: TimeInterval? {
        switch mode {
        case .standard: length
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

    public func progress(at now: Date) -> Double {
        guard let target, target > 0 else { return elapsed(at: now).truncatingRemainder(dividingBy: 60) / 60 }
        return min(elapsed(at: now) / target, 1)
    }

    public func isFinished(at now: Date) -> Bool {
        guard let remaining = remaining(at: now) else { return false }
        return isRunning && remaining <= 0
    }

    public var round: Int {
        switch phase {
        case .focus: focusCount % 4 + 1
        case .shortBreak, .longBreak: (focusCount - 1) % 4 + 1
        }
    }

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

    public static func text(_ seconds: TimeInterval, countingDown: Bool) -> String {
        let total = max(0, Int(countingDown ? seconds.rounded(.up) : seconds.rounded(.down)))
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        let s = secs < 10 ? "0\(secs)" : "\(secs)"
        if hours > 0 { return "\(hours):\(minutes < 10 ? "0" : "")\(minutes):\(s)" }
        return "\(minutes):\(s)"
    }
}
