import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Utilities-Panel als Baukasten: lesen, Vorlagen, Aendern, Hoehe")
struct UtilitiesLayoutTests {
    private func layout(_ json: String) -> UtilitiesLayout? {
        try? JSONDecoder().decode(UtilitiesLayout.self, from: Data(json.utf8))
    }

    private func toggleKinds(_ layout: UtilitiesLayout?) -> [String] {
        layout?.toggles.map(\.kind.rawValue) ?? ["<nicht lesbar>"]
    }

    private func cards(_ layout: UtilitiesLayout?) -> [String] {
        layout?.cards.map { "\($0.kind.rawValue)\($0.enabled ? "" : "-aus")" } ?? ["<nicht lesbar>"]
    }

    private static let standardKinds = ["wifi", "microphone", "bluetooth", "darkMode", "nightShift",
                                        "screenshot", "showDesktop", "colorPicker", "lockScreen", "settings"]

    // MARK: Migration und Vorgabe

    @Test("ohne Abschnitt oder unlesbar: das feste Panel von vorher", arguments: [
        "{}", #"{"utilities":5}"#, #"{"utilities":{}}"#, #"{"utilities":{"layout":"kaputt"}}"#, #"{"utilities":{"layout":{}}}"#,
    ])
    func migration(json: String) {
        let layout = ShellSettings.load(from: Data(json.utf8)).utilities.layout
        #expect(layout == UtilitiesPreset.standard.layout)
        #expect(toggleKinds(layout) == Self.standardKinds)
        #expect(cards(layout) == ["keepAwake", "audio", "quickToggles"])
        #expect(layout.toggles.map(\.id) == Self.standardKinds)
    }

    @Test("Vorgabe = Standard = feste Hoehe 426 wie vorher gemessen")
    func standardIsToday() {
        #expect(ShellSettings().utilities.layout == UtilitiesLayout())
        #expect(UtilitiesLayout().panelHeight == 426)
        #expect(UtilitiesLayout().toggleRows.map(\.count) == [5, 5])
    }

    // MARK: Lesen

