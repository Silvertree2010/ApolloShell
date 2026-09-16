import CoreGraphics
import Foundation
import Testing
@testable import ApolloShellCore

/// Masse wie an einem echten Aufbau: MacBook-Bildschirm als Hauptbildschirm,
/// daneben rechts ein groesserer externer.
private enum Screens {
    static let builtIn = ScreenInfo(
        name: "Built-in Retina Display",
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        isPrimary: true
    )
    static let external = ScreenInfo(
        name: "DELL U2723QE",
        frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440),
        isPrimary: false
    )
    static let both = [builtIn, external]
}

@Suite("Bildschirme auswaehlen")
struct ScreenSelectionTests {
    // MARK: - Zielbildschirme

    @Test("Alle: jeder angeschlossene Bildschirm, in der gegebenen Reihenfolge")
    func targetsAll() {
        #expect(ScreenSelection.targets(among: Screens.both, choice: .all) == Screens.both)
    }

    @Test("Nur Hauptbildschirm: der mit der Menueleiste, egal wo er in der Liste steht")
    func targetsPrimary() {
        #expect(ScreenSelection.targets(among: Screens.both, choice: .primary) == [Screens.builtIn])
        // Auch wenn der Hauptbildschirm nicht zuerst kommt.
        let reversed = [Screens.external, Screens.builtIn]
        #expect(ScreenSelection.targets(among: reversed, choice: .primary) == [Screens.builtIn])
    }

    @Test("Ohne gekennzeichneten Hauptbildschirm gilt der erste")
    func targetsPrimaryWithoutFlag() {
        let nameless = ScreenInfo(name: "A", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isPrimary: false)
        #expect(ScreenSelection.targets(among: [nameless], choice: .primary) == [nameless])
    }

    @Test("Einzelner Bildschirm ueber seinen Schluessel")
    func targetsSingle() {
        let choice = ScreenChoice.single(Screens.external.key)
        #expect(ScreenSelection.targets(among: Screens.both, choice: choice) == [Screens.external])
    }

    @Test("Gemerkter Bildschirm abgesteckt: faellt auf den Hauptbildschirm zurueck")
    func targetsSingleGone() {
        let choice = ScreenChoice.single(Screens.external.key)
        #expect(ScreenSelection.targets(among: [Screens.builtIn], choice: choice) == [Screens.builtIn])
    }

    @Test("Leere Liste: nichts, bei jeder Einstellung", arguments: [
        ScreenChoice.all, .primary, .single("Built-in Retina Display 1728x1117"),
    ])
    func targetsWithoutScreens(choice: ScreenChoice) {
        #expect(ScreenSelection.targets(among: [], choice: choice).isEmpty)
    }

    @Test("Zwei baugleiche Bildschirme teilen den Schluessel: es bleibt bei einem")
    func targetsDuplicateKey() {
        let left = ScreenInfo(name: "DELL U2723QE", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isPrimary: true)
        let right = ScreenInfo(name: "DELL U2723QE", frame: CGRect(x: 2560, y: 0, width: 2560, height: 1440), isPrimary: false)
        #expect(left.key == right.key)
        #expect(ScreenSelection.targets(among: [left, right], choice: .single(left.key)) == [left])
    }

    // MARK: - Schluessel

    @Test("Schluessel ist Name plus Aufloesung, auf ganze Punkte gerundet")
    func keyIsNameAndSize() {
        #expect(Screens.builtIn.key == "Built-in Retina Display 1728x1117")
        let scaled = ScreenInfo(name: "A", frame: CGRect(x: 0, y: 0, width: 1512.4, height: 982.6), isPrimary: true)
        #expect(scaled.key == "A 1512x983")
    }

    @Test("Verschobener Bildschirm behaelt seinen Schluessel, ein anderer Modus nicht")
    func keyIgnoresPosition() {
        var moved = Screens.external
        moved.frame.origin = CGPoint(x: -2560, y: 300)
        #expect(moved.key == Screens.external.key)

        var lowRes = Screens.external
        lowRes.frame.size = CGSize(width: 1920, height: 1080)
        #expect(lowRes.key != Screens.external.key)
    }

    // MARK: - Bildschirm unter dem Zeiger

    @Test("Zeiger mitten auf einem Bildschirm")
    func pointerInside() {
        #expect(ScreenSelection.screen(at: CGPoint(x: 800, y: 500), among: Screens.both) == Screens.builtIn)
        #expect(ScreenSelection.screen(at: CGPoint(x: 3000, y: 500), among: Screens.both) == Screens.external)
    }

