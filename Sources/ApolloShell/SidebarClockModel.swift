import AppKit
import ApolloShellCore
import Observation

/// Uhrzeit fuer die Uhr in der Leiste.
///
/// Caelestia zeigt dort keine Sekunden; ein Sekundentakt waere 59 von 60 Mal
/// umsonst. Also genau zur vollen Minute weiterschalten, und zwar jedes Mal
/// neu bis zur naechsten Minute gerechnet statt einmal ausgerichtet und
/// dann alle 60 s: so kann die Uhr nicht davonlaufen.
@MainActor
@Observable
final class SidebarClockModel {
    private(set) var now: Date

    /// Knapp nach der Minutengrenze feuern, nie knapp davor (sonst stuende
    /// noch die alte Minute da und der naechste Takt kaeme erst in 60 s).
    private static let slack: TimeInterval = 0.05

    @ObservationIgnored private var timer: Timer?

    init() {
        now = Date()
        scheduleTick()
        observeSystemChanges()
    }

    /// Fuer die Bildprobe: feste Zeit, kein Timer.
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
        // .common: auch waehrend ein Menue offen ist, sonst bliebe die Minute
        // stehen, bis es zu ist.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Im Ruhezustand laeuft der Timer nicht weiter (er zaehlt Wachzeit);
    /// nach dem Aufwachen, nach Uhr stellen und Zeitzonenwechsel neu
    /// ausrichten. Die Beobachter leben so lange wie der Prozess.
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
