import Foundation
import ApolloShellCore
import os

final class BluetoothState: @unchecked Sendable {
    private static let interval: TimeInterval = 30

    private let queue = DispatchQueue(label: AppIdentity.scoped("bluetooth"))
    private let log = Logger(category: "bluetooth")
    private var timer: DispatchSourceTimer?

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

    func readOnce(update: @escaping @MainActor (Bool?) -> Void) {
        queue.async { [self] in
            let state = readState()
            Task { @MainActor in update(state) }
        }
    }

    func readSnapshotOnce(update: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void) {
        queue.async { [self] in
            let snapshot = runProfiler().flatMap(StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON:))
            Task { @MainActor in update(snapshot) }
        }
    }

    private func readState() -> Bool? {
        runProfiler().flatMap(BluetoothStatus.powerOn(fromSystemProfilerJSON:))
    }

    private func runProfiler() -> Data? {
        Subprocess.runAndWait("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])?.output
    }
}
