import AppKit
import ApolloShellCore
import CoreAudio
import os

/// Die Systemanbindungen der neuen Schnellschalter und der Ton-Karte im
/// Utilities-Panel. Alles, was hier ohne Freigabe-Dialog geht, geht hier
/// ohne; wo private Schnittstellen noetig sind, werden sie zur Laufzeit
/// nachgeschlagen - fehlen sie in einem kuenftigen macOS, bleibt der Knopf
/// aus, statt dass die App beim Start abstuerzt.

private let systemLog = Logger(subsystem: AppIdentity.logSubsystem, category: "utilities")

// MARK: - Dunkelmodus

/// Dunkelmodus ueber SkyLight, wie es NightOwl & Co. tun:
/// `BOOL SLSGetAppearanceThemeLegacy(void)` und
/// `void SLSSetAppearanceThemeLegacy(BOOL)`.
///
/// Warum nicht AppleScript ("System Events" -> appearance preferences): das
/// fragt beim ersten Mal nach der Automatisierungs-Freigabe. SkyLight
/// braucht keine. Gemessen 14.09.: beide Symbole da, Lesen ergibt `true`
/// bei `defaults read -g AppleInterfaceStyle` = Dark. Nur wenn die Symbole
/// fehlen, geht es ueber System Events (dafuer steht der Text schon in der
/// Info.plist).
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

    /// SkyLight fragt den Fensterserver direkt, also immer aktuell. Ohne
    /// SkyLight die globale Voreinstellung - dort steht "Dark" oder nichts.
    static func isDark() -> Bool {
        if let skyLight { return skyLight.get() }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication)
        return (style as? String) == "Dark"
    }

    static func setDark(_ dark: Bool) {
        if let skyLight { return skyLight.set(dark) }
        // osascript als eigener Prozess: blockiert den Hauptthread nicht,
        // auch nicht waehrend macOS beim ersten Mal nach der Freigabe fragt.
        Subprocess.launch("/usr/bin/osascript", [
            "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)",
        ])
    }
}

// MARK: - Night Shift

/// Night Shift ueber CoreBrightness' `CBBlueLightClient` (privat, ueber die
/// ObjC-Laufzeit), wie das quelloffene `nightlight` und Shifty.
///
/// Gemessen 14.09. in einem unsignierten Probeprogramm: Klasse da,
/// `supportsBlueLightReduction` = ja, `getBlueLightStatus:` liefert ohne
/// Dialog. `setEnabled:` ist dieselbe Verbindung zum Dienst; ausprobiert
/// wurde es bewusst nicht (es haette den Bildschirm des Testrechners
/// umgefaerbt).
@MainActor
final class UtilitiesNightShiftClient {
    private typealias GetStatus = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool

    private let client: NSObject
    private let getSelector = NSSelectorFromString("getBlueLightStatus:")
    private let setSelector = NSSelectorFromString("setEnabled:")

    /// `nil`: CoreBrightness oder die Klasse fehlen, oder sie kennt die zwei
    /// Methoden nicht mehr.
    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        guard client.responds(to: getSelector), client.responds(to: setSelector) else { return nil }
        self.client = client
    }

    /// `nil`: Bildschirm ohne Night Shift oder Abfrage gescheitert.
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

// MARK: - Tastendruecke

/// Tastendruecke fuer die Aktions-Knoepfe, wie SpaceSwitcher. Braucht die
/// Bedienungshilfen-Freigabe (hat der Launcher); ohne sie passiert nichts.
///
/// Warum Tasten statt eigener Umsetzung: Bildschirmfoto-Leiste,
/// "Schreibtisch anzeigen" und "Bildschirm sperren" sind Systemfunktionen,
/// die macOS nur ueber ihre Kurzbefehle anbietet. Der Druck loest genau das
/// aus, was er selbst mit der Tastatur ausloesen wuerde - unsere App braucht
/// dafuer keine Bildschirmaufnahme-Freigabe.
enum UtilitiesKeys {
    /// Den Kurzbefehl so lesen, wie er in Mission Control bzw. unter
    /// Tastatur > Tastaturkurzbefehle eingestellt ist - nicht annehmen.
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

    /// `false`: keine Freigabe oder kein Ereignis - dann soll der Aufrufer
    /// den Ersatzweg nehmen, falls es einen gibt.
    @discardableResult
    static func post(_ key: UtilitiesHotKey) -> Bool {
        guard AXIsProcessTrusted() else {
            systemLog.error("Tastendruck ohne Bedienungshilfen-Freigabe nicht moeglich")
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down) else { return false }
            // Genau die gespeicherten Modifier, sonst nichts: haelt er gerade
            // eine Taste, soll sie den Kurzbefehl nicht verfaelschen.
            event.flags = CGEventFlags(rawValue: key.modifiers)
            event.post(tap: .cghidEventTap)
        }
        return true
    }
}

// MARK: - Audiogeraete

/// Liest die CoreAudio-Geraete und setzt das Standardgeraet. Nur
/// Eigenschaften, kein Ton - also keine Mikrofon-Freigabe. Gemessen 14.09.:
/// `kAudioHardwarePropertyDefaultOutputDevice` ist schreibbar.
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

    /// Wie die Auswahl in den Toneinstellungen. Die Kurzmeldung "Audioausgabe
    /// geaendert" kommt dann von selbst (ToastAudioMonitor hoert mit).
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

    /// Anzahl Stroeme in einer Richtung: die Groesse der Liste geteilt durch
    /// die Groesse einer Strom-ID. Daran erkennt man Ausgabe oder Eingang.
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

    /// CoreAudio gibt den CFString mit +1 zurueck, deshalb `takeRetainedValue`.
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
