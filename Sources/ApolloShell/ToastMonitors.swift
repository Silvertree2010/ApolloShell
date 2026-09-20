import CoreAudio
import Foundation
import IOKit.ps
import ApolloShellCore

/// The charger on and off and the battery warning levels as toasts (Caelestia:
/// modules/BatteryMonitor.qml). Only reads, never sets off sleep or another
/// session action - with an empty battery macOS acts by itself.
///
/// An IOKit notification of its own instead of hanging on to `StatusModel`:
/// that belongs to the bar and should not have to know who else is interested
/// in the battery. The reading uses the same function.
///
/// Lives as long as the app: the IOKit source holds an unretained pointer to
/// the object (as in `StatusModel`).
@MainActor
final class ToastPowerMonitor {
    /// The fallback should the IOKit notification not arrive (as in StatusModel).
    private static let fallbackInterval: TimeInterval = 60

    private let toaster: Toaster
    /// Nexus > Toasts: asked at the moment of the event, so it holds right
    /// away.
    private let settings: ShellSettingsStore
    /// `nil`: no battery (Mac mini, iMac) - then there is nothing to report.
    private var tracker: BatteryToastTracker?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    init(toaster: Toaster, settings: ShellSettingsStore) {
        self.toaster = toaster
        self.settings = settings
        // The state on the start is the starting point, not a toast.
        if let state = StatusModel.readBattery() {
            tracker = BatteryToastTracker(percent: state.level, onBattery: !state.onAC)
        }
        observe()
        timer = .repeating(every: Self.fallbackInterval, owner: self) { $0.refresh() }
    }

    private func refresh() {
        guard let state = StatusModel.readBattery() else { return }
        guard var tracker else {
            tracker = BatteryToastTracker(percent: state.level, onBattery: !state.onAC)
            return
        }
        // The tracker runs along even with the toast switched off: otherwise a
        // long-past warning would come on switching it back on.
        let events = tracker.update(percent: state.level, onBattery: !state.onAC)
        self.tracker = tracker
        let toasts = settings.settings.toasts
        for event in events where toasts.allows(event) {
            toaster.toast(ToastText.battery(event))
        }
    }

    /// IOKit reports the power adapter and the level right away.
    private func observe() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ToastPowerMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source hangs on the main runloop, so the call arrives there.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }
}

/// A change of the default output and input device as a toast (Caelestia:
/// services/Audio.qml, both toasts on by default there).
///
/// Only reads CoreAudio properties - no sound, so no microphone permission.
/// Never switches a device.
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
        // Remember the first names, without a toast.
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

    /// No device: remember nothing (Caelestia only compares when there was a
    /// name before).
    private func check(_ selector: AudioObjectPropertySelector) {
        guard let device = Self.defaultDevice(selector) else { return }
        let name = Self.name(of: device) ?? ""
        let toasts = settings.settings.toasts
        // `update` first and always: the name is kept up even with the toast
        // switched off (otherwise switching it back on would report an old
        // change).
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

    /// The display name, "MacBook Pro Speakers" for instance. CoreAudio hands
    /// the CFString back with +1, hence `takeRetainedValue`.
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