    @Test("unbekannte Eintraege fallen weg, der Rest bleibt", arguments: [
        (#"{"quickToggles":[{"kind":"wifi"},{"kind":"hologram"},{"kind":"lockScreen"}]}"#, ["wifi", "lockScreen"]),
        (#"{"quickToggles":[5, null, "wifi", {"kind":"settings"}]}"#, ["settings"]),
        (#"{"quickToggles":[{"kind":"Wifi"},{},{"id":"x"}]}"#, []),
        (#"{"quickToggles":[]}"#, []),
        (#"{"quickToggles":"alle"}"#, ["wifi", "microphone", "bluetooth", "darkMode", "nightShift",
                                         "screenshot", "showDesktop", "colorPicker", "lockScreen", "settings"]),
    ])
    func skipsUnknownToggles(json: String, expected: [String]) {
        #expect(toggleKinds(layout(json)) == expected)
    }

    @Test("Karten: unbekannte weg, doppelte weg, fehlende eingeschaltet ans Ende", arguments: [
        (#"{"cards":[{"kind":"audio","enabled":false},{"kind":"keepAwake"}]}"#, ["audio-aus", "keepAwake", "quickToggles"]),
        (#"{"cards":[{"kind":"quickToggles"},{"kind":"quickToggles","enabled":false},{"kind":"radio"}]}"#,
         ["quickToggles", "keepAwake", "audio"]),
        (#"{"cards":[{"kind":"audio","enabled":"nein"}]}"#, ["audio", "keepAwake", "quickToggles"]),
        (#"{"cards":7}"#, ["keepAwake", "audio", "quickToggles"]),
        (#"{"cards":[]}"#, ["keepAwake", "audio", "quickToggles"]),
    ])
    func cardsNormalized(json: String, expected: [String]) {
        #expect(cards(layout(json)) == expected)
    }

    @Test("kaputte Optionen: Vorgaben, lesbare Felder bleiben", arguments: [
        (#"{"quickToggles":[{"kind":"openApp","options":{"bundleID":"com.example.editor","title":5}}]}"#,
         UtilitiesToggle.openApp(.init(bundleID: "com.example.editor"))),
        (#"{"quickToggles":[{"kind":"openLink","options":[]}]}"#, UtilitiesToggle.openLink(.init())),
        (#"{"quickToggles":[{"kind":"openLink","options":{"url":"example.com","symbol":"globe"}}]}"#,
         UtilitiesToggle.openLink(.init(url: "example.com", symbol: "globe"))),
        (#"{"quickToggles":[{"kind":"runShortcut","options":{"name":"Fokus","identifier":null}}]}"#,
         UtilitiesToggle.runShortcut(.init(name: "Fokus"))),
        (#"{"quickToggles":[{"kind":"hideApps","options":{"keepFrontmost":true}}]}"#,
         UtilitiesToggle.hideApps(.init(keepFrontmost: true))),
        (#"{"quickToggles":[{"kind":"wifi","options":{"x":1}}]}"#, UtilitiesToggle.wifi),
    ])
    func lenientOptions(json: String, expected: UtilitiesToggle) {
        #expect(layout(json)?.toggles.first?.toggle == expected)
    }

    @Test("Kennungen eindeutig, feste Knoepfe hoechstens einmal", arguments: [
        (#"{"quickToggles":[{"kind":"wifi"},{"kind":"wifi"},{"kind":"settings"}]}"#, ["wifi", "settings"]),
        (#"{"quickToggles":[{"kind":"openApp"},{"kind":"openApp"},{"id":"openApp-2","kind":"openApp"}]}"#,
         ["openApp", "openApp-3", "openApp-2"]),
        (#"{"quickToggles":[{"id":"x","kind":"openLink"},{"id":"x","kind":"runShortcut"}]}"#, ["x", "runShortcut"]),
        (#"{"quickToggles":[{"id":"","kind":"lockScreen"},{"id":5,"kind":"openLink"}]}"#, ["lockScreen", "openLink"]),
    ])
    func normalizedIDs(json: String, expected: [String]) {
        #expect(layout(json)?.toggles.map(\.id) == expected)
    }

    @Test("jede Art mit Vorgaben uebersteht Schreiben und Lesen", arguments: UtilitiesToggleKind.allCases)
    func kindRoundTrip(kind: UtilitiesToggleKind) throws {
        let layout = UtilitiesLayout(toggles: [UtilitiesToggleEntry(kind)])
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(UtilitiesLayout.self, from: data) == layout)
        #expect(String(decoding: data, as: UTF8.self).contains("\"options\"") == UtilitiesToggle(kind).hasOptions)
    }

    @Test("Art, Name, Beschreibung, Gruppe sind vollstaendig", arguments: UtilitiesToggleKind.allCases)
    func kindMetadata(kind: UtilitiesToggleKind) {
        #expect(UtilitiesToggle(kind).kind == kind)
        #expect(!kind.title.isEmpty && !kind.summary.isEmpty)
        // Nur Bluetooth zeichnet seine Rune selbst.
        #expect((kind.symbol == nil) == (kind == .bluetooth))
        #expect(kind.group.kinds.contains(kind))
        #expect(kind.isUnique == (kind.group != .custom))
    }

    @Test("Karten: Name, Beschreibung, Symbol", arguments: UtilitiesCardKind.allCases)
    func cardMetadata(kind: UtilitiesCardKind) {
        #expect(!kind.title.isEmpty && !kind.summary.isEmpty && !kind.symbol.isEmpty)
    }

    // MARK: Vorlagen

    @Test("Vorlagen sind Daten mit fester Reihenfolge", arguments: [
        (UtilitiesPreset.standard, ["keepAwake", "audio", "quickToggles"],
         ["wifi", "microphone", "bluetooth", "darkMode", "nightShift", "screenshot", "showDesktop", "colorPicker",
          "lockScreen", "settings"]),
        (UtilitiesPreset.minimal, ["quickToggles", "keepAwake-aus", "audio-aus"],
         ["wifi", "bluetooth", "darkMode", "lockScreen", "settings"]),
        (UtilitiesPreset.audio, ["audio", "quickToggles", "keepAwake-aus"],
         ["microphone", "bluetooth", "wifi", "displaySleep", "settings"]),
        (UtilitiesPreset.everything, ["keepAwake", "audio", "quickToggles"],
         ["wifi", "microphone", "bluetooth", "darkMode", "nightShift", "screenshot", "showDesktop", "colorPicker",
          "lockScreen", "displaySleep", "hideApps", "settings"]),
    ])
    func presetOrder(preset: UtilitiesPreset, expectedCards: [String], expectedToggles: [String]) {
        #expect(cards(preset.layout) == expectedCards)
        #expect(toggleKinds(preset.layout) == expectedToggles)
    }

    @Test("Vorlagen sind gueltig und ueberstehen Schreiben und Lesen", arguments: UtilitiesPreset.allCases)
    func presetValid(preset: UtilitiesPreset) throws {
        let layout = preset.layout
        #expect(!preset.title.isEmpty && !preset.summary.isEmpty)
        #expect(UtilitiesLayout(cards: layout.cards, toggles: layout.toggles) == layout)
        #expect(Set(layout.toggles.map(\.id)).count == layout.toggles.count)
        #expect(!layout.visibleCards.isEmpty)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(UtilitiesLayout.self, from: data) == layout)
    }

    @Test("Alles: jeder feste Knopf genau einmal")
    func everythingHasAllFixed() {
        let kinds = Set(UtilitiesPreset.everything.layout.toggles.map(\.kind))
        #expect(kinds == Set(UtilitiesToggleKind.allCases.filter(\.isUnique)))
    }

    // MARK: Aendern

    @Test("hinzufuegen: hinten, an einer Stelle begrenzt", arguments: [
        (UtilitiesToggleKind.displaySleep, nil as Int?, ["wifi", "lockScreen", "displaySleep"]),
        (UtilitiesToggleKind.hideApps, 0 as Int?, ["hideApps", "wifi", "lockScreen"]),
        (UtilitiesToggleKind.openLink, 1 as Int?, ["wifi", "openLink", "lockScreen"]),
        (UtilitiesToggleKind.runShortcut, 99 as Int?, ["wifi", "lockScreen", "runShortcut"]),
        (UtilitiesToggleKind.openApp, -4 as Int?, ["openApp", "wifi", "lockScreen"]),
    ])
    func add(kind: UtilitiesToggleKind, index: Int?, expected: [String]) {
        var layout = UtilitiesLayout(toggles: [UtilitiesToggleEntry(.wifi), UtilitiesToggleEntry(.lockScreen)])
        #expect(layout.add(kind, at: index) != nil)
        #expect(toggleKinds(layout) == expected)
    }

    @Test("feste Knoepfe gibt es nur einmal", arguments: [
        UtilitiesToggleKind.wifi, UtilitiesToggleKind.settings, UtilitiesToggleKind.bluetooth,
    ])
    func addUniqueRefused(kind: UtilitiesToggleKind) {
        var layout = UtilitiesLayout()
        #expect(!layout.canAdd(kind))
        #expect(layout.add(kind) == nil)
        #expect(layout == UtilitiesLayout())
    }

    @Test("eigene Knoepfe mehrmals: eigene Kennungen", arguments: [
        (UtilitiesToggleKind.openApp, ["openApp", "openApp-2", "openApp-3"]),
        (UtilitiesToggleKind.runShortcut, ["runShortcut", "runShortcut-2", "runShortcut-3"]),
    ])
    func addCustomIDs(kind: UtilitiesToggleKind, expected: [String]) {
        var layout = UtilitiesLayout(toggles: [])
        #expect((0..<3).compactMap { _ in layout.add(kind) } == expected)
    }

    @Test("entfernen, danach wieder hinzufuegbar", arguments: [
        ("nightShift", ["wifi", "microphone", "bluetooth", "darkMode", "screenshot", "showDesktop", "colorPicker",
                        "lockScreen", "settings"]),
        ("gibtsnicht", ["wifi", "microphone", "bluetooth", "darkMode", "nightShift", "screenshot", "showDesktop",
                        "colorPicker", "lockScreen", "settings"]),
    ])
    func remove(id: String, expected: [String]) {
        var layout = UtilitiesLayout()
        layout.remove(toggle: id)
        #expect(toggleKinds(layout) == expected)
        #expect(layout.canAdd(.nightShift) == !layout.contains(.nightShift))
    }

    @Test("Optionen aendern nur bei gleicher Art", arguments: [
        (UtilitiesToggle.openLink(.init(url: "example.org")), UtilitiesToggle.openLink(.init(url: "example.org"))),
        (UtilitiesToggle.openApp(.init(bundleID: "com.example.app")), UtilitiesToggle.openLink(.init(url: "example.com"))),
        (UtilitiesToggle.wifi, UtilitiesToggle.openLink(.init(url: "example.com"))),
    ])
    func update(toggle: UtilitiesToggle, expected: UtilitiesToggle) {
        var layout = UtilitiesLayout(toggles: [UtilitiesToggleEntry(toggle: .openLink(.init(url: "example.com")), id: "l")])
        layout.update(toggle: "l", to: toggle)
        #expect(layout[toggle: "l"]?.toggle == expected)
    }

    @Test("ziehen wie onMove (Ziel vor dem Verschieben gezaehlt)", arguments: [
        ([0], 3, ["b", "c", "a", "d"]), ([3], 0, ["d", "a", "b", "c"]), ([1, 2], 4, ["a", "d", "b", "c"]),
        ([9], 0, ["a", "b", "c", "d"]),
    ])
    func moveOffsets(source: [Int], destination: Int, expected: [String]) {
        var layout = UtilitiesLayout(toggles: ["a", "b", "c", "d"].map { UtilitiesToggleEntry(toggle: .openApp(.init()), id: $0) })
        layout.moveToggles(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(layout.toggles.map(\.id) == expected)
    }

    @Test("im Raster ziehen: nimmt den Platz des Ziels ein", arguments: [
        ("a", "c", ["b", "c", "a", "d"]), ("d", "b", ["a", "d", "b", "c"]), ("b", "b", ["a", "b", "c", "d"]),
        ("a", "x", ["a", "b", "c", "d"]), ("c", "d", ["a", "b", "d", "c"]),
    ])
    func moveOnto(id: String, target: String, expected: [String]) {
        var layout = UtilitiesLayout(toggles: ["a", "b", "c", "d"].map { UtilitiesToggleEntry(toggle: .openApp(.init()), id: $0) })
        layout.moveToggle(id, onto: target)
        #expect(layout.toggles.map(\.id) == expected)
    }

    @Test("nach vorne und hinten, am Rand nichts", arguments: [
        ("b", -1, ["b", "a", "c"]), ("b", 1, ["a", "c", "b"]), ("a", -1, ["a", "b", "c"]), ("c", 1, ["a", "b", "c"]),
    ])
    func moveStep(id: String, step: Int, expected: [String]) {
        var layout = UtilitiesLayout(toggles: ["a", "b", "c"].map { UtilitiesToggleEntry(toggle: .openApp(.init()), id: $0) })
        layout.moveToggle(id, by: step)
        #expect(layout.toggles.map(\.id) == expected)
    }

    @Test("Karten ein/aus und umsortieren", arguments: [
        (UtilitiesCardKind.audio, false, [2], 0, ["quickToggles", "keepAwake", "audio-aus"]),
        (UtilitiesCardKind.keepAwake, false, [0], 3, ["audio", "quickToggles", "keepAwake-aus"]),
        (UtilitiesCardKind.quickToggles, true, [1], 0, ["audio", "keepAwake", "quickToggles"]),
    ])
    func cardChanges(kind: UtilitiesCardKind, enabled: Bool, source: [Int], destination: Int, expected: [String]) {
        var layout = UtilitiesLayout()
        layout.setCard(kind, enabled: enabled)
        layout.moveCards(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(cards(layout) == expected)
        #expect(layout.isEnabled(kind) == enabled)
    }

    @Test("Karte eine Stelle verschieben", arguments: [
        (UtilitiesCardKind.audio, -1, ["audio", "keepAwake", "quickToggles"]),
        (UtilitiesCardKind.quickToggles, 1, ["keepAwake", "audio", "quickToggles"]),
    ])
    func cardStep(kind: UtilitiesCardKind, step: Int, expected: [String]) {
        var layout = UtilitiesLayout()
        layout.moveCard(kind, by: step)
        #expect(cards(layout) == expected)
    }

    // MARK: Hoehe

    @Test("Hoehe je Vorlage aus den Massen", arguments: [
        (UtilitiesPreset.standard, 426.0), (UtilitiesPreset.minimal, 137.0), (UtilitiesPreset.audio, 290.0),
        (UtilitiesPreset.everything, 482.0),
    ])
    func presetHeight(preset: UtilitiesPreset, height: Double) {
        #expect(preset.layout.panelHeight == height)
    }

    @Test("Hoehe folgt Karten und Reihen", arguments: [
        // Nichts an: nur der Hinweis.
        (#"{"cards":[{"kind":"keepAwake","enabled":false},{"kind":"audio","enabled":false},{"kind":"quickToggles","enabled":false}]}"#, 100.0),
        // Schnellschalter-Karte an, aber leer: faellt weg.
        (#"{"quickToggles":[]}"#, 253.0),
        (#"{"cards":[{"kind":"audio","enabled":false},{"kind":"keepAwake","enabled":false}],"quickToggles":[]}"#, 100.0),
        (#"{"cards":[{"kind":"keepAwake"},{"kind":"audio","enabled":false},{"kind":"quickToggles","enabled":false}]}"#, 100.0),
        (#"{"cards":[{"kind":"audio","enabled":false}],"quickToggles":[{"kind":"wifi"}]}"#, 217.0),
        (#"{"quickToggles":[{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"}]}"#, 426.0),
        (#"{"quickToggles":[{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"},{"kind":"openApp"}]}"#, 482.0),
    ])
    func height(json: String, expected: Double) {
        #expect(layout(json)?.panelHeight == expected)
    }

    @Test("Reihen zu fuenf, die letzte darf kuerzer sein", arguments: [
        (0, [Int]()), (1, [1]), (5, [5]), (6, [5, 1]), (11, [5, 5, 1]), (15, [5, 5, 5]),
    ])
    func rows(count: Int, expected: [Int]) {
        let layout = UtilitiesLayout(toggles: (0..<count).map { _ in UtilitiesToggleEntry(toggle: .openApp(.init()), id: "") })
        #expect(layout.toggleRows.map(\.count) == expected)
        #expect(layout.toggles.count == count)
    }

    // MARK: Einstellungen

    @Test("settings.json: Abschnitt schreiben und wieder lesen")
    func settingsRoundTrip() {
        var layout = UtilitiesPreset.everything.layout
        layout.add(.openApp(.init(bundleID: "com.example.app", title: "Editor", symbol: "")))
        layout.add(.runShortcut(.init(name: "Fokus", identifier: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")))
        layout.setCard(.audio, enabled: false)
        let settings = ShellSettings(utilities: .init(layout: layout))
        #expect(ShellSettings.load(from: settings.encoded()) == settings)
        let text = String(decoding: settings.encoded(), as: UTF8.self)
        for key in ["\"utilities\"", "\"layout\"", "\"cards\"", "\"quickToggles\"", "\"enabled\"", "\"bundleID\""] {
            #expect(text.contains(key))
        }
    }

    @Test("ein kaputter utilities-Abschnitt laesst den Rest stehen")
    func otherSectionsSurvive() {
        let json = #"{"utilities":{"layout":{"cards":5,"quickToggles":[{"kind":"wifi"}]}},"toasts":{"batteryWarnings":false}}"#
        let settings = ShellSettings.load(from: Data(json.utf8))
        #expect(settings.toasts.batteryWarnings == false)
        #expect(toggleKinds(settings.utilities.layout) == ["wifi"])
        #expect(cards(settings.utilities.layout) == ["keepAwake", "audio", "quickToggles"])
    }
}

@Suite("Utilities-Panel: eigene Knoepfe")
struct UtilitiesCustomToggleTests {
    @Test("Link aus der Eingabe", arguments: [
        ("example.com", "https://example.com"),
        ("  https://example.com/docs?x=1  ", "https://example.com/docs?x=1"),
        ("http://example.com", "http://example.com"),
        ("mailto:someone@example.com", "mailto:someone@example.com"),
        ("x-apple.systempreferences:com.apple.Sound-Settings.extension", "x-apple.systempreferences:com.apple.Sound-Settings.extension"),
        ("localhost:8080", "https://localhost:8080"),
        ("example.com:8443/admin", "https://example.com:8443/admin"),
        ("", "-"), ("   ", "-"), ("zwei worte.de", "-"), ("https://", "-"), ("wort", "-"),
    ])
    func link(input: String, expected: String) {
        #expect(UtilitiesLink.url(from: input)?.absoluteString ?? "-" == expected)
    }

    @Test("Link kurz fuer den Tooltip", arguments: [
        ("https://www.example.com/", "example.com"), ("https://example.com/docs/", "example.com/docs"),
        ("mailto:someone@example.com", "mailto:someone@example.com"),
    ])
    func linkText(url: String, expected: String) {
        #expect(UtilitiesLink.displayText(URL(string: url)!) == expected)
    }

    @Test("Kurzbefehle aus shortcuts list --show-identifiers")
    func parseShortcuts() {
        let output = """
        Timer (kurz) (1B4E28BA-2FA1-11D2-883F-0016D3CCA427)

        Fokus an (6FA459EA-EE8A-3CA4-894E-DB77E160355E)
        Ohne Kennung
        Kaputt (keine-uuid)
         (886313E1-3B8A-5372-9B90-0C9AEE199E5D)
        """
        let list = UtilitiesShortcuts.parse(output)
        #expect(list.map(\.name) == ["Fokus an", "Kaputt (keine-uuid)", "Ohne Kennung", "Timer (kurz)"])
        #expect(list.map(\.identifier) == ["6FA459EA-EE8A-3CA4-894E-DB77E160355E", "", "", "1B4E28BA-2FA1-11D2-883F-0016D3CCA427"])
        #expect(UtilitiesShortcuts.parse("").isEmpty)
    }

    @Test("Ausfuehren: lieber Kennung, sonst Name, sonst nichts", arguments: [
        (UtilitiesShortcutOptions(name: "Fokus", identifier: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427"),
         ["run", "1B4E28BA-2FA1-11D2-883F-0016D3CCA427"]),
        (UtilitiesShortcutOptions(name: "Fokus", identifier: "  "), ["run", "Fokus"]),
        (UtilitiesShortcutOptions(), [String]()),
    ])
    func runArguments(options: UtilitiesShortcutOptions, expected: [String]) {
        #expect(UtilitiesShortcuts.runArguments(options) ?? [] == expected)
    }

    @Test("App button: without an app or when not installed it is not clickable", arguments: [
        (UtilitiesAppOptions(), "Editor" as String?, false, "No App Chosen Yet"),
        (UtilitiesAppOptions(bundleID: "com.example.app"), nil as String?, false, "App Not Installed"),
        (UtilitiesAppOptions(bundleID: "com.example.app"), "Editor" as String?, true, "Open Editor"),
        (UtilitiesAppOptions(bundleID: "com.example.app", title: "Writing"), "Editor" as String?, true, "Open Writing"),
    ])
    func appLook(options: UtilitiesAppOptions, name: String?, enabled: Bool, help: String) {
        let look = QuickToggles.openApp(options, appName: name)
        #expect(look.enabled == enabled && look.help == help && !look.active)
    }
    @Test("The app button shows the app icon when it has no symbol of its own", arguments: [
    @Test("App-Knopf zeigt ohne eigenes Symbol das App-Symbol", arguments: [
        ("", true), ("  ", true), ("star.fill", false),
    ])
    func appIcon(symbol: String, usesAppIcon: Bool) {
        #expect(UtilitiesAppOptions(bundleID: "com.example.app", symbol: symbol).usesAppIcon == usesAppIcon)
    }

    @Test("Link- und Kurzbefehl-Knopf", arguments: [
        (UtilitiesToggle.openLink(.init()), false, "Noch kein Link", "link"),
        (UtilitiesToggle.openLink(.init(url: "zwei worte")), false, "Link ungültig", "link"),
        (UtilitiesToggle.openLink(.init(url: "www.example.com")), true, "example.com öffnen", "link"),
        (UtilitiesToggle.openLink(.init(url: "example.com", title: "Doku", symbol: "book.fill")), true, "Doku öffnen", "book.fill"),
        (UtilitiesToggle.runShortcut(.init()), false, "Noch kein Kurzbefehl gewählt", "square.2.layers.3d.fill"),
        (UtilitiesToggle.runShortcut(.init(name: "Fokus")), true, "Kurzbefehl „Fokus“ ausführen", "square.2.layers.3d.fill"),
        (UtilitiesToggle.runShortcut(.init(name: "Fokus", title: "Ruhe", symbol: "moon.fill")), true,
         "Kurzbefehl „Ruhe“ ausführen", "moon.fill"),
    ])
    func customLooks(toggle: UtilitiesToggle, enabled: Bool, help: String, symbol: String) {
        let look = switch toggle {
        case .openLink(let o): QuickToggles.openLink(o)
        case .runShortcut(let o): QuickToggles.runShortcut(o)
        default: QuickToggles.settings
        }
        #expect(look.enabled == enabled && look.help == help && look.symbol == symbol)
    }

    @Test("Hide apps: never the shell, only regular apps, the frontmost one on request", arguments: [
        (Int32(10), true, Int32(10), false, false),
        (Int32(11), false, Int32(12), false, false),
        (Int32(11), true, Int32(12), false, true),
        (Int32(12), true, Int32(12), true, false),
        (Int32(12), true, Int32(99), true, true),
    ])
    func hideFilter(pid: Int32, regular: Bool, frontmost: Int32, keep: Bool, hides: Bool) {
        #expect(UtilitiesHideApps.shouldHide(pid: pid, isRegular: regular, ownPID: 10, frontmostPID: frontmost,
                                             keepFrontmost: keep) == hides)
        #expect(QuickToggles.hideApps(.init(keepFrontmost: keep)).help == (keep ? "Hide Other Apps" : "Hide All Apps"))
    }

    @Test("Symbol choice: unique, not empty")
    func symbolChoices() {
        #expect(!UtilitiesSymbols.choices.isEmpty)
        #expect(Set(UtilitiesSymbols.choices).count == UtilitiesSymbols.choices.count)
    }

    @Test("Toast on failure", arguments: [("Focus", "Focus"), ("  ", "Unknown Shortcut")])
    func failedToast(name: String, message: String) {
        let content = ToastText.shortcutFailed(name)
        #expect(content.message == message && content.kind == .warning)
    }
}
