import AppKit
import ApolloProviders

@MainActor
final class SystemClockSource: ClockSource {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var now: Date { Date() }

    var timeZone: TimeZone { TimeZone.current }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        let names: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSSystemTimeZoneDidChange),
            (.default, .NSSystemClockDidChange),
            (.default, .NSCalendarDayChanged),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    NSTimeZone.resetSystemTimeZone()
                    handler()
                }
            }
            observers.append((center, token))
        }
    }

    func stopObserving() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
