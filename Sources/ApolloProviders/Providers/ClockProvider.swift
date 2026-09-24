import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class ClockProvider: BaseProvider {
    private static let slack = 0.01
    private let source: any ClockSource
    public private(set) var firstWeekday = "system"

    public init(source: any ClockSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("clock"), clock: clock)
    }

    override func didStart() {
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    override func didChangeDemand() {
        refresh()
    }

    override func didStop() {
        source.stopObserving()
    }

    override func didConfigure(_ settings: Record) {
        if case .string(let value) = settings["first-weekday"] ?? .null {
            firstWeekday = value
        }
    }

    private func refresh() {
        guard isRunning else { return }
        let now = source.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = source.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: now)
        publish("now", .date(now))
        publish("hour", ProviderValue.number(parts.hour))
        publish("minute", ProviderValue.number(parts.minute))
        publish("second", ProviderValue.number(parts.second))
        publish("day", ProviderValue.number(parts.day))
        publish("month", ProviderValue.number(parts.month))
        publish("year", ProviderValue.number(parts.year))
        publish("weekday", ProviderValue.number(parts.weekday.map { ($0 + 5) % 7 + 1 }))
        publish("time-zone", .string(source.timeZone.identifier))
        scheduleNext(after: now, calendar: calendar)
    }

    private func scheduleNext(after now: Date, calendar: Calendar) {
        let next: Date
        if demand.wants("second") {
            next = calendar.dateInterval(of: .second, for: now)?.end ?? now.addingTimeInterval(1)
        } else {
            next = BarClock.nextMinute(after: now, calendar: calendar)
        }
        timers.once("tick", after: next.timeIntervalSince(now) + Self.slack) { [weak self] in
            self?.refresh()
        }
    }
}
