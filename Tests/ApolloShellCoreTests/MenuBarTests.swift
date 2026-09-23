import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The menu bar: reading, templates, groups, limits")
struct MenuBarTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func kinds(_ layout: BarLayout) -> [String] { layout.entries.map(\.kind.rawValue) }

    @Test("Without the section the bar is off and holds the Serpantinum template")
    func defaults() {
        let bar = ApolloMenuBar.standard
        #expect(!bar.enabled && !bar.isActive)
        #expect(kinds(bar.start) == ["dashboardButton", "workspaces", "mediaButton"])
        #expect(kinds(bar.center) == ["clock", "weather"])
        #expect(kinds(bar.end) == ["statusIcons", "battery", "power"])
    }

    @Test("A settings file without apolloMenuBar reads as the bar off")
    func oldSettings() {
        let settings = ShellSettings.load(from: Data(#"{"bar": {}}"#.utf8))
        #expect(settings.apolloMenuBar == .standard)
    }

    @Test("The Nexus item keeps its own key next to the menu bar")
    func separateFromNexusItem() throws {
        var settings = ShellSettings()
        settings.menuBar.shown = false
        settings.apolloMenuBar.enabled = true
        let json = try #require(JSONSerialization.jsonObject(with: settings.encoded()) as? [String: Any])
        #expect((json["menuBar"] as? [String: Any])?["shown"] as? Bool == false)
        #expect((json["apolloMenuBar"] as? [String: Any])?["enabled"] as? Bool == true)
        let back = ShellSettings.load(from: settings.encoded())
        #expect(!back.menuBar.shown && back.apolloMenuBar.enabled)
    }

    @Test("Switching the bar on by hand keeps the template's zones; zones in the file win")
    func partialFile() throws {
        let on = try #require(decode(ApolloMenuBar.self, #"{"enabled": true}"#))
        #expect(on.isActive)
        #expect(on.start == ApolloMenuBar.standard.start && on.end == ApolloMenuBar.standard.end)
        let emptied = try #require(decode(ApolloMenuBar.self, #"{"enabled": true, "end": []}"#))
        #expect(emptied.start == ApolloMenuBar.standard.start)
        #expect(emptied.end.entries.isEmpty)
    }

    @Test("Round trip keeps every field")
    func roundTrip() throws {
        var bar = MenuBarPreset.minimal.bar()
        bar.style = .islands
        bar.distinctGroups = true
        bar.thickness = 40
        bar.coversMenuBar = false
        bar.statusStyle = .pills
        bar.screens = .primary
        let data = try JSONEncoder().encode(bar)
        #expect(try JSONDecoder().decode(ApolloMenuBar.self, from: data) == bar)
    }

    @Test("A broken value costs only that value", arguments: [
        #"{"enabled": true, "style": "wobbly", "thickness": "thick"}"#,
        #"{"enabled": true, "start": 5, "screens": []}"#,
    ])
    func lenient(json: String) throws {
        let bar = try #require(decode(ApolloMenuBar.self, json))
        #expect(bar.enabled)
        #expect(bar.style == .fill)
        #expect(bar.thickness == ApolloMenuBar.standardThickness)
        #expect(bar.start == ApolloMenuBar.standard.start)
    }

    @Test("Thickness stays in range", arguments: [
        (0.0, 24.0), (10000.0, 64.0), (34.0, 34.0), (Double.nan, 34.0), (-Double.infinity, 34.0),
    ] as [(Double, Double)])
    func thickness(raw: Double, expected: Double) {
        var bar = ApolloMenuBar(thickness: raw)
        #expect(bar.thickness == expected)
        bar.thickness = raw
        #expect(bar.thickness == expected)
    }

    @Test("Thickness from the file is clamped too")
    func thicknessFromFile() throws {
        let bar = try #require(decode(ApolloMenuBar.self, #"{"thickness": 900}"#))
        #expect(bar.thickness == 64)
    }

    @Test("Joined entries form groups; the first entry of a zone never joins nothing")
    func groups() {
        let layout = BarLayout([
            BarEntry(.clock).joined(), BarEntry(.weather).joined(),
            BarEntry(.battery), BarEntry(.cpu).joined(), BarEntry(.power),
        ])
        let groups = ApolloMenuBar.groups(of: layout).map { $0.map(\.kind.rawValue) }
        #expect(groups == [["clock", "weather"], ["battery", "cpu"], ["power"]])
    }

    @Test("joinsPrevious is written only when set, and read back")
    func joinedCoding() throws {
        let plain = String(decoding: try JSONEncoder().encode(BarEntry(.clock)), as: UTF8.self)
        #expect(!plain.contains("joinsPrevious"))
        let joined = try JSONEncoder().encode(BarEntry(.clock).joined())
        #expect(try JSONDecoder().decode(BarEntry.self, from: joined).joinsPrevious)
    }

    @Test("Dock and status icons only once per bar, across zones")
    func uniqueAcrossZones() {
        var bar = ApolloMenuBar(start: BarLayout([BarEntry(.dock)]))
        #expect(!bar.canAdd(.dock))
        #expect(bar.canAdd(.statusIcons))
        #expect(bar.canAdd(.clock))
        bar.end = BarLayout([BarEntry(.statusIcons)])
        #expect(!bar.canAdd(.statusIcons))
    }

    @Test("Only an enabled bar with modules is active")
    func active() {
        var bar = ApolloMenuBar.standard
        #expect(!bar.isActive)
        bar.enabled = true
        #expect(bar.isActive)
        #expect(!ApolloMenuBar(enabled: true).isActive)
    }

    @Test("Zones by subscript")
    func zoneSubscript() {
        var bar = ApolloMenuBar()
        bar[.center] = BarLayout([BarEntry(.clock)])
        #expect(kinds(bar.center) == ["clock"])
        #expect(bar[.start].entries.isEmpty && !bar.isEmpty)
    }

    @Test("Every template has something in it", arguments: MenuBarPreset.allCases)
    func presets(preset: MenuBarPreset) {
        #expect(!preset.bar().isEmpty)
        #expect(preset.bar().enabled)
    }
}
