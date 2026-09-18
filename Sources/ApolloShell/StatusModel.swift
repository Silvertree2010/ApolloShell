import CoreWLAN
import Foundation
import IOKit.ps
import ApolloShellCore
import Observation

/// Live-Zustand fuer die Statussymbole der Leiste: WLAN, Bluetooth, Akku.
///
/// Alles ohne zusaetzliche Freigabe (gemessen 14.09.): CoreWLAN liefert
/// "an" und Signalstaerke ohne Ortung (nur den Netznamen nicht, den brauchen
/// wir nicht), IOKit den Akku. Bluetooth kommt aus `BluetoothState`.
@MainActor
@Observable
final class StatusModel {
    private(set) var wifiOn = false
    private(set) var wifiRSSI: Int?
    private(set) var battery: BatteryState?
    private(set) var bluetoothOn: Bool?

    /// WLAN aendert sich laufend, die Abfrage kostet gemessen ~9 ms: alle 5 s.
    @ObservationIgnored private static let wifiInterval: TimeInterval = 5
    /// Akku als Rueckfall, falls die IOKit-Meldung ausbleibt.
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

    /// Fuer die Bildprobe: feste Werte, keine Abfragen, keine Timer.
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

    /// Auch fuer `ToastPowerMonitor` (Kurzmeldungen) - einmal richtig lesen.
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

    /// Netzteil ein/aus meldet IOKit sofort; so springt der Blitz ohne die
    /// 60 s Rueckfall-Wartezeit.
    private func observeBatteryChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<StatusModel>.fromOpaque(context).takeUnretainedValue()
            // Die Quelle haengt am Main-Runloop, der Aufruf kommt also dort an.
            MainActor.assumeIsolated { model.refreshBattery() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        batterySource = source
    }
}
