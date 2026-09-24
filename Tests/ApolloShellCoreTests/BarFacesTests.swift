import Foundation
import Testing
@testable import ApolloShellCore

/// Etappe 2 of the menu bar: status pills and the faces of Spaces and the
/// clock. All three are stored as raw values in settings.json, so the tests
/// pin the raw values and the lenient reading as much as the behaviour.
@Suite("Bar faces: status pills, Spaces and clock styles")
struct BarFacesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(value))
    }

    // MARK: Status style

    @Test("A bar without statusStyle shows icons; pills and junk read as expected")
    func statusStyleDecoding() {
        #expect(decode(ApolloMenuBar.self, #"{"enabled": true}"#)?.statusStyle == .icons)
        #expect(decode(ApolloMenuBar.self, #"{"statusStyle": "pills"}"#)?.statusStyle == .pills)
        // A newer version's style or a wrong type costs only this field.
        let odd = decode(ApolloMenuBar.self, #"{"enabled": true, "statusStyle": "neon"}"#)
        #expect(odd?.statusStyle == .icons && odd?.enabled == true)
        #expect(decode(ApolloMenuBar.self, #"{"statusStyle": 3}"#)?.statusStyle == .icons)
    }

    @Test("statusStyle survives a round trip and keeps its raw values")
    func statusStyleRoundTrip() throws {
        var bar = MenuBarPreset.serpantinum.bar()
        bar.statusStyle = .pills
        #expect(try roundTrip(bar) == bar)
        #expect(BarStatusStyle.allCases.map(\.rawValue) == ["icons", "pills"])
    }

    @Test("Pill texts: a word for the radios, the level for the battery")
    func pillTexts() {
        #expect(StatusGlyphs.wifiPillText(powerOn: true) == "Wi-Fi")
        #expect(StatusGlyphs.wifiPillText(powerOn: false) == "Off")
        #expect(StatusGlyphs.bluetoothPillText(on: true) == "On")
        #expect(StatusGlyphs.bluetoothPillText(on: nil) == "On")
        #expect(StatusGlyphs.bluetoothPillText(on: false) == "Off")
        #expect(StatusGlyphs.batteryPillText(BatteryState(level: 76, charging: false, onAC: false)) == "76%")
        #expect(StatusGlyphs.batteryPillText(BatteryState(level: 140, charging: true, onAC: true)) == "100%")
        #expect(StatusGlyphs.batteryPillText(nil) == nil)
    }

    // MARK: Spaces

    @Test("Spaces faces: the old raw values stay, the new ones read, junk is dots")
    func spacesStyles() throws {
        #expect(BarWorkspacesOptions.Style.allCases.map(\.rawValue) == ["dots", "numbers", "pills", "bars"])
        #expect(decode(BarWorkspacesOptions.self, #"{"style": "pills"}"#)?.style == .pills)
        #expect(decode(BarWorkspacesOptions.self, #"{"style": "bars"}"#)?.style == .bars)
        #expect(decode(BarWorkspacesOptions.self, #"{"style": "numbers"}"#)?.style == .numbers)
        #expect(decode(BarWorkspacesOptions.self, #"{"style": "blobs"}"#)?.style == .dots)
        #expect(decode(BarWorkspacesOptions.self, "{}")?.style == .dots)
        let pills = BarWorkspacesOptions(style: .bars)
        #expect(try roundTrip(pills) == pills)
    }

    // MARK: Clock

    @Test("A clock saved before faces is automatic, and junk is too")
    func clockStyleDecoding() {
        #expect(BarClockOptions.Style.allCases.map(\.rawValue) == ["line", "stacked", "badge"])
        let old = decode(BarClockOptions.self, #"{"showIcon": false, "showDate": true}"#)
        #expect(old == BarClockOptions(showIcon: false, showDate: true, style: nil))
        #expect(decode(BarClockOptions.self, #"{"style": "badge"}"#)?.style == .badge)
        let odd = decode(BarClockOptions.self, #"{"showDate": true, "style": "flip"}"#)
        #expect(odd?.style == nil && odd?.showDate == true)
    }

    @Test("Automatic writes no style key, so an older version reads the file unchanged")
    func automaticIsNotWritten() throws {
        let data = try JSONEncoder().encode(BarClockOptions())
        #expect(!String(decoding: data, as: UTF8.self).contains("style"))
        let badge = BarClockOptions(style: .badge)
        #expect(try roundTrip(badge) == badge)
    }

    @Test("Automatic is stacked across a vertical bar and a line along a horizontal one; a line never goes vertical")
    func clockResolution() {
        #expect(BarClockOptions().resolvedStyle(horizontal: false) == .stacked)
        #expect(BarClockOptions().resolvedStyle(horizontal: true) == .line)
        #expect(BarClockOptions(style: .line).resolvedStyle(horizontal: false) == .stacked)
        #expect(BarClockOptions(style: .line).resolvedStyle(horizontal: true) == .line)
        #expect(BarClockOptions(style: .stacked).resolvedStyle(horizontal: true) == .stacked)
        #expect(BarClockOptions(style: .badge).resolvedStyle(horizontal: false) == .badge)
        #expect(BarClockOptions(style: .badge).resolvedStyle(horizontal: true) == .badge)
    }

    @Test("The clock inside a bar module keeps its style through settings.json")
    func clockInLayout() throws {
        let layout = BarLayout([BarEntry(module: .clock(.init(showIcon: false, showDate: true, style: .badge))),
                                BarEntry(module: .workspaces(.init(style: .pills)))])
        #expect(try roundTrip(layout) == layout)
    }
}
