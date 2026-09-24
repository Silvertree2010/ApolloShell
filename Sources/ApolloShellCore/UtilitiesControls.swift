import Foundation

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
    public static func colorCopied(_ hex: String) -> Content {
        Content(title: String(localized: "Color Copied"), message: hex, symbol: "eyedropper", kind: .info)
    }
}

public enum UtilitiesAudioScope: Sendable, Equatable {
    case output
    case input
}

public struct UtilitiesAudioDevice: Equatable, Sendable, Identifiable {
    public var id: UInt32
    public var name: String
    public var outputStreams: Int
    public var inputStreams: Int
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

    public static func label(defaultID: UInt32?, in all: [UtilitiesAudioDevice]) -> String {
        guard let defaultID, let device = all.first(where: { $0.id == defaultID }) else {
            return UtilitiesAudioText.noDevice
        }
        return displayName(device.name)
    }

    public static func displayName(_ name: String) -> String {
        ToastText.deviceName(name)
    }
}

public enum UtilitiesAudioText {
    public static let title = String(localized: "Sound")
    public static let output = String(localized: "Output")
    public static let input = String(localized: "Input")
    public static let noDevice = String(localized: "No Device")
    public static let noDevicesInMenu = String(localized: "No Devices")

    public static func level(volume: Float, muted: Bool) -> String {
        muted ? String(localized: "Muted") : String(localized: "\(VolumeGlyphs.percent(volume)) %")
    }

    public static func muteHelp(muted: Bool) -> String {
        muted ? String(localized: "Unmute") : String(localized: "Mute")
    }
}

public struct UtilitiesHotKey: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public static let modifierMask: UInt64 = 0x00FF_0000
    public static let noKey = 65535

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let showDesktopID = 36
    public static let screenshotToolbarID = 184

    public static let showDesktopDefault = UtilitiesHotKey(keyCode: 103, modifiers: 0)
    public static let screenshotToolbarDefault = UtilitiesHotKey(keyCode: 23, modifiers: 0x12_0000)

    public static let lockScreen = UtilitiesHotKey(keyCode: 12, modifiers: 0x14_0000)

    public static func resolve(enabled: Bool?, parameters: [Int]?, fallback: UtilitiesHotKey) -> UtilitiesHotKey? {
        if enabled == false { return nil }
        guard let parameters, parameters.count >= 3 else { return fallback }
        let code = parameters[1]
        guard code >= 0, code < noKey else { return nil }
        let mask = UInt64(max(parameters[2], 0)) & modifierMask
        return UtilitiesHotKey(keyCode: UInt16(code), modifiers: mask)
    }
}

public enum UtilitiesNightShiftStatus {
    public static let bufferSize = 64
    static let enabledOffset = 1
    static let availableOffset = 32

    public static func enabled(fromStatus bytes: [UInt8]) -> Bool? {
        guard bytes.count > availableOffset, bytes[availableOffset] != 0 else { return nil }
        return bytes[enabledOffset] != 0
    }
}
