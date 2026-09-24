import AppKit
import ApolloShellCore
import CoreAudio
import os

private let systemLog = Logger(category: "utilities")

@MainActor
enum UtilitiesAppearance {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void

    private static let skyLight: (get: Getter, set: Setter)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let get = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
              let set = dlsym(handle, "SLSSetAppearanceThemeLegacy")
        else {
            systemLog.notice("SkyLight-Dunkelmodus fehlt, Ersatzweg System Events")
            return nil
        }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    static func isDark() -> Bool {
        if let skyLight { return skyLight.get() }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return (style as? String) == "Dark"
    }

    static func setDark(_ dark: Bool) {
        if let skyLight { return skyLight.set(dark) }
        Subprocess.launch("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)",
        ])
    }
}

@MainActor
final class UtilitiesNightShiftClient {
    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool

    private let client: NSObject
    private let getSelector = NSSelectorFromString("getBlueLightStatus:")
    private let setSelector = NSSelectorFromString("setEnabled:")

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        guard client.responds(to: getSelector), client.responds(to: setSelector) else { return nil }
        self.client = client
    }

    func enabled() -> Bool? {
        var bytes = [UInt8](repeating: 0, count: UtilitiesNightShiftStatus.bufferSize)
        let function = unsafeBitCast(client.method(for: getSelector), to: GetStatus.self)
        let ok = bytes.withUnsafeMutableBytes { raw in
            function(client, getSelector, raw.baseAddress!)
        }
        return ok ? UtilitiesNightShiftStatus.enabled(fromStatus: bytes) : nil
    }

    @discardableResult
    func setEnabled(_ on: Bool) -> Bool {
        unsafeBitCast(client.method(for: setSelector), to: SetEnabled.self)(client, setSelector, on)
    }
}

enum UtilitiesKeys {
    static func symbolic(id: Int, fallback: UtilitiesHotKey) -> UtilitiesHotKey? {
        let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        let entry = (all as? [String: Any])?[String(id)] as? [String: Any]
        let value = entry?["value"] as? [String: Any]
        return UtilitiesHotKey.resolve(
            enabled: entry?["enabled"] as? Bool,
            parameters: value?["parameters"] as? [Int],
            fallback: fallback
        )
    }

    @discardableResult
    static func post(_ key: UtilitiesHotKey) -> Bool {
        guard AXIsProcessTrusted() else {
            systemLog.error("Tastendruck ohne Bedienungshilfen-Freigabe nicht moeglich")
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down) else { return false }
            event.flags = CGEventFlags(rawValue: key.modifiers)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

enum UtilitiesAudioHardware {
    static func devices() -> [UtilitiesAudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            UtilitiesAudioDevice(
                id: id,
                name: name(of: id) ?? "",
                outputStreams: streamCount(id, kAudioObjectPropertyScopeOutput),
                inputStreams: streamCount(id, kAudioObjectPropertyScopeInput),
                canBeDefaultOutput: flag(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput),
                canBeDefaultInput: flag(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeInput),
                hidden: flag(id, kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal)
            )
        }
    }

    static func defaultDevice(_ scope: UtilitiesAudioScope) -> UInt32? {
        var address = address(selector(scope))
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func setDefault(_ device: UInt32, _ scope: UtilitiesAudioScope) -> OSStatus {
        var address = address(selector(scope))
        var value = AudioObjectID(device)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    private static func selector(_ scope: UtilitiesAudioScope) -> AudioObjectPropertySelector {
        scope == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func streamCount(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func flag(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             _ scope: AudioObjectPropertyScope) -> Bool {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
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
