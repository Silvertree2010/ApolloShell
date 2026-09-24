import AppKit
import CoreWLAN
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemWifiSource: WifiSource {
    private let log = Logger(category: "network")

    func read() -> WifiReading? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        let on = iface.powerOn()
        let rssi = on ? iface.rssiValue() : 0
        let channel = on && rssi != 0 ? iface.wlanChannel() : nil
        return WifiReading(
            powerOn: on,
            interfaceName: iface.interfaceName,
            rssi: rssi,
            noise: on ? iface.noiseMeasurement() : 0,
            transmitRate: on && rssi != 0 ? iface.transmitRate() : nil,
            phyMode: on ? iface.activePHYMode().rawValue : 0,
            channel: channel?.channelNumber,
            band: channel?.channelBand.rawValue
        )
    }

    func setPower(_ on: Bool) -> Bool {
        guard let iface = CWWiFiClient.shared().interface() else { return false }
        guard iface.powerOn() != on else { return true }
        do {
            try iface.setPower(on)
            return true
        } catch {
            log.error("WLAN schalten fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
