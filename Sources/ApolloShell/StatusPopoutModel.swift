import AppKit
import CoreWLAN
import Foundation
import IOKit
import IOKit.ps
import ApolloShellCore
import Observation
import os

/// The Wi-Fi details, all readable without the location permission (measured
/// 14.09.): the interface, on/off, RSSI, noise, transmit rate, PHY mode,
/// channel. The network name (SSID) and the BSSID come back as nil without
/// location - we do not ask for that on purpose.
struct StatusPopoutWifiInfo: Equatable {
    var powerOn: Bool
    var interfaceName: String?
    /// 0 or nil: not connected.
    var rssi: Int?
    var noise: Int?
    /// Mbit/s.
    var transmitRate: Double?
    /// The raw value of `CWPHYMode`.
    var phyMode: Int
    var channel: Int?
    /// The raw value of `CWChannelBand`.
    var band: Int?

    var connected: Bool { powerOn && (rssi ?? 0) != 0 }
}

/// The battery details: IOPowerSources for the level and the times, the
/// IORegistry (AppleSmartBattery) for the cycles and the capacity,
/// ProcessInfo for Low Power Mode. All without a permission.
struct StatusPopoutBatteryInfo: Equatable {
    var state: BatteryState
    /// Minutes the way IOKit reports them: -1 is still working it out, 0 no entry.
    var minutesToEmpty: Int
    var minutesToFull: Int
    var cycleCount: Int?
    var healthPercent: Int?
    var lowPowerMode: Bool
}

/// The state of the detail windows next to the status capsule: which one is
/// open and what stands in it.
///
/// It is only read while a window is open, and only what that window shows
/// (Caelestia loads the content on opening too): Wi-Fi and battery every 2 s
/// (a few milliseconds each), Bluetooth only every fifth round, because
/// system_profiler costs ~165 ms in a process of its own.
@MainActor
@Observable
final class StatusPopoutModel {
    /// The content that was shown last. It stays on closing, so that the
    /// content does not disappear during the closing motion.
    private(set) var shown: StatusPopoutKind = .wifi
    private(set) var isOpen = false
    /// `nil`: no Wi-Fi interface.
    private(set) var wifi: StatusPopoutWifiInfo?
    /// `nil`: not read yet (the first system_profiler runs) or not readable.
    private(set) var bluetooth: StatusPopoutBluetoothSnapshot?
    private(set) var bluetoothRead = false
    /// `nil`: no battery.
    private(set) var battery: StatusPopoutBatteryInfo?

    /// Where the three symbols lie in the bar, in coordinates of the bar view
    /// (top = 0). Not observed: it changes on every layout and should set off
    /// no redraw.
    @ObservationIgnored var iconFrames: [StatusPopoutKind: CGRect] = [:]
    /// A click on a status symbol; set by `StatusPopout`.
    @ObservationIgnored var onIconClick: (StatusPopoutKind) -> Void = { _ in }
    /// After "... Settings": the window closes (Caelestia lets go of the
    /// popout then too).
    @ObservationIgnored var onOpenedSettings: () -> Void = {}

    @ObservationIgnored private static let interval: TimeInterval = 2
    @ObservationIgnored private static let bluetoothEvery = 5
    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private let bluetoothReader = BluetoothState()
    @ObservationIgnored private let log = Logger(category: "statuspopout")

    init() {
        live = true
    }

    private init(live: Bool) {
        self.live = live
    }

    /// A model with fixed values that reads nothing and switches nothing - for
    /// image samples.
    static func preview(
        shown: StatusPopoutKind,
        wifi: StatusPopoutWifiInfo?,
        bluetooth: StatusPopoutBluetoothSnapshot?,
        battery: StatusPopoutBatteryInfo?
    ) -> StatusPopoutModel {
        let model = StatusPopoutModel(live: false)
        model.shown = shown
        model.isOpen = true
        model.wifi = wifi
        model.bluetooth = bluetooth
        model.bluetoothRead = true
        model.battery = battery
        return model
    }

