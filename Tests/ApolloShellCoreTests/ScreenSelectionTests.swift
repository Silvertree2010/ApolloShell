import CoreGraphics
import Foundation
import Testing
@testable import ApolloShellCore

/// The measurements as on a real setup: the MacBook screen as the main
/// screen, a bigger external one to the right of it.
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

@Suite("Choosing screens")
struct ScreenSelectionTests {
    // MARK: - Target screens

    @Test("All: every connected screen, in the given order")
    func targetsAll() {
        #expect(ScreenSelection.targets(among: Screens.both, choice: .all) == Screens.both)
    }

    @Test("Main screen only: the one with the menu bar, wherever it stands in the list")
    func targetsPrimary() {
        #expect(ScreenSelection.targets(among: Screens.both, choice: .primary) == [Screens.builtIn])
        // Even when the main screen does not come first.
        let reversed = [Screens.external, Screens.builtIn]
        #expect(ScreenSelection.targets(among: reversed, choice: .primary) == [Screens.builtIn])
    }

    @Test("Without a marked main screen the first one counts")
    func targetsPrimaryWithoutFlag() {
        let nameless = ScreenInfo(name: "A", frame: CGRect(x: 0, y: 0, width: 800, height: 600), isPrimary: false)
        #expect(ScreenSelection.targets(among: [nameless], choice: .primary) == [nameless])
    }

    @Test("A single screen through its key")
    func targetsSingle() {
        let choice = ScreenChoice.single(Screens.external.key)
        #expect(ScreenSelection.targets(among: Screens.both, choice: choice) == [Screens.external])
    }

    @Test("The remembered screen unplugged: falls back to the main screen")
    func targetsSingleGone() {
        let choice = ScreenChoice.single(Screens.external.key)
        #expect(ScreenSelection.targets(among: [Screens.builtIn], choice: choice) == [Screens.builtIn])
    }

    @Test("An empty list: nothing, with every setting", arguments: [
        ScreenChoice.all, .primary, .single("Built-in Retina Display 1728x1117"),
    ])
    func targetsWithoutScreens(choice: ScreenChoice) {
        #expect(ScreenSelection.targets(among: [], choice: choice).isEmpty)
    }

    @Test("Two identical screens share the key: it stays at one")
    func targetsDuplicateKey() {
        let left = ScreenInfo(name: "DELL U2723QE", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isPrimary: true)
        let right = ScreenInfo(name: "DELL U2723QE", frame: CGRect(x: 2560, y: 0, width: 2560, height: 1440), isPrimary: false)
        #expect(left.key == right.key)
        #expect(ScreenSelection.targets(among: [left, right], choice: .single(left.key)) == [left])
    }

    // MARK: - Keys

    @Test("The key is the name plus the resolution, rounded to whole points")
    func keyIsNameAndSize() {
        #expect(Screens.builtIn.key == "Built-in Retina Display 1728x1117")
        let scaled = ScreenInfo(name: "A", frame: CGRect(x: 0, y: 0, width: 1512.4, height: 982.6), isPrimary: true)
        #expect(scaled.key == "A 1512x983")
    }

    @Test("A moved screen keeps its key, a different mode does not")
    func keyIgnoresPosition() {
        var moved = Screens.external
        moved.frame.origin = CGPoint(x: -2560, y: 300)
        #expect(moved.key == Screens.external.key)

        var lowRes = Screens.external
        lowRes.frame.size = CGSize(width: 1920, height: 1080)
        #expect(lowRes.key != Screens.external.key)
    }

    // MARK: - The screen under the pointer

    @Test("The pointer in the middle of a screen")
    func pointerInside() {
        #expect(ScreenSelection.screen(at: CGPoint(x: 800, y: 500), among: Screens.both) == Screens.builtIn)
        #expect(ScreenSelection.screen(at: CGPoint(x: 3000, y: 500), among: Screens.both) == Screens.external)
    }

    @Test("The pointer exactly on the edge between the two: clearly the right one")
    func pointerOnSharedEdge() {
        // 1728 is the right edge of the one and the left edge of the other at
        // the same time. Exactly one screen may claim it.
        let point = CGPoint(x: 1728, y: 500)
        #expect(Screens.builtIn.frame.contains(point) == false)
        #expect(Screens.external.frame.contains(point))
        #expect(ScreenSelection.screen(at: point, among: Screens.both) == Screens.external)
        // The answer does not hang on the order of the list.
        #expect(ScreenSelection.screen(at: point, among: [Screens.external, Screens.builtIn]) == Screens.external)
        // One point further left it still belongs to the left one.
        #expect(ScreenSelection.screen(at: CGPoint(x: 1727, y: 500), among: Screens.both) == Screens.builtIn)
    }

    @Test("The pointer on the top edge: belongs to the screen below it")
    func pointerOnTopEdge() {
        // y = maxY lies in no frame (contains does not count the top edge in)
        // - the nearest one has to step in.
        let point = CGPoint(x: 800, y: 1117)
        #expect(Screens.builtIn.frame.contains(point) == false)
        #expect(ScreenSelection.screen(at: point, among: Screens.both) == Screens.builtIn)
    }

    @Test("The pointer outside all screens: the nearest one")
    func pointerOutside() {
        #expect(ScreenSelection.screen(at: CGPoint(x: -100, y: 500), among: Screens.both) == Screens.builtIn)
        #expect(ScreenSelection.screen(at: CGPoint(x: 5000, y: 500), among: Screens.both) == Screens.external)
        // Just above the main screen and horizontally over it: it is nearer
        // than the taller neighbour on the right. Far enough up that tips,
        // because the neighbour reaches higher - the distance decides, not the
        // order.
        #expect(ScreenSelection.screen(at: CGPoint(x: 200, y: 1500), among: Screens.both) == Screens.builtIn)
    }

    @Test("An empty list: no screen under the pointer")
    func pointerWithoutScreens() {
        #expect(ScreenSelection.screen(at: CGPoint(x: 800, y: 500), among: []) == nil)
    }

    @Test("A single screen always catches the pointer")
    func pointerSingleScreen() {
        let only = [Screens.builtIn]
        #expect(ScreenSelection.screen(at: CGPoint(x: 9999, y: -9999), among: only) == Screens.builtIn)
    }

    // MARK: - Reading and writing the setting

    @Test("writing and reading back gives the same", arguments: [
        ScreenChoice.all, .primary, .single("Built-in Retina Display 1728x1117"),
    ])
    func choiceRoundTrip(choice: ScreenChoice) {
        let data = try! JSONEncoder().encode(choice)
        #expect(try! JSONDecoder().decode(ScreenChoice.self, from: data) == choice)
    }

    @Test("a broken or unknown entry: all screens", arguments: [
        "{}", #"{"mode":"hologramm"}"#, #"{"mode":null}"#, #"{"mode":"single"}"#,
        #"{"mode":"single","screen":null}"#, #"{"mode":"single","screen":"  "}"#, #"{"screen":"A 1x1"}"#,
    ])
    func choiceLenient(json: String) {
        #expect(try! JSONDecoder().decode(ScreenChoice.self, from: Data(json.utf8)) == .all)
    }

    @Test("Without a key in the file the bar stands on all screens")
    func settingsDefault() {
        #expect(ShellSettings().bar.screens == .all)
        #expect(ShellSettings.load(from: Data(#"{"bar":{"layout":[]}}"#.utf8)).bar.screens == .all)
        #expect(ShellSettings.load(from: Data(#"{"bar":{"screens":5}}"#.utf8)).bar.screens == .all)
    }

    @Test("The setting stands in settings.json and survives the writing")
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
