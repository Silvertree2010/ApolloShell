@testable import ApolloProviders

@MainActor
final class FakeWifiSource: WifiSource {
    var reading: WifiReading?
    var reads = 0
    var openedSettings = 0
    var powerCalls: [Bool] = []

    init(_ reading: WifiReading? = WifiReading(powerOn: true, interfaceName: "en0", rssi: -52, noise: -92, transmitRate: 866, phyMode: 6, channel: 36, band: 2)) {
        self.reading = reading
    }

    func read() -> WifiReading? {
        reads += 1
        return reading
    }

    func setPower(_ on: Bool) -> Bool {
        powerCalls.append(on)
        guard reading != nil else { return false }
        reading?.powerOn = on
        if !on { reading?.rssi = 0 }
        return true
    }

    func openSettings() {
        openedSettings += 1
    }
}
