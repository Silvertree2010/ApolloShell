import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Utilities-Panel: Farbpipette")
struct UtilitiesColorHexTests {
    @Test("sRGB-Anteile zu #RRGGBB, gerundet, Grossbuchstaben", arguments: [
        (1.0, 0.584, 0.0, "#FF9500"),
        (0.0, 0.0, 0.0, "#000000"),
        (1.0, 1.0, 1.0, "#FFFFFF"),
        (0.1, 0.2, 0.3, "#1A334D"),
    ])
    func hex(red: Double, green: Double, blue: Double, expected: String) {
        #expect(UtilitiesColorHex.hex(red: red, green: green, blue: blue) == expected)
    }

    @Test("ausserhalb 0...1 (erweitertes sRGB) wird abgeschnitten", arguments: [
        (1.2, -0.1, 0.5, "#FF0080"),
        (-3.0, 7.0, 1.0001, "#00FFFF"),
    ])
    func clamped(red: Double, green: Double, blue: Double, expected: String) {
        #expect(UtilitiesColorHex.hex(red: red, green: green, blue: blue) == expected)
    }

    @Test("keine Zahl: 00 statt Absturz")
    func notANumber() {
        #expect(UtilitiesColorHex.hex(red: .nan, green: .infinity, blue: 1) == "#0000FF")
    }

    @Test("Kurzmeldung: Titel fest, Hexwert als Text")
    func toast() {
        let content = ToastText.colorCopied("#FF9500")
        #expect(content.title == "Color Copied" && content.message == "#FF9500" && content.symbol == "eyedropper")
    }
}

@Suite("Utilities-Panel: Audiogeraete")
struct UtilitiesAudioDevicesTests {
    /// Die Geraete, wie sie am 14.09. auf einem MacBook gelesen wurden,
    /// plus ein verstecktes Aggregat und ein Geraet ohne Standard-Recht.
    static let measured: [UtilitiesAudioDevice] = [
        .init(id: 105, name: "iPhone Mikrofon", outputStreams: 0, inputStreams: 1,
              canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        .init(id: 61, name: "BlackHole 2ch", outputStreams: 1, inputStreams: 1,
              canBeDefaultOutput: true, canBeDefaultInput: true, hidden: false),
        .init(id: 100, name: "MacBook Pro-Mikrofon", outputStreams: 0, inputStreams: 1,
              canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        .init(id: 93, name: "MacBook Pro-Lautsprecher", outputStreams: 1, inputStreams: 0,
              canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false),
        .init(id: 113, name: "AirPods Pro", outputStreams: 0, inputStreams: 1,
              canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        .init(id: 107, name: "AirPods Pro", outputStreams: 1, inputStreams: 0,
              canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false),
        .init(id: 200, name: "CADefaultDeviceAggregate", outputStreams: 2, inputStreams: 1,
              canBeDefaultOutput: true, canBeDefaultInput: true, hidden: true),
        .init(id: 201, name: "Nur Ausgang, nicht waehlbar", outputStreams: 1, inputStreams: 0,
              canBeDefaultOutput: false, canBeDefaultInput: false, hidden: false),
    ]

    @Test("Ausgaenge: nur mit Ausgabestrom, waehlbar, nicht versteckt - nach Namen", arguments: [
        (UtilitiesAudioScope.output, [107 as UInt32, 61, 93]),
        (UtilitiesAudioScope.input, [113 as UInt32, 61, 105, 100]),
    ])
    func filter(scope: UtilitiesAudioScope, ids: [UInt32]) {
        #expect(UtilitiesAudioDevices.devices(Self.measured, for: scope).map(\.id) == ids)
    }

    @Test("gleiche Namen (AirPods) trennt die Stromzahl, nicht der Name")
    func airPodsSplit() {
        let outputs = UtilitiesAudioDevices.devices(Self.measured, for: .output).filter { $0.name == "AirPods Pro" }
        let inputs = UtilitiesAudioDevices.devices(Self.measured, for: .input).filter { $0.name == "AirPods Pro" }
        #expect(outputs.map(\.id) == [107] && inputs.map(\.id) == [113])
    }

    @Test("Beschriftung: Name des Standardgeraets, auch wenn es versteckt ist", arguments: [
        (107 as UInt32?, "AirPods Pro"),
        (200 as UInt32?, "CADefaultDeviceAggregate"),
        (999 as UInt32?, "No Device"),
        (nil as UInt32?, "No Device"),
    ])
    func label(id: UInt32?, expected: String) {
        #expect(UtilitiesAudioDevices.label(defaultID: id, in: Self.measured) == expected)
    }

    @Test("leerer Name: wie bei den Kurzmeldungen 'Unbekanntes Gerät'")
    func emptyName() {
        let blank = UtilitiesAudioDevice(id: 1, name: "  ", outputStreams: 1, inputStreams: 0,
                                         canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false)
        #expect(UtilitiesAudioDevices.label(defaultID: 1, in: [blank]) == "Unknown Device")
    }

    @Test("Pegeltext: Prozent mit Leerschlag, stumm als Wort", arguments: [
        (Float(0.45), false, "45 %"),
        (Float(0.45), true, "Muted"),
        (Float(1.2), false, "100 %"),
        (Float(0), false, "0 %"),
    ])
    func level(volume: Float, muted: Bool, expected: String) {
        #expect(UtilitiesAudioText.level(volume: volume, muted: muted) == expected)
    }
}

@Suite("Utilities-Panel: Tastenkuerzel aus symbolichotkeys")
struct UtilitiesHotKeyTests {
    @Test("Tastencode und Maske wie gespeichert; Maske nur Modifier-Bits", arguments: [
        ([65535, 103, 0], 103, 0),                      // Schreibtisch anzeigen, gemessen: F11 ohne Fn
        ([53, 23, 1_179_648], 23, 0x12_0000),           // ⌘⇧5
        ([65535, 125, 0x84_0000], 125, 0x84_0000),      // ⌃↓ mit Fn, wie echte Pfeiltasten
        ([113, 12, 0x114_0000], 12, 0x14_0000),         // Bit ausserhalb der Maske faellt weg
    ])
    func resolved(parameters: [Int], keyCode: Int, modifiers: Int) {
        let key = UtilitiesHotKey.resolve(enabled: true, parameters: parameters, fallback: .showDesktopDefault)
        #expect(key == UtilitiesHotKey(keyCode: UInt16(keyCode), modifiers: UInt64(modifiers)))
    }

    @Test("abgeschaltet oder ohne Key: nichts zu druecken", arguments: [
        (false, [65535, 103, 0]),
        (true, [65535, 65535, 0]),
        (true, [65535, -1, 0]),
    ])
    func unavailable(enabled: Bool, parameters: [Int]) {
        #expect(UtilitiesHotKey.resolve(enabled: enabled, parameters: parameters, fallback: .showDesktopDefault) == nil)
    }

    @Test("Eintrag fehlt oder ist unvollstaendig: macOS-Standard")
    func fallback() {
        #expect(UtilitiesHotKey.resolve(enabled: nil, parameters: nil, fallback: .screenshotToolbarDefault) == .screenshotToolbarDefault)
        #expect(UtilitiesHotKey.resolve(enabled: true, parameters: [65535, 103], fallback: .showDesktopDefault) == .showDesktopDefault)
    }

    @Test("Standards: F11, ⌘⇧5, ⌃⌘Q")
    func defaults() {
        #expect(UtilitiesHotKey.showDesktopDefault == UtilitiesHotKey(keyCode: 103, modifiers: 0))
        #expect(UtilitiesHotKey.screenshotToolbarDefault == UtilitiesHotKey(keyCode: 23, modifiers: 0x02_0000 | 0x10_0000))
        #expect(UtilitiesHotKey.lockScreen == UtilitiesHotKey(keyCode: 12, modifiers: 0x04_0000 | 0x10_0000))
    }
}

@Suite("Utilities-Panel: Night Shift")
struct UtilitiesNightShiftStatusTests {
    /// Am 14.09. um 16 Uhr gelesen: aus, Zeitplan 22-7 gespeichert, verfuegbar.
    static let measuredOff: [UInt8] = [
        1, 0, 0, 0, 0, 0, 0, 0, 22, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
    ]

    @Test("gemessen: aus, obwohl Byte 0 gesetzt ist")
    func measured() {
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: Self.measuredOff) == false)
    }

    @Test("Byte 1 gesetzt: an")
    func on() {
        var bytes = Self.measuredOff
        bytes[1] = 1
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: bytes) == true)
    }

    @Test("nicht verfuegbar oder Puffer zu kurz: nil")
    func unavailable() {
        var bytes = Self.measuredOff
        bytes[32] = 0
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: bytes) == nil)
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: Array(Self.measuredOff.prefix(32))) == nil)
    }

    @Test("Puffer groesser als das Struct")
    func buffer() {
        #expect(UtilitiesNightShiftStatus.bufferSize >= 40)
    }
}

