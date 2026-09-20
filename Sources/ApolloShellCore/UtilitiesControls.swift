import Foundation

/// A color as "#RRGGBB" for the color picker in the utilities panel.
///
/// Capitals as in Figma and Apple's color pickers - that is how one sees hex
/// values day to day. Values outside 0...1 (extended sRGB colors off P3
/// screens) are cut off instead of overflowing: "#FFFFFF" is closer to the
/// truth than a number error.
public enum UtilitiesColorHex {
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    private static func byte(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int((min(max(value, 0), 1) * 255).rounded())
    }
}

extension ToastText {
    /// After the color picker: the value is in the clipboard already.
    public static func colorCopied(_ hex: String) -> Content {
        Content(title: String(localized: "Color Copied"), message: hex, symbol: "eyedropper", kind: .info)
    }
}

// MARK: - Audio devices

/// Output or input.
public enum UtilitiesAudioScope: Sendable, Equatable {
    case output
    case input
}

/// A CoreAudio device the way the user interface needs it. The app reads the
/// values out of CoreAudio; the choice (what goes into which menu) is here -
/// so that it is testable.
public struct UtilitiesAudioDevice: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var outputStreams: Int
    public var inputStreams: Int
    /// `kAudioDevicePropertyDeviceCanBeDefaultDevice` per direction: Apple
    /// hides devices without this property in the sound settings.
    public var canBeDefaultOutput: Bool
    public var canBeDefaultInput: Bool
    public var hidden: Bool

    public init(id: UInt32, name: String, outputStreams: Int, inputStreams: Int,
                canBeDefaultOutput: Bool, canBeDefaultInput: Bool, hidden: Bool) {
        self.id = id
        self.name = name
        self.outputStreams = outputStreams
        self.inputStreams = inputStreams
        self.canBeDefaultOutput = canBeDefaultOutput
        self.canBeDefaultInput = canBeDefaultInput
        self.hidden = hidden
    }
}

public enum UtilitiesAudioDevices {
    /// What stands in the menu for this direction: at least one stream in the
    /// direction, selectable as the default, not hidden (hidden ones are
    /// aggregate devices apps create for themselves, say).
    ///
    /// Measured 14.09.: AirPods Pro report themselves as two devices of the
    /// same name (1 output stream / 1 input stream) - only the stream count
    /// tells them apart. The iPhone microphone (Continuity) has one input only.
    ///
    /// Sorted by name: the order out of CoreAudio changes when devices come
    /// and go; the menu should stay calm.
    public static func devices(_ all: [UtilitiesAudioDevice], for scope: UtilitiesAudioScope) -> [UtilitiesAudioDevice] {
        all.filter { device in
            guard !device.hidden else { return false }
            switch scope {
            case .output: return device.outputStreams > 0 && device.canBeDefaultOutput
            case .input: return device.inputStreams > 0 && device.canBeDefaultInput
            }
        }
        .sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }

    /// The name of the default device for the button label. Looked for among
    /// all devices, not only the filtered ones: when a hidden device is the
    /// default (which happens with conferencing apps), its name should stand
    /// there all the same, not "No Device".
    public static func label(defaultID: UInt32?, in all: [UtilitiesAudioDevice]) -> String {
        guard let defaultID, let device = all.first(where: { $0.id == defaultID }) else {
            return UtilitiesAudioText.noDevice
        }
        return displayName(device.name)
    }

    /// A menu line: an empty name as with the toasts, "Unknown Device".
    public static func displayName(_ name: String) -> String {
        ToastText.deviceName(name)
    }
}

/// The texts of the sound card.
public enum UtilitiesAudioText {
    public static let title = String(localized: "Sound")
    public static let output = String(localized: "Output")
    public static let input = String(localized: "Input")
    public static let noDevice = String(localized: "No Device")
    public static let noDevicesInMenu = String(localized: "No Devices")

    /// "45 %" (with a space, as written in Switzerland and Germany), muted
    /// "Muted" - a zero would look like an error.
    public static func level(volume: Float, muted: Bool) -> String {
        muted ? String(localized: "Muted") : String(localized: "\(VolumeGlyphs.percent(volume)) %")
    }

