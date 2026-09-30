import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Übernahme 0.2-alt: apolloMenuBar")
struct LegacyImportMenuBarTests {
    static let json = """
    {"apolloMenuBar": {
        "enabled": true, "style": "islands", "statusStyle": "pills", "distinctGroups": true,
        "thickness": 99, "coversMenuBar": false, "hideAppleMenuBar": true,
        "screens": {"mode": "primary"},
        "start": [{"id": "appleMenu", "kind": "appleMenu"}, {"id": "appMenu", "kind": "appMenu"}],
        "center": [{"id": "clock", "kind": "clock", "options": {"showIcon": true, "showDate": false}},
                   {"id": "weather", "kind": "weather", "joinsPrevious": true},
                   {"id": "t", "kind": "timer"}],
        "end": [{"id": "workspaces", "kind": "workspaces", "options": {"style": "pills"}}, {"kind": "statusItems"}]
    }}
    """

    func run(_ text: String) -> LegacyImportResult {
        LegacyImport.convert(settings: text, weather: nil, launcherOnly: false, makeID: { "id" })
    }

    @Test("Alle Felder wandern in die Variablen der Menüleiste")
    func fields() {
        let r = run(Self.json)
        #expect(r.state["menubar-enabled"] == .bool(true))
        #expect(r.state["menubar-style"] == .string("islands"))
        #expect(r.state["menubar-status-style"] == .string("pills"))
        #expect(r.state["menubar-distinct"] == .bool(true))
        #expect(r.state["menubar-thickness"] == .number(64))
        #expect(r.state["menubar-covers"] == .bool(false))
        #expect(r.state["menubar-hide-apple"] == .bool(true))
        #expect(r.state["menubar-screens"] == .string("main"))
    }

    @Test("Zonen tragen neue Namen, Optionen und das Verbinden mit dem Vorgänger")
    func zones() {
        let r = run(Self.json)
        #expect(LegacyFixtures.ids(r.state["menubar-start"]) == ["apple-menu", "app-menus"])
        let c = LegacyFixtures.list(r.state["menubar-center"])
        #expect(c.count == 2)
        #expect(c[0]["show-icon"] == .bool(true))
        #expect(c[0]["show-date"] == .bool(false))
        #expect(c[1]["joins"] == .bool(true))
        #expect(c[0]["joins"] == nil)
        let e = LegacyFixtures.list(r.state["menubar-end"])
        #expect(e[0]["kind"] == .string("spaces"))
        #expect(e[0]["style"] == .string("pills"))
        #expect(e[1]["kind"] == .string("status-items"))
        #expect(LegacyFixtures.mentions(r, "unknown kind 'timer'"))
    }

    @Test("Ohne apolloMenuBar bleibt die Menüleiste unberührt")
    func absent() {
        let r = run("{\"bar\": {}}")
        #expect(r.state.keys.filter { $0.hasPrefix("menubar-") }.isEmpty)
    }

    @Test("Kaputte Werte werden gemeldet und übersprungen")
    func broken() {
        let r = run("{\"apolloMenuBar\": {\"style\": \"x\", \"thickness\": \"a\", \"start\": 3}}")
        #expect(r.state["menubar-style"] == nil)
        #expect(r.state["menubar-thickness"] == nil)
        #expect(r.state["menubar-start"] == nil)
        #expect(r.diagnostics.count == 3)
    }
}
