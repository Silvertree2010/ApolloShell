import AppKit
import ApolloShellCore
import CoreAudio
import os

/// The system hook-ups of the new quick toggles and of the sound card in the
/// utilities panel. Everything that works here without a permission dialog
/// does; where private interfaces are needed, they are looked up at runtime -
/// when they are missing in a future macOS, the button stays off instead of
/// the app crashing on the start.

private let systemLog = Logger(category: "utilities")

// MARK: - Dark mode

/// Dark mode through SkyLight, the way NightOwl and friends do it:
/// `BOOL SLSGetAppearanceThemeLegacy(void)` and
/// `void SLSSetAppearanceThemeLegacy(BOOL)`.
///
/// Why not AppleScript ("System Events" -> appearance preferences): that asks
/// for the automation permission the first time. SkyLight needs none. Measured
/// 14.09.: both symbols there, reading gives `true` when
/// `defaults read -g AppleInterfaceStyle` = Dark. Only when the symbols are
/// missing does it go through System Events (the text for that stands in the
/// Info.plist already).
@MainActor
enum UtilitiesAppearance {
    private typealias Getter = @convention(c) () -> Bool
    private typealias Setter = @convention(c) (Bool) -> Void

    private static let skyLight: (get: Getter, set: Setter)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let get = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
              let set = dlsym(handle, "SLSSetAppearanceThemeLegacy")
        else {
        systemLog.notice("Dark mode via SkyLight missing, falling back to System Events")
            return nil
        }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    /// SkyLight asks the window server straight away, so it is always current.
    /// Without SkyLight the global preference - "Dark" or nothing stands there.
    static func isDark() -> Bool {
        if let skyLight { return skyLight.get() }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return (style as? String) == "Dark"
    }

    static func setDark(_ dark: Bool) {
        if let skyLight { return skyLight.set(dark) }
        // osascript as a process of its own: it does not block the main thread,
        // not even while macOS asks for the permission the first time.
        Subprocess.launch("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)",
        ])
    }
}

// MARK: - Night Shift

/// Night Shift through CoreBrightness' `CBBlueLightClient` (private, through
/// the ObjC runtime), like the open source `nightlight` and Shifty.
///
/// Measured 14.09. in an unsigned test program: the class is there,
/// `supportsBlueLightReduction` = yes, `getBlueLightStatus:` delivers without
/// a dialog. `setEnabled:` is the same connection to the service; trying it
/// out was left alone on purpose (it would have recolored the screen of the
/// test machine).
@MainActor
final class UtilitiesNightShiftClient {
    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool

    private let client: NSObject
    private let getSelector = NSSelectorFromString("getBlueLightStatus:")
    private let setSelector = NSSelectorFromString("setEnabled:")

    /// `nil`: CoreBrightness or the class is missing, or it no longer knows
    /// the two methods.
    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        guard client.responds(to: getSelector), client.responds(to: setSelector) else { return nil }
        self.client = client
    }

    /// `nil`: a screen without Night Shift, or the query failed.
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

// MARK: - Key presses

/// Key presses for the action buttons, like SpaceSwitcher. Needs the
/// accessibility permission (the launcher has it); without it nothing happens.
///
/// Why keys instead of doing it ourselves: the screenshot bar, “Show Desktop”
/// and “Lock Screen” are system functions macOS only offers through their
/// shortcuts. The press sets off exactly what it would set off from the
/// keyboard - and our app needs no screen recording permission for that.
enum UtilitiesKeys {
    /// Read the shortcut the way it is set in Mission Control or under
    /// Keyboard > Keyboard Shortcuts - do not assume it.
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

    /// `false`: no permission or no event - then the caller should take the
    /// fallback, if there is one.
    @discardableResult
    static func post(_ key: UtilitiesHotKey) -> Bool {
        guard AXIsProcessTrusted() else {
            systemLog.error("Key press not possible without the Accessibility permission")
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down) else { return false }
            // Exactly the stored modifiers, nothing else: if a key is held
            // right now, it should not falsify the shortcut.
            event.flags = CGEventFlags(rawValue: key.modifiers)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

// MARK: - Audio devices

/// Reads the CoreAudio devices and sets the default device. Only properties,
/// no sound - so no microphone permission. Measured 14.09.:
/// `kAudioHardwarePropertyDefaultOutputDevice` is writable.
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

    /// Like the choice in the sound settings. The toast "Audio output changed"
    /// then comes by itself (ToastAudioMonitor listens in).
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

    /// The number of streams in one direction: the size of the list divided by
    /// the size of one stream ID. That tells output from input.
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

    /// CoreAudio hands the CFString back with +1, hence `takeRetainedValue`.
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
