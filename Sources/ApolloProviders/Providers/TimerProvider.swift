import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class TimerProvider: BaseProvider {
    static let alarmCheck: Double = 30

    private let now: @MainActor () -> Date
    public private(set) var state = ShellTimerState()
    private var alarm: ScheduledWork?

    public init(clock: any RuntimeClock, now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
        super.init(schema: BuiltinProviderSchemas.schema("timer"), clock: clock)
    }

    override func didStart() {
        checkFinished()
        publishAll()
        scheduleAlarm()
    }

    override func didChangeDemand() {
        scheduleTick()
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        let date = now()
        switch arguments.action {
        case "timer.start":
            if !arguments.values.isEmpty, arguments.values[0] != .null {
                let minutes = try arguments.number(0, range: ShellTimerState.minutesRange)
                state.set(mode: .standard, length: minutes * 60)
            }
            state.start(at: date)
        case "timer.pause":
            state.pause(at: date)
        case "timer.resume":
            state.start(at: date)
        case "timer.reset":
            state.reset()
        case "timer.set-mode":
            let text = try arguments.string(0)
            guard let mode = ShellTimerState.Mode(rawValue: text) else {
                throw ProviderActionError.invalidArgument(action: arguments.action, message: "unknown mode \"\(text)\", expected standard, stopwatch or pomodoro")
            }
            var minutes: Double?
            if arguments.values.count > 1, arguments.values[1] != .null {
                minutes = try arguments.number(1, range: ShellTimerState.minutesRange)
            }
            setMode(mode, minutes: minutes)
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        changed()
        return .null
    }

    private func setMode(_ mode: ShellTimerState.Mode, minutes: Double?) {
        if mode == state.mode {
            guard state.isIdle, mode == .standard, let minutes, state.length != minutes * 60 else { return }
        }
        state.set(mode: mode, length: minutes.map { $0 * 60 })
    }

    private func changed() {
        publishAll()
        scheduleAlarm()
        scheduleTick()
    }

    private func publishAll() {
        guard isRunning else { return }
        let date = now()
        publish("mode", .string(state.mode.rawValue))
        publish("running", .bool(state.isRunning))
        publish("duration", ProviderValue.number(state.target))
        publish("phase", .string(state.phase.rawValue))
        publish("round", .number(Double(state.round)))
        publishTime(date)
    }

    private func publishTime(_ date: Date) {
        publish("elapsed", .number(state.elapsed(at: date)))
        publish("remaining", ProviderValue.number(state.remaining(at: date)))
    }

    private func scheduleTick() {
        guard isRunning, state.isRunning, demand.wantsAny(["elapsed", "remaining"]) else {
            timers.cancel("tick")
            return
        }
        let elapsed = state.elapsed(at: now())
        let step = 1 - elapsed.truncatingRemainder(dividingBy: 1)
        timers.once("tick", after: step < 0.01 ? 1 : step) { [weak self] in
            guard let self else { return }
            self.publishTime(self.now())
            self.scheduleTick()
        }
    }

    private func scheduleAlarm() {
        alarm?.cancel()
        alarm = nil
        guard state.isRunning, let remaining = state.remaining(at: now()) else { return }
        alarm = clock.schedule(after: min(max(remaining, 0.05), Self.alarmCheck)) { [weak self] in
            self?.alarmFired()
        }
    }

    private func alarmFired() {
        alarm = nil
        if !checkFinished() { scheduleAlarm() }
    }

    @discardableResult
    private func checkFinished() -> Bool {
        guard state.isFinished(at: now()) else { return false }
        let finished = state
        state.finish()
        changed()
        emit("timer.finished", Record([
            ("mode", .string(finished.mode.rawValue)),
            ("phase", .string(finished.phase.rawValue)),
            ("duration", ProviderValue.number(finished.target)),
        ]))
        return true
    }
}
