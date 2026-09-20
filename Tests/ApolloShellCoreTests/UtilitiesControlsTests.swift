import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The utilities panel: the color picker")
struct UtilitiesColorHexTests {
    @Test("sRGB parts to #RRGGBB, rounded, in capitals", arguments: [
        (1.0, 0.584, 0.0, "#FF9500"),
        (0.0, 0.0, 0.0, "#000000"),
        (1.0, 1.0, 1.0, "#FFFFFF"),
        (0.1, 0.2, 0.3, "#1A334D"),
    ])
    func hex(red: Double, green: Double, blue: Double, expected: String) {
        #expect(UtilitiesColorHex.hex(red: red, green: green, blue: blue) == expected)
    }

    @Test("outside 0...1 (extended sRGB) it is cut off", arguments: [
        (1.2, -0.1, 0.5, "#FF0080"),
        (-3.0, 7.0, 1.0001, "#00FFFF"),
    ])
    func clamped(red: Double, green: Double, blue: Double, expected: String) {
        #expect(UtilitiesColorHex.hex(red: red, green: green, blue: blue) == expected)
    }

    @Test("no number: 00 instead of a crash")
    func notANumber() {
        #expect(UtilitiesColorHex.hex(red: .nan, green: .infinity, blue: 1) == "#0000FF")
    }

    @Test("The toast: a fixed title, the hex value as the text")
    func toast() {
        let content = ToastText.colorCopied("#FF9500")
        #expect(content.title == "Color Copied" && content.message == "#FF9500" && content.symbol == "eyedropper")
    }
}

@Suite("The utilities panel: audio devices")
struct UtilitiesAudioDevicesTests {
    /// The devices the way they were read on a MacBook on 14.09., plus a hidden
    /// aggregate and a device without the default right.
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

    @Test("Outputs: only with an output stream, selectable, not hidden - by name", arguments: [
        (UtilitiesAudioScope.output, [107 as UInt32, 61, 93]),
        (UtilitiesAudioScope.input, [113 as UInt32, 61, 105, 100]),
    ])
    func filter(scope: UtilitiesAudioScope, ids: [UInt32]) {
        #expect(UtilitiesAudioDevices.devices(Self.measured, for: scope).map(\.id) == ids)
    }

    @Test("The same names (AirPods) are told apart by the stream count, not by the name")
    func airPodsSplit() {
        let outputs = UtilitiesAudioDevices.devices(Self.measured, for: .output).filter { $0.name == "AirPods Pro" }
        let inputs = UtilitiesAudioDevices.devices(Self.measured, for: .input).filter { $0.name == "AirPods Pro" }
        #expect(outputs.map(\.id) == [107] && inputs.map(\.id) == [113])
    }

    @Test("The label: the name of the default device, even when it is hidden", arguments: [
        (107 as UInt32?, "AirPods Pro"),
        (200 as UInt32?, "CADefaultDeviceAggregate"),
        (999 as UInt32?, "No Device"),
        (nil as UInt32?, "No Device"),
    ])
    func label(id: UInt32?, expected: String) {
        #expect(UtilitiesAudioDevices.label(defaultID: id, in: Self.measured) == expected)
    }

    @Test("empty name: as with the toasts, 'Unknown Device'")
    func emptyName() {
        let blank = UtilitiesAudioDevice(id: 1, name: "  ", outputStreams: 1, inputStreams: 0,
                                         canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false)
        #expect(UtilitiesAudioDevices.label(defaultID: 1, in: [blank]) == "Unknown Device")
    }

    @Test("Level text: percent with a space, muted as a word", arguments: [
        (Float(0.45), false, "45 %"),
        (Float(0.45), true, "Muted"),
        (Float(1.2), false, "100 %"),
        (Float(0), false, "0 %"),
    ])
    func level(volume: Float, muted: Bool, expected: String) {
        #expect(UtilitiesAudioText.level(volume: volume, muted: muted) == expected)
    }
}

@Suite("The utilities panel: keyboard shortcuts out of symbolichotkeys")
struct UtilitiesHotKeyTests {
    @Test("The key code and the mask as stored; the mask only modifier bits", arguments: [
        ([65535, 103, 0], 103, 0),                      // Schreibtisch anzeigen, gemessen: F11 ohne Fn
        ([53, 23, 1_179_648], 23, 0x12_0000),           // ⌘⇧5
        ([65535, 125, 0x84_0000], 125, 0x84_0000),      // ⌃↓ mit Fn, wie echte Pfeiltasten
        ([113, 12, 0x114_0000], 12, 0x14_0000),         // Bit ausserhalb der Maske faellt weg
    ])
    func resolved(parameters: [Int], keyCode: Int, modifiers: Int) {
        let key = UtilitiesHotKey.resolve(enabled: true, parameters: parameters, fallback: .showDesktopDefault)
        #expect(key == UtilitiesHotKey(keyCode: UInt16(keyCode), modifiers: UInt64(modifiers)))
    }