    /// The middle of the clicked symbol, measured from the top edge of the
    /// popout window.
    private(set) var anchorY: CGFloat = 0
    /// Where the glass stands in the window right now (top = 0) - for the
    /// "outside" click test. Not observed, like `iconFrames`.
    @ObservationIgnored var panelFrame: CGRect = .zero

    // MARK: - Opening, switching, closing

    /// Set the content and the place without opening - before opening out of
    /// the closed state, so that the place jumps instead of gliding
    /// (Caelestia: y only animates while the popout is open).
    func prepare(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        shown = kind
        self.anchorY = anchorY
    }

    /// Open or switch in place: read right away, then every 2 s.
    func show(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        shown = kind
        self.anchorY = anchorY
        isOpen = true
        guard live else { return }
        ticks = 0
        read(includingBluetooth: true)
        if timer == nil {
            timer = .repeating(every: Self.interval, owner: self) { $0.tick() }
        }
    }

    func hide() {
        isOpen = false
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        ticks += 1
        read(includingBluetooth: ticks % Self.bluetoothEvery == 0)
    }

    private func read(includingBluetooth: Bool) {
        switch shown {
        case .wifi: readWifi()
        case .battery: readBattery()
        case .bluetooth where includingBluetooth: readBluetooth()
        case .bluetooth: break
        }
    }

    // MARK: - Reading

    private func readWifi() {
        let next = CWWiFiClient.shared().interface().map { iface in
            let on = iface.powerOn()
            let rssi = on ? iface.rssiValue() : 0
            let channel = on && rssi != 0 ? iface.wlanChannel() : nil
            return StatusPopoutWifiInfo(
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
        if next != wifi { wifi = next }
    }

    private func readBattery() {
        let next = Self.readBatteryInfo()
        if next != battery { battery = next }
    }

    private func readBluetooth() {
        bluetoothReader.readSnapshotOnce { [weak self] snapshot in
            guard let self else { return }
            self.bluetoothRead = true
            if snapshot != self.bluetooth { self.bluetooth = snapshot }
        }
    }

    /// The level and the charging as in the status capsule
    /// (`StatusModel.readBattery`), plus the times, cycles and capacity.
    private static func readBatteryInfo() -> StatusPopoutBatteryInfo? {
        guard let state = StatusModel.readBattery() else { return nil }
        var toEmpty = 0, toFull = 0
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        for source in IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef] {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            toEmpty = d[kIOPSTimeToEmptyKey] as? Int ?? 0
            toFull = d[kIOPSTimeToFullChargeKey] as? Int ?? 0
        }
        // Single keys instead of the whole property list: that one holds
        // BatteryData with dozens of measurement series. Measured ~0.14 ms for four.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        func int(_ key: String) -> Int? {
            guard service != 0 else { return nil }
            return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        return StatusPopoutBatteryInfo(
            state: state,
            minutesToEmpty: toEmpty,
            minutesToFull: toFull,
            cycleCount: int("CycleCount"),
            healthPercent: StatusPopoutBatteryHealth.percent(
                rawMax: int("AppleRawMaxCapacity"), nominal: int("NominalChargeCapacity"), design: int("DesignCapacity")
            ),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    // MARK: - Actions

    /// Only on a click of the user on the switch. Needs no permission.
    func setWifiPower(_ on: Bool) {
        guard live, let iface = CWWiFiClient.shared().interface(), iface.powerOn() != on else { return }
        do {
            try iface.setPower(on)
        } catch {
            log.error("WLAN schalten fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        readWifi()
    }

    /// The areas measured 14.09. out of the Info.plist of the settings
    /// extensions (Wi-Fi.appex, Bluetooth.appex, PowerPreferences.appex).
    func openSettings(for kind: StatusPopoutKind) {
        guard live else { return }
        let pane = switch kind {
        case .wifi: "com.apple.wifi-settings-extension"
        case .bluetooth: "com.apple.BluetoothSettings"
        case .battery: "com.apple.Battery-Settings.extension"
        }
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
        onOpenedSettings()
    }
}
