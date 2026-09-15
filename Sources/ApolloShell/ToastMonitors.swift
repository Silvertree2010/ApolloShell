import CoreAudio
import Foundation
import IOKit.ps
import ApolloShellCore

/// Ladegeraet ein/aus und Akku-Warnstufen als Kurzmeldungen (Caelestia:
/// modules/BatteryMonitor.qml). Liest nur, loest nie Ruhezustand oder eine
/// andere Sitzungsaktion aus - bei leerem Akku handelt macOS selbst.
///
/// Eigene IOKit-Meldung statt Anhaengen an `StatusModel`: das gehoert der
/// Leiste und soll nicht wissen, wer sonst noch am Akku interessiert ist.
/// Gelesen wird mit derselben Funktion.
///
/// Lebt so lange wie die App: die IOKit-Quelle haelt einen unretained
/// Zeiger auf das Objekt (wie in `StatusModel`).
@MainActor
final class ToastPowerMonitor {
    /// Rueckfall, falls die IOKit-Meldung ausbleibt (wie StatusModel).
    private static let fallbackInterval: TimeInterval = 60

    private let toaster: Toaster
    /// Nexus > Kurzmeldungen: im Moment des Ereignisses gefragt, gilt also
    /// sofort.
    private let settings: ShellSettingsStore
    /// `nil`: kein Akku (Mac mini, iMac) - dann gibt es nichts zu melden.
    private var tracker: BatteryToastTracker?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    init(toaster: Toaster, settings: ShellSettingsStore) {
        self.toaster = toaster
        self.settings = settings
        // Der Zustand beim Start ist Ausgangspunkt, keine Meldung.
        if let state = StatusModel.readBattery() {
            tracker = BatteryToastTracker(percent: state.level, onBattery: !state.onAC)
        }
        observe()
        timer = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let state = StatusModel.readBattery() else { return }
        guard var tracker else {
            tracker = BatteryToastTracker(percent: state.level, onBattery: !state.onAC)
            return
        }
        // Der Tracker laeuft auch bei ausgeschalteter Meldung mit: sonst
        // kaeme beim Wiedereinschalten eine laengst vergangene Warnung.
        let events = tracker.update(percent: state.level, onBattery: !state.onAC)
        self.tracker = tracker
        let toasts = settings.settings.toasts
        for event in events where toasts.allows(event) {
            toaster.toast(ToastText.battery(event))
        }
    }

    /// IOKit meldet Netzteil und Ladestand sofort.
    private func observe() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ToastPowerMonitor>.fromOpaque(context).takeUnretainedValue()
            // Die Quelle haengt am Main-Runloop, der Aufruf kommt also dort an.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }
}

/// Wechsel des Standard-Ausgabe- und -Eingangsgeraets als Kurzmeldung
/// (Caelestia: services/Audio.qml, beide Meldungen dort standardmaessig an).
///
/// Nur CoreAudio-Eigenschaften lesen - kein Ton, also keine
/// Mikrofon-Freigabe. Schaltet nie ein Geraet um.
@MainActor
final class ToastAudioMonitor {
    private let toaster: Toaster
    private let settings: ShellSettingsStore
    private var output = ToastDeviceTracker()
    private var input = ToastDeviceTracker()
    private var listeners: [AudioObjectPropertyListenerBlock] = []

    init(toaster: Toaster, settings: ShellSettingsStore) {
        self.toaster = toaster
        self.settings = settings
        // Erste Namen merken, ohne Meldung.
        check(kAudioHardwarePropertyDefaultOutputDevice)
        check(kAudioHardwarePropertyDefaultInputDevice)
        listen(kAudioHardwarePropertyDefaultOutputDevice)
        listen(kAudioHardwarePropertyDefaultInputDevice)
    }

    private func listen(_ selector: AudioObjectPropertySelector) {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.check(selector) }
        }
        var address = Self.address(selector)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        listeners.append(listener)
    }

    /// Kein Geraet: nichts merken (Caelestia vergleicht nur, wenn es vorher
    /// schon einen Namen gab).
    private func check(_ selector: AudioObjectPropertySelector) {
        guard let device = Self.defaultDevice(selector) else { return }
        let name = Self.name(of: device) ?? ""
        let toasts = settings.settings.toasts
        // `update` zuerst und immer: der Name wird auch bei ausgeschalteter
        // Meldung nachgefuehrt (sonst meldete das Wiedereinschalten einen
        // alten Wechsel).
        if selector == kAudioHardwarePropertyDefaultOutputDevice {
            if output.update(name: name), toasts.audioOutputChanged { toaster.toast(ToastText.audioOutput(name)) }
        } else {
            if input.update(name: name), toasts.audioInputChanged { toaster.toast(ToastText.audioInput(name)) }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = address(selector)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// Anzeigename, z. B. "MacBook Pro-Lautsprecher". CoreAudio gibt den
    /// CFString mit +1 zurueck, deshalb `takeRetainedValue`.
    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