@Suite("Utilities-Panel: neue Schnellschalter")
struct UtilitiesQuickToggleLookTests {
    @Test("Dunkelmodus und Night Shift leuchten, wenn an", arguments: [
        (true, true),
        (false, false),
    ])
    func stateful(on: Bool, active: Bool) {
        #expect(QuickToggles.darkMode(on: on).active == active && QuickToggles.darkMode(on: on).enabled)
        #expect(QuickToggles.nightShift(enabled: on).active == active && QuickToggles.nightShift(enabled: on).enabled)
    }

    @Test("unbekannter Zustand: sichtbar, aber nicht klickbar")
    func unknown() {
        #expect(!QuickToggles.darkMode(on: nil).enabled && !QuickToggles.darkMode(on: nil).active)
        #expect(!QuickToggles.nightShift(enabled: nil).enabled)
        #expect(QuickToggles.nightShift(enabled: nil).help == "Night Shift Not Available")
    }

    @Test("Aktionen leuchten nie und sind klickbar")
    func actions() {
        for look in [QuickToggles.screenshot, QuickToggles.colorPicker, QuickToggles.lockScreen, QuickToggles.settings] {
            #expect(!look.active && look.enabled && look.symbol != nil)
        }
    }

    @Test("Schreibtisch: ohne Kurzbefehl nicht klickbar", arguments: [
        (true, true),
        (false, false),
    ])
    func showDesktop(available: Bool, enabled: Bool) {
        #expect(QuickToggles.showDesktop(available: available).enabled == enabled)
        #expect(!QuickToggles.showDesktop(available: available).active)
    }

    @Test("zwei volle Reihen: zehn Knoepfe")
    func grid() {
        #expect(QuickToggles.columns == 5)
    }
}
