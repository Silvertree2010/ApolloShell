import AppKit
import CoreWLAN
import Foundation
import IOKit
import IOKit.ps
import ApolloShellCore
import Observation
import os

/// WLAN-Details, alle ohne Ortungsfreigabe lesbar (gemessen 14.09.):
/// Interface, an/aus, RSSI, Rauschen, Senderate, PHY-Modus, Kanal. Der
/// Netzname (SSID) und die BSSID kommen ohne Ortung als nil zurueck - danach
/// fragen wir bewusst nicht.
struct StatusPopoutWifiInfo: Equatable {
    var powerOn: Bool
    var interfaceName: String?
    /// 0 oder nil: nicht verbunden.
    var rssi: Int?
    var noise: Int?
    /// Mbit/s.
    var transmitRate: Double?
    /// Rohwert von `CWPHYMode`.
    var phyMode: Int
    var channel: Int?
    /// Rohwert von `CWChannelBand`.
    var band: Int?

    var connected: Bool { powerOn && (rssi ?? 0) != 0 }
}

/// Akku-Details: IOPowerSources fuer Stand und Zeiten, IORegistry
/// (AppleSmartBattery) fuer Ladezyklen und Kapazitaet, ProcessInfo fuer den
/// Stromsparmodus. Alles ohne Freigabe.
struct StatusPopoutBatteryInfo: Equatable {
    var state: BatteryState
    /// Minuten wie IOKit sie meldet: -1 rechnet noch, 0 keine Angabe.
    var minutesToEmpty: Int
    var minutesToFull: Int
    var cycleCount: Int?
    var healthPercent: Int?
    var lowPowerMode: Bool
}

/// Zustand der Detailfenster neben der Statuskapsel: welches offen ist und
/// was darin steht.
///
/// Gelesen wird nur, solange ein Fenster offen ist, und nur, was es zeigt
/// (Caelestia laedt den Inhalt auch erst beim Oeffnen): WLAN und Akku alle
/// 2 s (je wenige Millisekunden), Bluetooth nur jede fuenfte Runde, denn
/// system_profiler kostet ~165 ms in einem eigenen Prozess.
@MainActor
@Observable
final class StatusPopoutModel {
    /// Zuletzt gezeigter Inhalt. Bleibt beim Schliessen stehen, damit der
    /// Inhalt waehrend der Schliessbewegung nicht verschwindet.
    private(set) var shown: StatusPopoutKind = .wifi
    private(set) var isOpen = false
    /// `nil`: kein WLAN-Interface.
    private(set) var wifi: StatusPopoutWifiInfo?
    /// `nil`: noch nicht gelesen (erstes system_profiler laeuft) oder nicht lesbar.
    private(set) var bluetooth: StatusPopoutBluetoothSnapshot?
    private(set) var bluetoothRead = false
    /// `nil`: kein Akku.
    private(set) var battery: StatusPopoutBatteryInfo?

    /// Wo die drei Symbole in der Leiste liegen, in Koordinaten der
    /// Leisten-Ansicht (oben = 0). Nicht beobachtet: aendert sich bei jedem
    /// Layout und soll keine Neuzeichnung ausloesen.
    @ObservationIgnored var iconFrames: [StatusPopoutKind: CGRect] = [:]
    /// Klick auf ein Statussymbol; setzt `StatusPopout`.
    @ObservationIgnored var onIconClick: (StatusPopoutKind) -> Void = { _ in }
    /// Nach "...-Einstellungen": das Fenster schliesst (Caelestia loest das
    /// Popout dann ebenfalls ab).
    @ObservationIgnored var onOpenedSettings: () -> Void = {}
    private(set) var stack: DockStack?
    @ObservationIgnored private(set) lazy var nets = WifiNetworks()
    enum Speed: Equatable { case idle, running(SpeedResult?, Date), done(SpeedResult), failed }
    private(set) var speed: Speed = .idle
    nonisolated static let speedLimit: TimeInterval = 20

    var speedRunning: Bool { if case .running = speed { true } else { false } }

