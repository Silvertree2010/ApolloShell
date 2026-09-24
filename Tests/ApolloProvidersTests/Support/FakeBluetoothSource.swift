import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeBluetoothSource: BluetoothSource {
    static let airpods = StatusPopoutBluetoothDevice(name: "AirPods Pro", minorType: "Headphones", connected: true, batteries: [
        StatusPopoutBluetoothBattery(part: .left, percent: 80),
        StatusPopoutBluetoothBattery(part: .right, percent: 75),
        StatusPopoutBluetoothBattery(part: .case, percent: 40),
    ])
    static let keyboard = StatusPopoutBluetoothDevice(name: "Magic Keyboard", minorType: "Keyboard", connected: false, batteries: [])

    var snapshot: StatusPopoutBluetoothSnapshot? = StatusPopoutBluetoothSnapshot(powerOn: true, devices: [airpods, keyboard])
    var pending: [@MainActor (StatusPopoutBluetoothSnapshot?) -> Void] = []
    var requests = 0
    var openedSettings = 0
    var answersImmediately = true

    func read(_ completion: @escaping @MainActor (StatusPopoutBluetoothSnapshot?) -> Void) {
        requests += 1
        if answersImmediately {
            completion(snapshot)
        } else {
            pending.append(completion)
        }
    }

    func finish() {
        let waiting = pending
        pending.removeAll()
        for completion in waiting { completion(snapshot) }
    }

    func openSettings() {
        openedSettings += 1
    }
}
