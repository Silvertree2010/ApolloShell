import AudioToolbox
import CoreAudio
import Foundation

/// The volume and the mute of the default output device, live through a
/// CoreAudio listener. When the output device changes (headphones plugged in,
/// AirPods connected), it hangs itself on the new device.
///
/// No permission needed. It sets the volume and the mute only on an explicit
/// wish (the OSD slider, the sound card of the utilities), otherwise it only
/// reads. It uses the "virtual main volume": many devices have no main
/// control, only one per channel - the virtual one covers both.
@MainActor
final class VolumeMonitor {
    private(set) var volume: Float = 0
    private(set) var muted = false
    /// Some outputs (HDMI, digital converters) have no control or no mute; then
    /// the control stays off.
    private(set) var volumeSettable = false
    private(set) var muteSettable = false
    /// Only on real changes after `start()`, not on the first reading.
    var onChange: (_ volume: Float, _ muted: Bool) -> Void = { _, _ in }

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice(notify: true) }
        }
        var address = Self.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        deviceListener = listener
        attachToDefaultDevice(notify: false)
    }

    /// Let go of the listener on the old device, hang it on the current default.
    private func attachToDefaultDevice(notify: Bool) {
        if let listener = valueListener, device != kAudioObjectUnknown {
            var volume = Self.volumeAddress
            var mute = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, listener)
        }
        guard let next: AudioObjectID = Self.read(AudioObjectID(kAudioObjectSystemObject), Self.defaultOutputAddress, initial: AudioObjectID(kAudioObjectUnknown)),
              next != kAudioObjectUnknown
        else { return }
        device = next

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh(notify: true) }
        }
        var volume = Self.volumeAddress
        var mute = Self.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        valueListener = listener
        refresh(notify: notify)
    }

    /// Only on an explicit wish: dragging the OSD slider. It lifts the mute as
    /// soon as a value above 0 is set (like the volume keys).
    func setVolume(_ newValue: Float) {
        guard device != kAudioObjectUnknown else { return }
        var address = Self.volumeAddress
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var value = min(max(newValue, 0), 1)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)

        if muted && value > 0 {
            var muteAddress = Self.muteAddress
            var muteSettable: DarwinBoolean = false
            if AudioObjectIsPropertySettable(device, &muteAddress, &muteSettable) == noErr, muteSettable.boolValue {
                var off: UInt32 = 0
                AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            }
        }
    }

    /// Only on an explicit wish: the mute button of the sound card.
    func setMuted(_ newValue: Bool) {
        guard device != kAudioObjectUnknown, Self.settable(device, Self.muteAddress) else { return }
        var address = Self.muteAddress
        var value: UInt32 = newValue ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func settable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    private func refresh(notify: Bool) {
        // On every reading: after a device change it can be different.
        volumeSettable = Self.settable(device, Self.volumeAddress)
        muteSettable = Self.settable(device, Self.muteAddress)
        let newVolume: Float = Self.read(device, Self.volumeAddress, initial: Float(0)) ?? volume
        let newMuted = (Self.read(device, Self.muteAddress, initial: UInt32(0)) ?? (muted ? 1 : 0)) != 0
        let changed = newVolume != volume || newMuted != muted
        volume = newVolume
        muted = newMuted
        if notify && changed { onChange(volume, muted) }
    }

    /// Read one property; `nil` when the device does not have it.
    /// `BitwiseCopyable`: CoreAudio writes raw bytes into `value` - that is
    /// only safe for plain data types (Float, UInt32, AudioObjectID).
    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
