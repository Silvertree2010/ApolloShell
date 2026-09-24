import Foundation
import ApolloShellCore
import os

/// Fragt alle 30 s im Hintergrund ab, ob Bluetooth an ist (ueber
/// system_profiler, siehe `BluetoothStatus` - ohne Freigabe-Dialog).
///
/// Bluetooth wird selten umgeschaltet; 30 s Verzoegerung beim Anzeigen sind
/// vertretbar, und der ~165 ms teure Aufruf laeuft nie auf dem Hauptthread.
final class BluetoothState: @unchecked Sendable {
    private static let interval: TimeInterval = 30

    /// Serielle Queue: hier laeuft system_profiler, hier lebt der Timer.
    private let queue = DispatchQueue(label: AppIdentity.scoped("bluetooth"))
    private let log = Logger(category: "bluetooth")
    /// Nur auf `queue` anfassen.
    private var timer: DispatchSourceTimer?

    /// `update` wird auf dem Hauptthread aufgerufen, auch mit `nil`, wenn der
    /// Zustand nicht lesbar war.
    func start(update: @escaping @MainActor (Bool?) -> Void) {
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.interval)
            timer.setEventHandler { [self] in
                let state = readState()
                Task { @MainActor in update(state) }
            }
            timer.resume()
            self.timer = timer
        }
    }

    /// Einmal lesen, ohne Timer - fuer das Utilities-Panel, das beim Oeffnen
    /// sofort den aktuellen Stand will. Laeuft auf derselben Queue, also nie
    /// zwei system_profiler gleichzeitig.
    func readOnce(update: @escaping @MainActor (Bool?) -> Void) {
        queue.async { [self] in
            let state = readState()
            Task { @MainActor in update(state) }
        }
    }

    /// Einmal lesen, mit Geraeteliste - fuer das Bluetooth-Detailfenster
    /// neben der Leiste. Gleicher Aufruf, nur mehr aus derselben Ausgabe.
    func readSnapshotOnce(update: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void) {
        queue.async { [self] in
            let snapshot = runProfiler().flatMap(StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON:))
            Task { @MainActor in update(snapshot) }
        }
    }

    private func readState() -> Bool? {
        runProfiler().flatMap(BluetoothStatus.powerOn(fromSystemProfilerJSON:))
    }

    /// Wartet auf das Werkzeug (~165 ms) - laeuft auf `queue`, nie auf dem
    /// Hauptthread.
    private func runProfiler() -> Data? {
        Subprocess.runAndWait("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])?.output
    }
}
