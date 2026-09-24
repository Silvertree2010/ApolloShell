import CoreAudio
import Foundation
import IOKit.ps
import ApolloShellCore

@MainActor
final class ToastPowerMonitor {
    private static let fallbackInterval: TimeInterval = 60

    private let toaster: Toaster
    private let settings: ShellSettingsStore
    private var tracker: BatteryToastTracker?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    init(toaster: Toaster, settings: ShellSettingsStore) {
        self.toaster = toaster
        self.settings = settings
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
        let events = tracker.update(percent: state.level, onBattery: !state.onAC)
        self.tracker = tracker
        let toasts = settings.settings.toasts
        for event in events where toasts.allows(event) {
            toaster.toast(ToastText.battery(event))
        }
    }

    private func observe() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ToastPowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }
}

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

    private func check(_ selector: AudioObjectPropertySelector) {
        guard let device = Self.defaultDevice(selector) else { return }
        let name = Self.name(of: device) ?? ""
        let toasts = settings.settings.toasts
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
