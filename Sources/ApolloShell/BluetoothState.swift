import Foundation
import ApolloShellCore
import os

/// Asks every 30 s in the background whether Bluetooth is on (through
/// system_profiler, see `BluetoothStatus` - without a permission dialog).
///
/// Bluetooth is switched rarely; 30 s of delay in the display is bearable, and
/// the ~165 ms call never runs on the main thread.
final class BluetoothState: @unchecked Sendable {
    private static let interval: TimeInterval = 30

    /// A serial queue: system_profiler runs here, the timer lives here.
    private let queue = DispatchQueue(label: AppIdentity.scoped("bluetooth"))
    private let log = Logger(category: "bluetooth")
    /// Only touch on `queue`.
    private var timer: DispatchSourceTimer?

    /// `update` is called on the main thread, with `nil` too when the state
    /// could not be read.
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

    /// Read once, without a timer - for the utilities panel, which wants the
    /// current state right away on opening. Runs on the same queue, so never
    /// two system_profiler at once.
    func readOnce(update: @escaping @MainActor (Bool?) -> Void) {
        queue.async { [self] in
            let state = readState()
            Task { @MainActor in update(state) }
        }
    }

    /// Read once, with the device list - for the Bluetooth detail window next
    /// to the bar. The same call, only more out of the same output.
    func readSnapshotOnce(update: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void) {
        queue.async { [self] in
            let snapshot = runProfiler().flatMap(StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON:))
            Task { @MainActor in update(snapshot) }
        }
    }

    private func readState() -> Bool? {
        runProfiler().flatMap(BluetoothStatus.powerOn(fromSystemProfilerJSON:))
    }

    /// Waits for the tool (~165 ms) - runs on `queue`, never on the main
    /// thread.
    private func runProfiler() -> Data? {
        Subprocess.runAndWait("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])?.output
    }
}