    @Test("switched off or without a key: nothing to press", arguments: [
        (false, [65535, 103, 0]),
        (true, [65535, 65535, 0]),
        (true, [65535, -1, 0]),
    ])
    func unavailable(enabled: Bool, parameters: [Int]) {
        #expect(UtilitiesHotKey.resolve(enabled: enabled, parameters: parameters, fallback: .showDesktopDefault) == nil)
    }

    @Test("the entry is missing or incomplete: the macOS default")
    func fallback() {
        #expect(UtilitiesHotKey.resolve(enabled: nil, parameters: nil, fallback: .screenshotToolbarDefault) == .screenshotToolbarDefault)
        #expect(UtilitiesHotKey.resolve(enabled: true, parameters: [65535, 103], fallback: .showDesktopDefault) == .showDesktopDefault)
    }

    @Test("The defaults: F11, ⌘⇧5, ⌃⌘Q")
    func defaults() {
        #expect(UtilitiesHotKey.showDesktopDefault == UtilitiesHotKey(keyCode: 103, modifiers: 0))
        #expect(UtilitiesHotKey.screenshotToolbarDefault == UtilitiesHotKey(keyCode: 23, modifiers: 0x02_0000 | 0x10_0000))
        #expect(UtilitiesHotKey.lockScreen == UtilitiesHotKey(keyCode: 12, modifiers: 0x04_0000 | 0x10_0000))
    }
}

@Suite("The utilities panel: Night Shift")
struct UtilitiesNightShiftStatusTests {
    /// Read on 14.09. at 16:00: off, a 22-7 schedule saved, available.
    static let measuredOff: [UInt8] = [
        1, 0, 0, 0, 0, 0, 0, 0, 22, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0,
    ]

    @Test("measured: off, although byte 0 is set")
    func measured() {
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: Self.measuredOff) == false)
    }

    @Test("byte 1 set: on")
    func on() {
        var bytes = Self.measuredOff
        bytes[1] = 1
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: bytes) == true)
    }

    @Test("not available or the buffer too short: nil")
    func unavailable() {
        var bytes = Self.measuredOff
        bytes[32] = 0
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: bytes) == nil)
        #expect(UtilitiesNightShiftStatus.enabled(fromStatus: Array(Self.measuredOff.prefix(32))) == nil)
    }

    @Test("a buffer bigger than the struct")
    func buffer() {
        #expect(UtilitiesNightShiftStatus.bufferSize >= 40)
    }
}

@Suite("The utilities panel: the new quick toggles")
struct UtilitiesQuickToggleLookTests {
    @Test("Dark mode and Night Shift light up when they are on", arguments: [
        (true, true),
        (false, false),
    ])
    func stateful(on: Bool, active: Bool) {
        #expect(QuickToggles.darkMode(on: on).active == active && QuickToggles.darkMode(on: on).enabled)
        #expect(QuickToggles.nightShift(enabled: on).active == active && QuickToggles.nightShift(enabled: on).enabled)
    }

    @Test("an unknown state: visible, but not clickable")
    func unknown() {
        #expect(!QuickToggles.darkMode(on: nil).enabled && !QuickToggles.darkMode(on: nil).active)
        #expect(!QuickToggles.nightShift(enabled: nil).enabled)
        #expect(QuickToggles.nightShift(enabled: nil).help == "Night Shift Not Available")
    }

    @Test("Actions never light up and are clickable")
    func actions() {
        for look in [QuickToggles.screenshot, QuickToggles.colorPicker, QuickToggles.lockScreen, QuickToggles.settings] {
            #expect(!look.active && look.enabled && look.symbol != nil)
        }
    }

    @Test("Desktop: without a shortcut not clickable", arguments: [
        (true, true),
        (false, false),
    ])
    func showDesktop(available: Bool, enabled: Bool) {
        #expect(QuickToggles.showDesktop(available: available).enabled == enabled)
        #expect(!QuickToggles.showDesktop(available: available).active)
    }

    @Test("two full rows: ten buttons")
    func grid() {
        #expect(QuickToggles.columns == 5)
    }
}
