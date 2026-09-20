import AppKit
import ApolloShellCore
import Observation

/// The time for the clock in the bar.
///
/// Caelestia shows no seconds there; a beat every second would be wasted 59
/// times out of 60. So it moves on exactly at the full minute, and the time to
/// the next minute is worked out anew every time instead of being lined up
/// once and then every 60 s: that way the clock cannot run away.
@MainActor
@Observable
final class SidebarClockModel {
    private(set) var now: Date

    /// Fire just after the minute boundary, never just before it (otherwise the
    /// old minute would still stand there and the next beat would only come in 60 s).
    private static let slack: TimeInterval = 0.05

    @ObservationIgnored private var timer: Timer?

    init() {
        now = Date()
        scheduleTick()
        observeSystemChanges()
    }

    /// For the image sample: a fixed time, no timer.
    init(preview date: Date) {
        now = date
    }

    private func scheduleTick() {
        timer?.invalidate()
        let current = Date()
        now = current
        let next = BarClock.nextMinute(after: current, calendar: .current)
        let timer = Timer(timeInterval: next.timeIntervalSince(current) + Self.slack, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleTick() }
        }
        // .common: while a menu is open too, otherwise the minute would stand
        // still until it closes.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// In sleep the timer does not go on running (it counts waking time); line
    /// it up anew after the wake-up, after setting the clock and after a time
    /// zone change. The observers live as long as the process.
    private func observeSystemChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleTick() }
        }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleTick() }
            }
        }
    }
}
