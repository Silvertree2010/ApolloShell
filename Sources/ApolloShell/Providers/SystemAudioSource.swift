import AudioToolbox
import CoreAudio
import Foundation
import ApolloProviders

@MainActor
final class SystemAudioSource: AudioSource {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var handler: (@MainActor () -> Void)?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var watched: [(AudioObjectID, AudioObjectPropertyAddress)] = []

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let systemSelectors = [
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDefaultInputDevice,
        kAudioHardwarePropertyDevices,
    ]

    func read() -> AudioSnapshot {
        let output = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let input = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let all = devices()
        return AudioSnapshot(
            volume: output.flatMap { volume($0, kAudioDevicePropertyScopeOutput) },
            muted: output.flatMap { muted($0, kAudioDevicePropertyScopeOutput) } ?? false,
            output: output.flatMap(describe),
            input: input.flatMap(describe),
            inputVolume: input.flatMap { volume($0, kAudioDevicePropertyScopeInput) },
            inputMuted: input.flatMap { muted($0, kAudioDevicePropertyScopeInput) },
            outputs: all.filter { hasStreams($0, kAudioDevicePropertyScopeOutput) }.compactMap(describe),
            inputs: all.filter { hasStreams($0, kAudioDevicePropertyScopeInput) }.compactMap(describe)
        )
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        stopObserving()
        self.handler = handler
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.attachDevices()
                self?.handler?()
            }
        }
        for selector in Self.systemSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, .main, listener)
        }
        systemListener = listener
        attachDevices()
    }

    func stopObserving() {
        detachDevices()
        if let systemListener {
            for selector in Self.systemSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(system, &address, .main, systemListener)
            }
        }
        systemListener = nil
        handler = nil
    }

    func setVolume(_ volume: Double) -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return false }
        guard write(device, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput), Float32(volume)) else { return false }
        if volume > 0, muted(device, kAudioDevicePropertyScopeOutput) == true {
            _ = write(device, Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput), UInt32(0))
        }
        return true
    }

    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return false }
        return write(device, Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput), UInt32(muted ? 1 : 0))
    }

    func selectOutput(_ id: String) -> Bool {
        guard let device = device(uid: id) else { return false }
        return write(system, Self.address(kAudioHardwarePropertyDefaultOutputDevice), device)
    }

    func selectInput(_ id: String) -> Bool {
        guard let device = device(uid: id) else { return false }
        return write(system, Self.address(kAudioHardwarePropertyDefaultInputDevice), device)
    }

    func setInputVolume(_ volume: Double) -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return false }
        return write(device, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeInput), Float32(volume))
    }

    func setInputMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return false }
        return write(device, Self.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput), UInt32(muted ? 1 : 0))
    }

    private func attachDevices() {
        detachDevices()
        guard handler != nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handler?() }
        }
        deviceListener = listener
        let targets: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
            (kAudioHardwarePropertyDefaultOutputDevice, kAudioDevicePropertyScopeOutput),
            (kAudioHardwarePropertyDefaultInputDevice, kAudioDevicePropertyScopeInput),
        ]
        for (selector, scope) in targets {
            guard let device = defaultDevice(selector) else { continue }
            for property in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(property, scope)
                guard AudioObjectHasProperty(device, &address) else { continue }
                AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
                watched.append((device, address))
            }
        }
    }

    private func detachDevices() {
        guard let deviceListener else { return }
        for (device, address) in watched {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
        }
        watched.removeAll()
        self.deviceListener = nil
    }

    private func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        guard let device: AudioObjectID = read(system, Self.address(selector), initial: AudioObjectID(kAudioObjectUnknown)),
              device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    private func devices() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func device(uid: String) -> AudioObjectID? {
        devices().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private func describe(_ device: AudioObjectID) -> AudioDevice? {
        guard let uid = string(device, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(id: uid, name: string(device, kAudioObjectPropertyName) ?? uid)
    }

    private func hasStreams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var address = Self.address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private func volume(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Double? {
        let value: Float32? = read(device, Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope), initial: Float32(0))
        return value.map(Double.init)
    }

    private func muted(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool? {
        let value: UInt32? = read(device, Self.address(kAudioDevicePropertyMute, scope), initial: UInt32(0))
        return value.map { $0 != 0 }
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func write<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address),
              AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}
