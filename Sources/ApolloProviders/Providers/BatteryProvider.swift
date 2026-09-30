import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class BatteryProvider: BaseProvider {
    static let baseInterval: Double = 60
    static let detailInterval: Double = 2
    static let detailFields = ["health", "cycles", "low-power-mode"]
    static let lowPowerReread: Double = 1

    private let source: any BatterySource
    private var tracker: BatteryToastTracker?

    public init(source: any BatterySource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("battery"), clock: clock)
    }

    override func didStart() {
        tracker = nil
        source.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
        timers.set("base", every: Self.baseInterval, active: true) { [weak self] in
            self?.refresh()
        }
    }

    override func didChangeDemand() {
        timers.set("details", every: Self.detailInterval, active: demand.wantsAny(Self.detailFields), immediately: true) { [weak self] in
            self?.refreshDetails()
        }
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        guard arguments.action == "battery.set-low-power" else { throw ProviderActionError.unknownAction(arguments.action) }
        source.setLowPowerMode(try arguments.bool(0))
        timers.once("low-power-reread", after: Self.lowPowerReread) { [weak self] in
            self?.refreshDetails()
        }
        return .null
    }

    override func didStop() {
        source.stopObserving()
    }

    private func refresh() {
        guard isRunning else { return }
        guard let reading = source.read() else {
            publishAbsent()
            return
        }
        let state = BatteryState(level: reading.level, charging: reading.charging, onAC: reading.onAC)
        let toEmpty = reading.minutesToEmpty > 0 ? reading.minutesToEmpty : nil
        let toFull = reading.minutesToFull > 0 ? reading.minutesToFull : nil
        publish("present", .bool(true))
        publish("percent", .number(Double(min(max(reading.level, 0), 100)) / 100))
        publish("charging", .bool(reading.charging))
        publish("on-power", .bool(reading.onAC))
        publish("full", .bool(reading.charged || (reading.onAC && reading.level >= 100)))
        publish("minutes-to-empty", ProviderValue.number(toEmpty))
        publish("minutes-to-full", ProviderValue.number(toFull))
        publish("state-text", .string(StatusPopoutBatteryText.state(state)))
        publish("time-text", .string(StatusPopoutBatteryText.time(state, minutesToEmpty: reading.minutesToEmpty, minutesToFull: reading.minutesToFull)))
        publish("symbol", ProviderValue.string(StatusGlyphs.batterySymbol(state)))
        publish("tank-text", .string(BatteryTankText.status(state, minutes: reading.charging ? toFull : toEmpty)))
        track(reading)
    }

    private func publishAbsent() {
        publish("present", .bool(false))
        for field in ["percent", "minutes-to-empty", "minutes-to-full", "symbol", "health", "cycles"] {
            publish(field, .null)
        }
        publish("charging", .bool(false))
        publish("on-power", .bool(true))
        publish("full", .bool(false))
        publish("state-text", .string(StatusGlyphs.batteryText(nil)))
        publish("time-text", .string(""))
        publish("tank-text", .string(""))
    }

    private func refreshDetails() {
        guard isRunning else { return }
        let details = source.readDetails()
        publish("health", ProviderValue.number(details.healthPercent.map { Double($0) / 100 }))
        publish("cycles", ProviderValue.number(details.cycles))
        publish("low-power-mode", .bool(details.lowPowerMode))
    }

    private func track(_ reading: BatteryReading) {
        let onBattery = !reading.onAC
        guard var tracker else {
            tracker = BatteryToastTracker(percent: reading.level, onBattery: onBattery)
            return
        }
        let events = tracker.update(percent: reading.level, onBattery: onBattery)
        self.tracker = tracker
        for event in events {
            switch event {
            case .chargerConnected:
                emit("battery.charger-connected")
            case .chargerDisconnected:
                emit("battery.charger-disconnected")
            case .warning(let level):
                emit("battery.warning", Record([
                    ("level", .string(String(level.level))),
                    ("percent", .number(Double(reading.level) / 100)),
                    ("title", .string(level.title)),
                    ("body", .string(level.message)),
                    ("critical", .bool(level.critical)),
                ]))
            }
        }
    }
}
