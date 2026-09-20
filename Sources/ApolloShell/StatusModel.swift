import CoreWLAN
import Foundation
import IOKit.ps
import ApolloShellCore
import Observation

/// Live state for the bar's status icons: Wi-Fi, Bluetooth, battery.
///
/// All without extra permission (measured 14.09.): CoreWLAN provides
/// on/off and signal strength without location access (just not the network name,
/// which we don't need), IOKit provides the battery. Bluetooth comes from `BluetoothState`.
@MainActor
@Observable
final class StatusModel {
    private(set) var wifiOn = false
    private(set) var wifiRSSI: Int?
    private(set) var battery: BatteryState?
    private(set) var bluetoothOn: Bool?

    /// Wi-Fi changes constantly, the query costs measured ~9 ms: every 5 s.
    @ObservationIgnored private static let wifiInterval: TimeInterval = 5
    /// Battery as a fallback, in case the IOKit notification stays silent.
    @ObservationIgnored private static let batteryInterval: TimeInterval = 60
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var batterySource: CFRunLoopSource?
    @ObservationIgnored private let bluetooth = BluetoothState()

    init() {
        refreshWifi()
        refreshBattery()
        timers = [
            .repeating(every: Self.wifiInterval, owner: self) { $0.refreshWifi() },
            .repeating(every: Self.batteryInterval, owner: self) { $0.refreshBattery() },
        ]
        observeBatteryChanges()
        bluetooth.start { [weak self] on in
            self?.bluetoothOn = on
        }
    }

    /// For the screenshot test: fixed values, no queries, no timers.
    init(previewWifiRSSI rssi: Int?, battery: BatteryState?, bluetoothOn: Bool?) {
        wifiOn = true
        wifiRSSI = rssi
        self.battery = battery
        self.bluetoothOn = bluetoothOn
    }

    private func refreshWifi() {
        let iface = CWWiFiClient.shared().interface()
        let on = iface?.powerOn() ?? false
        let rssi = on ? iface?.rssiValue() : nil
        if on != wifiOn { wifiOn = on }
        if rssi != wifiRSSI { wifiRSSI = rssi }
    }

    private func refreshBattery() {
        let next = Self.readBattery()
        if next != battery { battery = next }
    }

    /// Also used by `ToastPowerMonitor` (toasts) - read it properly once.
    static func readBattery() -> BatteryState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return BatteryState(
                level: Int((Double(current) / Double(max) * 100).rounded()),
                charging: (d[kIOPSIsChargingKey] as? Bool) ?? false,
                onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            )
        }
        return nil
    }

    /// IOKit reports the power adapter on/off immediately; that's how the bolt jumps without the
    /// 60 s fallback wait.
    private func observeBatteryChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<StatusModel>.fromOpaque(context).takeUnretainedValue()
            // The source is tied to the main run loop, so the call arrives there.
            MainActor.assumeIsolated { model.refreshBattery() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        batterySource = source
    }
}
