import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Leiste als Baukasten: lesen, Migration, Vorlagen, Aendern, Hoehe verteilen")
struct BarLayoutTests {
    private func layout(_ json: String) -> BarLayout? {
        try? JSONDecoder().decode(BarLayout.self, from: Data(json.utf8))
    }

    private func layout(kinds: [String]) -> BarLayout {
        BarLayout(kinds.compactMap(BarModuleKind.init(rawValue:)).map { BarEntry($0) })
    }

    private func kinds(_ layout: BarLayout?) -> [String] {
        layout?.entries.map(\.kind.rawValue) ?? ["<nicht lesbar>"]
    }

    // MARK: Lesen und Schreiben

    @Test("unbekannte Arten und Nicht-Objekte fallen weg, der Rest bleibt", arguments: [
        (#"[{"kind":"clock"},{"kind":"hologram"},{"kind":"power"}]"#, ["clock", "power"]),
        (#"[5, null, "dock", {"kind":"dock"}]"#, ["dock"]),
        (#"[{"id":"a","kind":"divider"},{"kind":7},{},{"id":"b"}]"#, ["divider"]),
        (#"[{"kind":"weather","future":{"x":1}},{"kind":"Clock"}]"#, ["weather"]),
        ("[]", []),
    ])
    func skipsUnknown(json: String, expected: [String]) {
        #expect(kinds(layout(json)) == expected)
    }

    @Test("kaputte Optionen: Vorgaben, lesbare Felder bleiben", arguments: [
        (#"[{"kind":"clock","options":{"showDate":true,"showSeconds":true}}]"#, BarModule.clock(.init(showDate: true))),
        (#"[{"kind":"gap","options":{"height":"hoch"}}]"#, BarModule.gap(.init())),
        (#"[{"kind":"gap","options":{"height":5000}}]"#, BarModule.gap(.init(height: 96))),
        (#"[{"kind":"dock","options":{"iconSize":"riesig","showRunning":false}}]"#, BarModule.dock(.init(showRunning: false))),
        (#"[{"kind":"workspaces","options":[]}]"#, BarModule.workspaces(.init())),
        (#"[{"kind":"workspaces","options":{"style":"numbers"}}]"#, BarModule.workspaces(.init(style: .numbers))),
        (#"[{"kind":"appButton","options":{"bundleID":"com.example.editor"}}]"#, BarModule.appButton(.init(bundleID: "com.example.editor"))),
        (#"[{"kind":"statusIcons","options":{"showWifi":false,"showBattery":"nein"}}]"#, BarModule.statusIcons(.init(showWifi: false))),
        (#"[{"kind":"cpu","options":{"style":"percent"}}]"#, BarModule.cpu(.init(style: .percent))),
        (#"[{"kind":"power","options":{"confirm":true}}]"#, BarModule.power),
    ])
    func lenientOptions(json: String, expected: BarModule) {
        #expect(layout(json)?.entries.first?.module == expected)
    }

    @Test("Kennungen eindeutig, Dock und Statussymbole hoechstens einmal", arguments: [
        (#"[{"kind":"divider"},{"kind":"divider"},{"id":"divider-2","kind":"divider"}]"#, ["divider", "divider-3", "divider-2"]),
        (#"[{"id":"x","kind":"clock"},{"id":"x","kind":"power"}]"#, ["x", "power"]),
        (#"[{"id":"","kind":"spacer"},{"id":5,"kind":"gap"}]"#, ["spacer", "gap"]),
        (#"[{"id":"a","kind":"dock"},{"id":"b","kind":"dock"},{"kind":"statusIcons"},{"kind":"statusIcons"}]"#, ["a", "statusIcons"]),
    ])
    func normalizedIDs(json: String, expected: [String]) {
        #expect(layout(json)?.entries.map(\.id) == expected)
    }

    @Test("jede Vorlage uebersteht Schreiben und Lesen", arguments: BarPreset.allCases)
    func presetRoundTrip(preset: BarPreset) throws {
        let data = try JSONEncoder().encode(preset.layout)
        #expect(try JSONDecoder().decode(BarLayout.self, from: data) == preset.layout)
    }

    @Test("jede Art mit Vorgaben uebersteht Schreiben und Lesen", arguments: BarModuleKind.allCases)
    func kindRoundTrip(kind: BarModuleKind) throws {
        let layout = BarLayout([BarEntry(kind)])
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(BarLayout.self, from: data) == layout)
        // Optionen stehen nur in der Datei, wenn es welche gibt.
        #expect(String(decoding: data, as: UTF8.self).contains("\"options\"") == BarModule(kind).hasOptions)
    }

    @Test("Art, Name, Beschreibung und Symbol sind vollstaendig", arguments: BarModuleKind.allCases)
    func kindMetadata(kind: BarModuleKind) {
        #expect(BarModule(kind).kind == kind)
        #expect(!kind.title.isEmpty && !kind.summary.isEmpty && !kind.symbol.isEmpty)
    }

    // MARK: Migration

    @Test("ohne layout: aus den alten Schaltern, mit layout: nur das", arguments: [
        ("{}", ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
        (#"{"bar":{}}"#, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
        (#"{"bar":{"showDock":false}}"#, ["dashboardButton", "workspaces", "spacer", "clock", "utilitiesButton", "statusIcons", "power"]),
        (#"{"bar":{"showWorkspaces":false,"showClock":false,"showStatusIcons":false}}"#, ["dashboardButton", "dock", "utilitiesButton", "power"]),
        (#"{"bar":{"layout":[],"showDock":false}}"#, []),
        (#"{"bar":{"layout":5,"showClock":false}}"#, ["dashboardButton", "workspaces", "dock", "utilitiesButton", "statusIcons", "power"]),
        (#"{"bar":{"layout":[{"kind":"power"}],"showClock":false}}"#, ["power"]),
    ])
    func migration(json: String, expected: [String]) {
        #expect(kinds(ShellSettings.load(from: Data(json.utf8)).bar.layout) == expected)
    }

    @Test("die alten Uhr-Optionen wandern mit", arguments: [
        (#"{"bar":{"clock":{"showIcon":false,"showDate":true}}}"#, BarClockOptions(showIcon: false, showDate: true)),
        (#"{"bar":{"clock":{"showDate":true}}}"#, BarClockOptions(showIcon: true, showDate: true)),
        (#"{"bar":{"clock":"kaputt"}}"#, BarClockOptions()),
    ])
    func migratedClock(json: String, expected: BarClockOptions) {
        let layout = ShellSettings.load(from: Data(json.utf8)).bar.layout
        #expect(layout[id: "clock"]?.module.clock == expected)
    }

    @Test("Vorgabe = Caelestia = every alten Schalter an")
    func defaultIsCaelestia() {
        #expect(ShellSettings().bar.layout == BarPreset.caelestia.layout)
        #expect(ShellSettings.load(from: nil).bar.layout == BarLayout.migrated())
    }

    // MARK: Vorlagen

    @Test("Vorlagen sind Daten mit fester Reihenfolge", arguments: [
        (BarPreset.caelestia, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
        (BarPreset.minimal, ["workspaces", "spacer", "clock", "power"]),
        (BarPreset.dockOnly, ["dock"]),
        (BarPreset.everything, ["dashboardButton", "mediaButton", "workspaces", "divider", "dock", "divider", "appButton",
                                "weather", "cpu", "battery", "clock", "utilitiesButton", "statusIcons", "power"]),
    ])
    func presetOrder(preset: BarPreset, expected: [String]) {
        #expect(kinds(preset.layout) == expected)
    }

    @Test("Vorlagen sind gueltig", arguments: BarPreset.allCases)
    func presetValid(preset: BarPreset) {
        let entries = preset.layout.entries
        #expect(!preset.title.isEmpty && !preset.summary.isEmpty && !entries.isEmpty)
        #expect(Set(entries.map(\.id)).count == entries.count)
        #expect(!entries.contains { $0.id.isEmpty })
        for kind in BarModuleKind.allCases where kind.isUnique {
            #expect(entries.filter { $0.kind == kind }.count <= 1)
        }
        // Schon in Normalform: Lesen aendert nichts.
        #expect(BarLayout(entries) == preset.layout)
        // Jede Vorlage haelt ihre untere Gruppe unten (Dock oder Abstand).
        #expect(preset.layout.flexibleCount == 1)
    }

    @Test("App-Knoepfe in Vorlagen zeigen nur auf mitgelieferte Apple-Apps", arguments: BarPreset.allCases)
    func presetAppButtons(preset: BarPreset) {
        for entry in preset.layout.entries {
            if let app = entry.module.appButton { #expect(app.bundleID.hasPrefix("com.apple.")) }
        }
    }

    // MARK: Aendern

    @Test("hinzufuegen: unter den letzten flexiblen, sonst vor Ausschalten, sonst ans Ende", arguments: [
        (["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"], BarModuleKind.battery,
         ["dashboardButton", "workspaces", "dock", "battery", "clock", "utilitiesButton", "statusIcons", "power"]),
        (["workspaces", "spacer", "clock", "power"], BarModuleKind.cpu, ["workspaces", "spacer", "cpu", "clock", "power"]),
        (["dock", "clock", "spacer", "power"], BarModuleKind.divider, ["dock", "clock", "spacer", "divider", "power"]),
        (["clock", "power"], BarModuleKind.gap, ["clock", "gap", "power"]),
        (["clock"], BarModuleKind.divider, ["clock", "divider"]),
        ([], BarModuleKind.clock, ["clock"]),
        (["dock"], BarModuleKind.power, ["dock", "power"]),
    ])
    func add(start: [String], kind: BarModuleKind, expected: [String]) {
        var layout = layout(kinds: start)
        #expect(layout.add(kind) != nil)
        #expect(kinds(layout) == expected)
    }

    @Test("ein zweites Dock oder zweite Statussymbole gibt es nicht", arguments: [
        BarModuleKind.dock, BarModuleKind.statusIcons,
    ])
    func addUniqueRefused(kind: BarModuleKind) {
        var layout = BarPreset.caelestia.layout
        #expect(!layout.canAdd(kind))
        #expect(layout.add(kind) == nil)
        #expect(layout == BarPreset.caelestia.layout)
    }

    @Test("gleiche Art mehrmals: eigene Kennungen", arguments: [
        (BarModuleKind.divider, ["divider", "divider-2", "divider-3"]),
        (BarModuleKind.appButton, ["appButton", "appButton-2", "appButton-3"]),
    ])
    func addIDs(kind: BarModuleKind, expected: [String]) {
        var layout = BarLayout()
        let ids = (0..<3).compactMap { _ in layout.add(kind) }
        #expect(ids == expected)
    }

    @Test("hinzufuegen an einer bestimmten Stelle, ausserhalb begrenzt", arguments: [
        (0, ["gap", "clock", "power"]), (1, ["clock", "gap", "power"]), (99, ["clock", "power", "gap"]), (-3, ["gap", "clock", "power"]),
    ])
    func addAt(index: Int, expected: [String]) {
        var layout = layout(kinds: ["clock", "power"])
        layout.add(.gap, at: index)
        #expect(kinds(layout) == expected)
    }

    @Test("ziehen wie onMove (Ziel vor dem Verschieben gezaehlt)", arguments: [
        ([6], 0, ["power", "dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons"]),
        ([0], 7, ["workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power", "dashboardButton"]),
        ([3], 2, ["dashboardButton", "workspaces", "clock", "dock", "utilitiesButton", "statusIcons", "power"]),
        ([1, 2], 7, ["dashboardButton", "clock", "utilitiesButton", "statusIcons", "power", "workspaces", "dock"]),
        ([9], 0, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
    ])
    func moveOffsets(source: [Int], destination: Int, expected: [String]) {
        var layout = BarPreset.caelestia.layout
        layout.move(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(kinds(layout) == expected)
    }

    @Test("nach oben und unten (Kontextmenue), am Rand nichts", arguments: [
        ("clock", -1, ["dashboardButton", "workspaces", "clock", "dock", "utilitiesButton", "statusIcons", "power"]),
        ("clock", 1, ["dashboardButton", "workspaces", "dock", "utilitiesButton", "clock", "statusIcons", "power"]),
        ("dashboardButton", -1, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
        ("power", 1, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
        ("gibtsnicht", 1, ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
    ])
    func moveStep(id: String, step: Int, expected: [String]) {
        var layout = BarPreset.caelestia.layout
        layout.move(id: id, by: step)
        #expect(kinds(layout) == expected)
    }

    @Test("entfernen", arguments: [
        ("dock", ["dashboardButton", "workspaces", "clock", "utilitiesButton", "statusIcons", "power"]),
        ("gibtsnicht", ["dashboardButton", "workspaces", "dock", "clock", "utilitiesButton", "statusIcons", "power"]),
    ])
    func remove(id: String, expected: [String]) {
        var layout = BarPreset.caelestia.layout
        layout.remove(id: id)
        #expect(kinds(layout) == expected)
        // Nach dem Entfernen darf das Dock wieder hinein.
        #expect(layout.canAdd(.dock) == !layout.contains(.dock))
    }

    @Test("Optionen aendern nur bei gleicher Art", arguments: [
        ("clock", BarModule.clock(.init(showDate: true)), BarModule.clock(.init(showDate: true))),
        ("clock", BarModule.dock(.init(showRunning: false)), BarModule.clock(.init())),
        ("dock", BarModule.dock(.init(iconSize: .large)), BarModule.dock(.init(iconSize: .large))),
    ])
    func update(id: String, module: BarModule, expected: BarModule) {
        var layout = BarPreset.caelestia.layout
        layout.update(id: id, to: module)
        #expect(layout[id: id]?.module == expected)
        #expect(layout.entries.count == BarPreset.caelestia.layout.entries.count)
    }

    @Test("fester Abstand bleibt im Bereich", arguments: [
        (-5.0, 4.0), (16.0, 16.0), (500.0, 96.0), (Double.nan, 16.0), (Double.infinity, 16.0),
    ])
    func gapClamp(value: Double, expected: Double) {
        #expect(BarGapOptions(height: value).height == expected)
        var options = BarGapOptions()
        options.height = value
        #expect(options.height == expected)
    }

    // MARK: Hoehe verteilen

    @Test("feste Hoehe, Rest gleichmaessig an die flexiblen, nie negativ", arguments: [
        ([32, nil, 32] as [Double?], 200.0, 8.0, [[0, 32], [40, 120], [168, 32]]),
        ([32, nil, nil, 32] as [Double?], 200.0, 8.0, [[0, 32], [40, 56], [104, 56], [168, 32]]),
        ([32, 32] as [Double?], 200.0, 8.0, [[0, 32], [40, 32]]),
        ([100, nil, 100] as [Double?], 150.0, 10.0, [[0, 100], [110, 0], [120, 100]]),
        ([nil] as [Double?], 300.0, 8.0, [[0, 300]]),
        ([] as [Double?], 100.0, 8.0, []),
    ])
    func flexSlots(heights: [Double?], available: Double, spacing: Double, expected: [[Double]]) {
        let slots = BarFlex.slots(available: available, heights: heights, spacing: spacing)
        #expect(slots.map { [$0.y, $0.height] } == expected)
    }

    @Test("Dock und Abstand zaehlen als flexibel, sonst nichts", arguments: BarModuleKind.allCases)
    func flexibleKinds(kind: BarModuleKind) {
        #expect(kind.isFlexible == (kind == .dock || kind == .spacer))
    }
}
