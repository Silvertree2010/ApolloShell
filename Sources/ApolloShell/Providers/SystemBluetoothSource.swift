import AppKit
import ApolloProviders
import ApolloShellCore

@MainActor
final class SystemBluetoothSource: BluetoothSource {
    private let queue = DispatchQueue(label: AppIdentity.scoped("bluetooth"))

    func read(_ completion: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void) {
        queue.async {
            let output = Subprocess.runAndWait("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])?.output
            let snapshot = output.flatMap { StatusPopoutBluetoothParser.snapshot(fromSystemProfilerJSON: $0) }
            Task { @MainActor in completion(snapshot) }
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }
}
