import AudioToolbox
import CoreAudio
import Foundation

/// Lautstaerke und Stumm des Standard-Ausgabegeraets, live ueber
/// CoreAudio-Listener. Wechselt das Ausgabegeraet (Kopfhoerer rein, AirPods
/// verbunden), haengt es sich an das neue Geraet.
///
/// Keine Freigabe noetig. Setzt Lautstaerke und Stumm nur auf ausdruecklichen
/// Wunsch (OSD-Regler, Ton-Karte der Utilities), sonst liest es nur.
/// Nutzt die "virtuelle Hauptlautstaerke": viele Geraete haben keinen
/// Hauptregler, nur einen pro Kanal - die virtuelle deckt beides ab.
@MainActor
final class VolumeMonitor {
    private(set) var volume: Float = 0
    private(set) var muted = false
    /// Manche Ausgaben (HDMI, digitale Wandler) haben keinen Regler bzw.
    /// keine Stummschaltung; dann bleibt das Bedienelement aus.
    private(set) var volumeSettable = false
    private(set) var muteSettable = false
    /// Nur bei echten Aenderungen nach `start()`, nicht beim ersten Lesen.
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

    /// Listener vom alten Geraet loesen, ans aktuelle Standardgeraet haengen.
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

    /// Nur auf ausdruecklichen Wunsch: Ziehen am OSD-Regler. Hebt Stumm auf,
    /// sobald ein Wert ueber 0 gesetzt wird (wie die Lautstaerketasten).
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

    /// Nur auf ausdruecklichen Wunsch: Stumm-Knopf der Ton-Karte.
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
        // Bei jedem Lesen: nach einem Geraetewechsel kann es anders sein.
        volumeSettable = Self.settable(device, Self.volumeAddress)
        muteSettable = Self.settable(device, Self.muteAddress)
        let newVolume: Float = Self.read(device, Self.volumeAddress, initial: Float(0)) ?? volume
        let newMuted = (Self.read(device, Self.muteAddress, initial: UInt32(0)) ?? (muted ? 1 : 0)) != 0
        let changed = newVolume != volume || newMuted != muted
        volume = newVolume
        muted = newMuted
        if notify && changed { onChange(volume, muted) }
    }

    /// Eine Eigenschaft lesen; `nil`, wenn das Geraet sie nicht hat.
    /// `BitwiseCopyable`: CoreAudio schreibt rohe Bytes in `value` - das ist
    /// nur fuer reine Datentypen (Float, UInt32, AudioObjectID) sicher.
    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }
}