    public static func muteHelp(muted: Bool) -> String {
        muted ? String(localized: "Unmute") : String(localized: "Mute")
    }
}

// MARK: - Keyboard shortcuts

/// A key with modifiers, the way macOS puts it down in
/// com.apple.symbolichotkeys: `parameters = (ASCII, key code, modifier mask)`.
///
/// The mask uses the same bits as `CGEventFlags` (⇧ 0x20000, ⌃ 0x40000,
/// ⌥ 0x80000, ⌘ 0x100000, Fn 0x800000) - so the app can hang it on the key
/// press unchanged. Post it exactly as it stands there: “Show Desktop” is
/// F11 there WITHOUT the Fn bit (measured 14.09.: 65535, 103, 0), while the
/// arrows for the spaces are WITH it.
public struct UtilitiesHotKey: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    /// Only the device-independent modifier bits; the rest of the mask (left
    /// or right, Caps Lock) does not belong in a posted press.
    public static let modifierMask: UInt64 = 0x00FF_0000
    /// 65535 = "no key" in symbolichotkeys.
    public static let noKey = 65535

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Mission Control "Show Desktop".
    public static let showDesktopID = 36
    /// "Screenshot and Recording Options" (⌘⇧5).
    public static let screenshotToolbarID = 184

    /// The values when the entry is missing (then the macOS default holds).
    /// Both measured and equal to the default: F11, ⌘⇧5.
    public static let showDesktopDefault = UtilitiesHotKey(keyCode: 103, modifiers: 0)
    public static let screenshotToolbarDefault = UtilitiesHotKey(keyCode: 23, modifiers: 0x12_0000)

    /// "Lock Screen" in the Apple menu, ⌃⌘Q. Not a symbolic hotkey but a menu
    /// command - so it stands fixed.
    public static let lockScreen = UtilitiesHotKey(keyCode: 12, modifiers: 0x14_0000)

    /// Out of a symbolichotkeys entry, the key one has to post.
    /// - The entry is missing entirely (`enabled` and `parameters` nil): the macOS default.
    /// - Switched off: `nil` - then there is nothing to press.
    /// - On, but without usable values: the default.
    /// - Key code 65535: on, but no key assigned - `nil`.
    public static func resolve(enabled: Bool?, parameters: [Int]?, fallback: UtilitiesHotKey) -> UtilitiesHotKey? {
        if enabled == false { return nil }
        guard let parameters, parameters.count >= 3 else { return fallback }
        let code = parameters[1]
        guard code >= 0, code < noKey else { return nil }
        let mask = UInt64(max(parameters[2], 0)) & modifierMask
        return UtilitiesHotKey(keyCode: UInt16(code), modifiers: mask)
    }
}

// MARK: - Night Shift

/// Reads the state out of CoreBrightness' `getBlueLightStatus:`. That is a
/// private C struct; its shape as in the open source tools (nightlight,
/// Shifty): active, enabled, sunSchedulePermitted (1 byte each), mode (Int32
/// from 4 on), schedule (4 x Int32 from 8 on), disableFlags (UInt64 from 24
/// on), available (1 byte from 32 on) - 40 bytes with alignment.
///
/// Measured 14.09. at 16:00 (a 22-7 schedule saved, but off): byte 0 = 1,
/// byte 1 = 0, bytes 8/16 = 22/7, byte 32 = 1. So "enabled" (byte 1) is the
/// switch Apple's Control Centre shows; byte 0 stays 1 even with Night Shift
/// switched off.
public enum UtilitiesNightShiftStatus {
    /// This much room the call gets - more than the 40 bytes, in case a future
    /// macOS lengthens the struct. Too little would be a memory error, too
    /// much costs nothing.
    public static let bufferSize = 64
    static let enabledOffset = 1
    static let availableOffset = 32

    /// `nil`: the screen cannot do Night Shift (or the buffer is too short) -
    /// then the button stays off.
    public static func enabled(fromStatus bytes: [UInt8]) -> Bool? {
        guard bytes.count > availableOffset, bytes[availableOffset] != 0 else { return nil }
        return bytes[enabledOffset] != 0
    }
}
