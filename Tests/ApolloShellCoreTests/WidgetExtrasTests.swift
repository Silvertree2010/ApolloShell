import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Timer, sun and moon, clipboard")
struct WidgetExtrasTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The timer counts from its start, pauses keep what ran")
    func timer() {
        var state = ShellTimerState()
        state.set(mode: .timer, length: 300)
        #expect(state.isIdle)
        state.start(at: t0)
        #expect(state.remaining(at: t0.addingTimeInterval(100)) == 200)
        state.pause(at: t0.addingTimeInterval(100))
        #expect(state.remaining(at: t0.addingTimeInterval(1000)) == 200)
        state.start(at: t0.addingTimeInterval(1000))
        #expect(!state.isFinished(at: t0.addingTimeInterval(1199)))
        #expect(state.isFinished(at: t0.addingTimeInterval(1200)))
        state.finish()
        #expect(state.isIdle && state.mode == .timer)
    }

    @Test("Pomodoro: focus, short break, and every fourth break a long one")
    func pomodoro() {
        var state = ShellTimerState()
        state.set(mode: .pomodoro)
        var phases: [ShellTimerState.Phase] = []
        for _ in 0..<8 {
            state.finish()
            phases.append(state.phase)
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(state.target == ShellTimerState.focusLength)
    }

    @Test("Stopwatch has no end", arguments: [0.0, 59, 3_700])
    func stopwatch(seconds: Double) {
        var state = ShellTimerState()
        state.set(mode: .stopwatch)
        state.start(at: t0)
        #expect(state.remaining(at: t0.addingTimeInterval(seconds)) == nil)
        #expect(!state.isFinished(at: t0.addingTimeInterval(seconds)))
    }

    @Test("Time text", arguments: [
        (0.0, true, "0:00"), (0.2, true, "0:01"), (65, false, "1:05"), (3_723, false, "1:02:03"), (599.5, true, "10:00"),
    ])
    func text(seconds: Double, down: Bool, expected: String) {
        #expect(ShellTimerState.text(seconds, countingDown: down) == expected)
    }

    @Test("Sunrise and sunset in Berlin at midsummer: 04:43 and 21:33 CEST, within 3 minutes")
    func berlin() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12)))
        let sun = SunMoon.day(day, latitude: 52.52, longitude: 13.405)
        let rise = try #require(sun.sunrise), set = try #require(sun.sunset)
        let expectedRise = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 4, minute: 43)))
        let expectedSet = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 21, minute: 33)))
        #expect(abs(rise.timeIntervalSince(expectedRise)) < 180)
        #expect(abs(set.timeIntervalSince(expectedSet)) < 180)
    }

    @Test("Polar day in Tromsø at midsummer: no sunrise, always up")
    func polar() throws {
        let day = try #require(ISO8601DateFormatter().date(from: "2026-06-21T10:00:00Z"))
        let sun = SunMoon.day(day, latitude: 69.65, longitude: 18.96)
        #expect(sun.sunrise == nil && sun.alwaysUp)
    }

    @Test("Moon phase at known new and full moons (2024)")
    func moon() throws {
        let formatter = ISO8601DateFormatter()
        let new = SunMoon.moonPhase(try #require(formatter.date(from: "2024-01-11T11:57:00Z")))
        let full = SunMoon.moonPhase(try #require(formatter.date(from: "2024-01-25T17:54:00Z")))
        #expect(new < 0.02 || new > 0.98)
        #expect(abs(full - 0.5) < 0.03)
        #expect(SunMoon.moonSymbol(phase: full) == "moonphase.full.moon")
        #expect(SunMoon.illumination(phase: 0.5) == 1)
    }

    @Test("Clipboard: newest first, no duplicates, at most 20, secrets never")
    func clipboard() {
        var list = ClipboardList()
        list.add("a")
        list.add("b")
        list.add("a")
        list.add("   ")
        #expect(list.items == ["a", "b"])
        for index in 0..<30 { list.add("x\(index)") }
        #expect(list.items.count == ClipboardList.limit && list.items.first == "x29")
        #expect(!ClipboardList.records(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardList.records(types: ["public.utf8-plain-text"]))
        #expect(ClipboardList.preview("a\n  b\tc") == "a b c")
    }
}