    func runSpeedTest() {
        guard live, !speedRunning else { return }
        let start = Date()
        speed = .running(nil, start)
        Task.detached { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            p.arguments = ["-q", "/dev/null", "/usr/bin/networkQuality", "-M", String(Int(StatusPopoutModel.speedLimit))]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else {
                await MainActor.run { [weak self] in self?.speed = .failed }
                return
            }
            var all = ""
            var last: SpeedResult?
            let h = out.fileHandleForReading
            while true {
                let d = h.availableData
                if d.isEmpty { break }
                let chunk = String(decoding: d, as: UTF8.self)
                all += chunk
                for line in chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
                    if let r = SpeedResult.live(String(line)), r.down > 0 || r.up > 0 {
                        last = r
                        let snap = r
                        await MainActor.run { [weak self] in
                            guard let self, self.speedRunning else { return }
                            self.speed = .running(snap, start)
                        }
                    }
                }
            }
            p.waitUntilExit()
            let final = SpeedResult.summary(all, last: last)
            await MainActor.run { [weak self] in self?.speed = final.map(Speed.done) ?? .failed }
        }
    }
    @ObservationIgnored var onStackHover: (DockStack, CGRect, Bool) -> Void = { _, _, _ in }
    @ObservationIgnored var onStackToggle: (DockStack, CGRect) -> Void = { _, _ in }
    @ObservationIgnored var onPanelHover: (Bool) -> Void = { _ in }
    @ObservationIgnored var onIconHover: (StatusPopoutKind, Bool) -> Void = { _, _ in }
    @ObservationIgnored var onStackClick: (DockStackItem, NSEvent.ModifierFlags) -> Void = { _, _ in }
    @ObservationIgnored var onStackMenu: (DockStackItem, NSView) -> Void = { _, _ in }
    @ObservationIgnored var onStackDrop: (DockStackItem, [URL]) -> Void = { _, _ in }

    @ObservationIgnored private static let interval: TimeInterval = 2
    @ObservationIgnored private static let bluetoothEvery = 5
    @ObservationIgnored private(set) var live: Bool
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

    /// Modell mit festen Werten, das nichts liest und nichts schaltet - fuer
    /// Bildproben.
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

    /// Mitte des angeklickten Symbols, von der Oberkante des Popout-Fensters
    /// aus gemessen.
    private(set) var anchorY: CGFloat = 0
    /// Wo das Glas gerade im Fenster steht (oben = 0) - fuer den Klicktest
    /// "ausserhalb". Nicht beobachtet, wie `iconFrames`.
    @ObservationIgnored var panelFrame: CGRect = .zero

    // MARK: - Oeffnen, wechseln, schliessen

    /// Inhalt und Lage setzen, ohne zu oeffnen - vor dem Oeffnen aus dem
    /// geschlossenen Zustand, damit die Lage springt statt zu gleiten
    /// (Caelestia: y animiert nur, solange das Popout offen ist).
    func setStack(_ next: DockStack?) {
        if next != stack { stack = next }
    }

    func prepare(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        shown = kind
        self.anchorY = anchorY
    }

    /// Oeffnen oder in-place wechseln: sofort lesen, dann alle 2 s.
    func show(_ kind: StatusPopoutKind, anchorY: CGFloat) {
        if live { StatusPopoutSound.use(kind == .sound) }
        if live, kind == .wifi { nets.load() }
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
        if live { StatusPopoutSound.use(false) }
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
        case .stack, .sound: break
        }
    }

    // MARK: - Lesen

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

    /// Stand und Laden wie die Statuskapsel (`StatusModel.readBattery`),
    /// dazu Zeiten, Zyklen, Kapazitaet.
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
        // Einzelne Schluessel statt der ganzen Eigenschaftsliste: die enthaelt
        // BatteryData mit Dutzenden Messreihen. Gemessen ~0,14 ms fuer vier.
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

    // MARK: - Aktionen

    /// Nur auf Klick des Nutzers auf den Schalter. Braucht keine Freigabe.
    func setWifiPower(_ on: Bool) {
        guard live, let iface = CWWiFiClient.shared().interface(), iface.powerOn() != on else { return }
        do {
            try iface.setPower(on)
        } catch {
            log.error("WLAN schalten fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
        readWifi()
    }

    /// Bereiche gemessen 14.09. aus den Info.plist der Einstellungs-
    /// Erweiterungen (Wi-Fi.appex, Bluetooth.appex, PowerPreferences.appex).
    func openSettings(for kind: StatusPopoutKind) {
        guard live else { return }
        let pane = switch kind {
        case .wifi: "com.apple.wifi-settings-extension"
        case .bluetooth: "com.apple.BluetoothSettings"
        case .battery: "com.apple.Battery-Settings.extension"
        case .stack: ""
        case .sound: "com.apple.Sound-Settings.extension"
        }
        guard !pane.isEmpty else { return }
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
        onOpenedSettings()
    }
}
