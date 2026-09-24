import Foundation
import ApolloRuntime
@testable import ApolloProviders

@MainActor
final class FakeClockSource: ClockSource {
    let clock: ManualRuntimeClock
    var base: Date
    var timeZone: TimeZone
    var reads = 0
    var observing = false
    private var handler: (@MainActor () -> Void)?

    init(clock: ManualRuntimeClock, base: String, timeZone: String = "Europe/Zurich") {
        self.clock = clock
        self.base = ISO8601DateFormatter().date(from: base)!
        self.timeZone = TimeZone(identifier: timeZone)!
    }

    var now: Date {
        reads += 1
        return base.addingTimeInterval(clock.now)
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func changeTimeZone(_ identifier: String) {
        timeZone = TimeZone(identifier: identifier)!
        handler?()
    }
}
