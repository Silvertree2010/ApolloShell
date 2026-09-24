import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class BluetoothProvider: BaseProvider {
    static let stateInterval: Double = 30
    static let deviceInterval: Double = 10

    private let source: any BluetoothSource
    private var generation = 0
    private var reading = false
    private var lastState: [Int?]?

    public init(source: any BluetoothSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("bluetooth"), clock: clock)
    }

    override func didStart() {
        generation += 1
        reading = false
        lastState = nil
        publish("status", .string("reading"))
        timers.set("state", every: Self.stateInterval, active: true, immediately: true) { [weak self] in
            self?.request()
        }
    }

    override func didChangeDemand() {
        timers.set("devices", every: Self.deviceInterval, active: demand.wants("devices"), immediately: true) { [weak self] in
            self?.request()
        }
    }

    override func didStop() {
        generation += 1
        reading = false
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "bluetooth.open-settings" else {
            throw ProviderActionError.unknownAction(arguments.action)
        }
        source.openSettings()
        return .null
    }

    private func request() {
        guard isRunning, !reading else { return }
        reading = true
        let generation = generation
        source.read { [weak self] snapshot in
            guard let self, generation == self.generation else { return }
            self.reading = false
            self.apply(snapshot)
        }
    }

    private func apply(_ snapshot: StatusPopoutBluetoothSnapshot?) {
        guard isRunning else { return }
        guard let snapshot else {
            publish("status", .string("unavailable"))
            publish("on", .null)
            publish("paired", .number(0))
            publish("connected", .number(0))
            publish("devices", .list([]))
            report([nil, 0, 0])
            return
        }
        let connected = snapshot.connected
        publish("status", .string("ready"))
        publish("on", ProviderValue.bool(snapshot.powerOn))
        publish("paired", .number(Double(snapshot.pairedCount)))
        publish("connected", .number(Double(connected.count)))
        publish("devices", .list(connected.map(Self.device)))
        report([snapshot.powerOn.map { $0 ? 1 : 0 }, snapshot.pairedCount, connected.count])
    }

    private func report(_ state: [Int?]) {
        if let lastState, lastState != state {
            emit("bluetooth.changed")
        }
        lastState = state
    }

    static func device(_ device: StatusPopoutBluetoothDevice) -> Value {
        var battery = Record()
        for part in [StatusPopoutBluetoothBattery.Part.main, .left, .right, .case] {
            let percent = device.batteries.first { $0.part == part }?.percent
            battery[part.rawValue] = ProviderValue.number(percent.map { Double($0) / 100 })
        }
        return .record(Record([
            ("name", .string(device.name)),
            ("kind", ProviderValue.string(device.minorType?.lowercased())),
            ("symbol", .string(device.symbol)),
            ("battery", .record(battery)),
        ]))
    }
}
