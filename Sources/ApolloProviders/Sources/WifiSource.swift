import Foundation

public struct WifiReading: Equatable, Sendable {
    public var powerOn: Bool
    public var interfaceName: String?
    public var rssi: Int?
    public var noise: Int?
    public var transmitRate: Double?
    public var phyMode: Int
    public var channel: Int?
    public var band: Int?

    public init(powerOn: Bool, interfaceName: String? = nil, rssi: Int? = nil, noise: Int? = nil, transmitRate: Double? = nil, phyMode: Int = 0, channel: Int? = nil, band: Int? = nil) {
        self.powerOn = powerOn
        self.interfaceName = interfaceName
        self.rssi = rssi
        self.noise = noise
        self.transmitRate = transmitRate
        self.phyMode = phyMode
        self.channel = channel
        self.band = band
    }

    public var connected: Bool { powerOn && (rssi ?? 0) != 0 }
}

@MainActor
public protocol WifiSource: AnyObject {
    func read() -> WifiReading?
    func setPower(_ on: Bool) -> Bool
    func openSettings()
}
