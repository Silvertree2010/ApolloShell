import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bars along the other edges: reading, templates, groups, limits")
struct EdgeBarsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func kinds(_ layout: BarLayout) -> [String] { layout.entries.map(\.kind.rawValue) }

    @Test("Without the section every bar is off, and the top one holds the Serpantinum template")
    func defaults() {
        let bars = EdgeBars()
        #expect(bars.active.isEmpty)
        #expect(!bars.top.enabled && !bars.bottom.enabled && !bars.right.enabled)
        #expect(kinds(bars.top.start) == ["dashboardButton", "workspaces", "mediaButton"])
        #expect(kinds(bars.top.center) == ["clock", "weather"])
        #expect(kinds(bars.top.end) == ["statusIcons", "battery", "power"])
    }

    @Test("A settings file without edgeBars reads as all bars off")
    func oldSettings() {
        let settings = ShellSettings.load(from: Data(#"{"bar": {}}"#.utf8))
        #expect(settings.edgeBars == EdgeBars())
    }

    @Test("Round trip keeps every field")
    func roundTrip() throws {
        var bar = EdgeBarPreset.minimal.bar(edge: .bottom)
        bar.style = .islands
        bar.distinctGroups = true
        bar.thickness = 40
        bar.coversMenuBar = false
        bar.screens = .primary
        let bars = EdgeBars(bottom: bar)
        let data = try JSONEncoder().encode(bars)
        #expect(try JSONDecoder().decode(EdgeBars.self, from: data) == bars)
    }

    @Test("A broken value costs only that value", arguments: [
        #"{"top": {"enabled": true, "style": "wobbly", "thickness": "thick"}}"#,
        #"{"top": {"enabled": true, "start": 5, "screens": []}}"#,
    ])
    func lenient(json: String) throws {
        let bars = try #require(decode(EdgeBars.self, json))
        #expect(bars.top.enabled)
        #expect(bars.top.style == .fill)
        #expect(bars.top.thickness == EdgeBar.standardThickness)
        #expect(bars.bottom == EdgeBars().bottom)
    }

    @Test("Thickness stays in range", arguments: [
        (0.0, 24.0), (10000.0, 64.0), (34.0, 34.0), (Double.nan, 34.0), (-Double.infinity, 34.0),
    ] as [(Double, Double)])
    func thickness(raw: Double, expected: Double) {
        var bar = EdgeBar(thickness: raw)
        #expect(bar.thickness == expected)
        bar.thickness = raw
        #expect(bar.thickness == expected)
    }

    @Test("Thickness from the file is clamped too")
    func thicknessFromFile() throws {
        let bar = try #require(decode(EdgeBar.self, #"{"thickness": 900}"#))
        #expect(bar.thickness == 64)
    }

    @Test("Joined entries form groups; the first entry of a zone never joins nothing")
    func groups() {
        let layout = BarLayout([
            BarEntry(.clock).joined(), BarEntry(.weather).joined(),
            BarEntry(.battery), BarEntry(.cpu).joined(), BarEntry(.power),
        ])
        let groups = EdgeBar.groups(of: layout).map { $0.map(\.kind.rawValue) }
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
        var bar = EdgeBar(start: BarLayout([BarEntry(.dock)]))
        #expect(!bar.canAdd(.dock))
        #expect(bar.canAdd(.statusIcons))
        #expect(bar.canAdd(.clock))
        bar.end = BarLayout([BarEntry(.statusIcons)])
        #expect(!bar.canAdd(.statusIcons))
    }

    @Test("Only enabled bars with modules are active")
    func active() {
        var bars = EdgeBars()
        bars.top.enabled = true
        bars.right = EdgeBar(enabled: true)
        #expect(bars.active == [.top])
    }

    @Test("Zones by subscript")
    func zoneSubscript() {
        var bar = EdgeBar()
        bar[.center] = BarLayout([BarEntry(.clock)])
        #expect(kinds(bar.center) == ["clock"])
        #expect(bar[.start].entries.isEmpty && !bar.isEmpty)
    }

    @Test("Every template has something in it", arguments: EdgeBarPreset.allCases)
    func presets(preset: EdgeBarPreset) {
        #expect(!preset.bar(edge: .top).isEmpty)
        #expect(preset.bar(edge: .top).enabled)
    }
}