    @Test("Zeiger genau auf der Kante zwischen beiden: eindeutig der rechte")
    func pointerOnSharedEdge() {
        // 1728 ist zugleich die rechte Kante des einen und die linke des
        // anderen. Genau ein Bildschirm darf ihn beanspruchen.
        let point = CGPoint(x: 1728, y: 500)
        #expect(Screens.builtIn.frame.contains(point) == false)
        #expect(Screens.external.frame.contains(point))
        #expect(ScreenSelection.screen(at: point, among: Screens.both) == Screens.external)
        // Die Antwort haengt nicht an der Reihenfolge der Liste.
        #expect(ScreenSelection.screen(at: point, among: [Screens.external, Screens.builtIn]) == Screens.external)
        // Einen Punkt weiter links gehoert er noch dem linken.
        #expect(ScreenSelection.screen(at: CGPoint(x: 1727, y: 500), among: Screens.both) == Screens.builtIn)
    }

    @Test("Zeiger auf der Oberkante: gehoert dem Bildschirm darunter")
    func pointerOnTopEdge() {
        // y = maxY liegt in keinem Rahmen (contains zaehlt die Oberkante
        // nicht mit) - der naechstgelegene muss einspringen.
        let point = CGPoint(x: 800, y: 1117)
        #expect(Screens.builtIn.frame.contains(point) == false)
        #expect(ScreenSelection.screen(at: point, among: Screens.both) == Screens.builtIn)
    }

    @Test("Zeiger ausserhalb aller Bildschirme: der naechstgelegene")
    func pointerOutside() {
        #expect(ScreenSelection.screen(at: CGPoint(x: -100, y: 500), among: Screens.both) == Screens.builtIn)
        #expect(ScreenSelection.screen(at: CGPoint(x: 5000, y: 500), among: Screens.both) == Screens.external)
        // Knapp ueber dem Hauptbildschirm und waagrecht ueber ihm: er ist
        // naeher als der hoehere Nachbar rechts. Weit genug oben kippt das,
        // weil der Nachbar hoeher hinaufreicht - der Abstand entscheidet,
        // nicht die Reihenfolge.
        #expect(ScreenSelection.screen(at: CGPoint(x: 200, y: 1500), among: Screens.both) == Screens.builtIn)
    }

    @Test("Leere Liste: kein Bildschirm unter dem Zeiger")
    func pointerWithoutScreens() {
        #expect(ScreenSelection.screen(at: CGPoint(x: 800, y: 500), among: []) == nil)
    }

    @Test("Ein einziger Bildschirm faengt den Zeiger immer")
    func pointerSingleScreen() {
        let only = [Screens.builtIn]
        #expect(ScreenSelection.screen(at: CGPoint(x: 9999, y: -9999), among: only) == Screens.builtIn)
    }

    // MARK: - Einstellung lesen und schreiben

    @Test("schreiben und wieder lesen ergibt dasselbe", arguments: [
        ScreenChoice.all, .primary, .single("Built-in Retina Display 1728x1117"),
    ])
    func choiceRoundTrip(choice: ScreenChoice) {
        let data = try! JSONEncoder().encode(choice)
        #expect(try! JSONDecoder().decode(ScreenChoice.self, from: data) == choice)
    }

    @Test("kaputte oder unbekannte Angabe: alle Bildschirme", arguments: [
        "{}", #"{"mode":"hologramm"}"#, #"{"mode":null}"#, #"{"mode":"single"}"#,
        #"{"mode":"single","screen":null}"#, #"{"mode":"single","screen":"  "}"#, #"{"screen":"A 1x1"}"#,
    ])
    func choiceLenient(json: String) {
        #expect(try! JSONDecoder().decode(ScreenChoice.self, from: Data(json.utf8)) == .all)
    }

    @Test("Die Leiste steht ohne Schluessel in der Datei auf allen Bildschirmen")
    func settingsDefault() {
        #expect(ShellSettings().bar.screens == .all)
        #expect(ShellSettings.load(from: Data(#"{"bar":{"layout":[]}}"#.utf8)).bar.screens == .all)
        #expect(ShellSettings.load(from: Data(#"{"bar":{"screens":5}}"#.utf8)).bar.screens == .all)
    }

    @Test("Die Einstellung steht in settings.json und ueberlebt das Schreiben")
    func settingsRoundTrip() {
        var settings = ShellSettings()
        settings.bar.screens = .single("DELL U2723QE 2560x1440")
        let text = String(decoding: settings.encoded(), as: UTF8.self)
        #expect(text.contains("\"screens\""))
        #expect(text.contains("\"mode\""))
        #expect(ShellSettings.load(from: settings.encoded()) == settings)

        var primaryOnly = ShellSettings()
        primaryOnly.bar.screens = .primary
        #expect(ShellSettings.load(from: primaryOnly.encoded()) == primaryOnly)
    }
}
