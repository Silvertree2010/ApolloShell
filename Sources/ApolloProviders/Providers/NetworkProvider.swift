import Foundation
import ApolloConfig
import ApolloRuntime
import ApolloShellCore

@MainActor
public final class NetworkProvider: BaseProvider {
    static let baseInterval: Double = 5
    static let detailInterval: Double = 2
    static let detailFields = ["wifi.rssi", "wifi.noise", "wifi.snr", "wifi.tx-rate", "wifi.standard", "wifi.band", "wifi.channel", "wifi.interface"]

    private let source: any WifiSource
    private var lastState: [Bool?]?

    public init(source: any WifiSource, clock: any RuntimeClock) {
        self.source = source
        super.init(schema: BuiltinProviderSchemas.schema("network"), clock: clock)
    }

    override func didStart() {
        lastState = nil
        timers.set("base", every: Self.baseInterval, active: true, immediately: true) { [weak self] in
            self?.refresh(details: false)
        }
    }

    override func didChangeDemand() {
        timers.set("details", every: Self.detailInterval, active: demand.wantsAny(Self.detailFields), immediately: true) { [weak self] in
            self?.refresh(details: true)
        }
    }

    override func handle(_ arguments: ActionArguments) async throws -> Value {
        switch arguments.action {
        case "network.set-wifi":
            setPower(try arguments.bool(0), action: arguments.action)
        case "network.toggle-wifi":
            setPower(!(source.read()?.powerOn ?? false), action: arguments.action)
        case "network.open-settings":
            source.openSettings()
        default:
            throw ProviderActionError.unknownAction(arguments.action)
        }
        return .null
    }

    private func setPower(_ on: Bool, action: String) {
        if !source.setPower(on) {
            warn("\(action): Wi-Fi could not be switched")
        }
        refresh(details: demand.wantsAny(Self.detailFields))
    }

    private func refresh(details: Bool) {
        guard isRunning else { return }
        let reading = source.read()
        let rssi = reading.flatMap { $0.powerOn ? $0.rssi : nil }
        publish("wifi.on", ProviderValue.bool(reading?.powerOn))
        publish("wifi.connected", .bool(reading?.connected ?? false))
        publish("wifi.bars", .number(Double(StatusPopoutSignal.bars(rssi: rssi))))
        publish("wifi.quality", .string(StatusPopoutSignal.quality(rssi: rssi)))
        publish("wifi.symbol", .string(StatusGlyphs.wifi(powerOn: reading?.powerOn ?? false, rssi: rssi).symbol))
        if details {
            publishDetails(reading)
        }
        let state = [reading?.powerOn, reading?.connected]
        if let lastState, lastState != state {
            emit("network.wifi-changed")
        }
        lastState = state
    }

    private func publishDetails(_ reading: WifiReading?) {
        let on = reading?.powerOn ?? false
        let rssi = on ? reading?.rssi.flatMap { $0 != 0 ? $0 : nil } : nil
        let noise = on ? reading?.noise.flatMap { $0 != 0 ? $0 : nil } : nil
        publish("wifi.rssi", ProviderValue.number(rssi))
        publish("wifi.noise", ProviderValue.number(noise))
        publish("wifi.snr", ProviderValue.number(StatusPopoutSignal.signalToNoise(rssi: rssi, noise: noise)))
        publish("wifi.tx-rate", ProviderValue.number(on ? reading?.transmitRate : nil))
        publish("wifi.standard", ProviderValue.string(on ? reading.flatMap { StatusPopoutSignal.phyModeName(rawValue: $0.phyMode) } : nil))
        publish("wifi.band", ProviderValue.string(on ? reading?.band.flatMap(StatusPopoutSignal.bandName(rawValue:)) : nil))
        publish("wifi.channel", ProviderValue.string(on ? reading?.channel.map(String.init) : nil))
        publish("wifi.interface", ProviderValue.string(reading?.interfaceName))
    }
}
