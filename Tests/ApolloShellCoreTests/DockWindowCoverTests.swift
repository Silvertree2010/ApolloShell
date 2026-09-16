import ApolloShellCore
import Testing

@Suite("Verdecktes Fenster beim Klick auf die schon vordere App")
struct DockWindowCoverTests {
    private static func window(
        _ id: Int, _ owner: DockScreenWindow.Owner, layer: Int = 0,
        _ x: Double, _ y: Double, _ width: Double, _ height: Double
    ) -> DockScreenWindow {
        DockScreenWindow(id: id, owner: owner, layer: layer, x: x, y: y, width: width, height: height)
    }

    @Test("Nur ein Fenster: nichts verdeckt es")
    func onlyOneWindow() {
        let windows = [Self.window(1, .target, 0, 0, 500, 400)]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Zwei Fenster nebeneinander, keine Ueberlappung: nichts blaettert")
    func sideBySideNoOverlap() {
        let windows = [
            Self.window(1, .other, 0, 0, 500, 400),
            Self.window(2, .target, 500, 0, 500, 400),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Vollstaendig verdeckt: das verdeckte kommt nach vorne")
    func fullyCovered() {
        let windows = [
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("Teilweise verdeckt, aber unter der Schwelle: nichts blaettert")
    func partiallyCoveredBelowThreshold() {
        // 5 % der Flaeche liegen unter dem anderen Fenster.
        let windows = [
            Self.window(1, .other, 0, 0, 100, 30),
            Self.window(2, .target, 0, 0, 100, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Teilweise verdeckt, ueber der Schwelle: gilt als verdeckt")
    func partiallyCoveredAboveThreshold() {
        // 20 % der Flaeche liegen unter dem anderen Fenster.
        let windows = [
            Self.window(1, .other, 0, 0, 100, 120),
            Self.window(2, .target, 0, 0, 100, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("Mehrere verdeckte in Reihe: das vorderste kommt zuerst")
    func multipleCoveredInARow() {
        let windows = [
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
            Self.window(3, .target, 300, 300, 200, 200),
        ]
        // Beide Zielfenster liegen unter Fenster 1 - das vordere Zielfenster
        // (2) ist naeher an der Spitze der Liste und kommt zuerst.
        #expect(DockWindowCover.nextCovered(in: windows) == 2)
    }

    @Test("Nach dem Nachvornholen ist ein anderes an der Reihe")
    func nextClickPicksTheNextOne() {
        // Wie im echten Ablauf: nach dem Heben von 2 steht die Liste neu -
        // 2 ist jetzt vorne, 3 liegt immer noch unter 1.
        let windows = [
            Self.window(2, .target, 100, 100, 200, 200),
            Self.window(1, .other, 0, 0, 800, 600),
            Self.window(3, .target, 300, 300, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == 3)
    }

    @Test("Fremdes Fenster ausserhalb Ebene 0 verdeckt nicht (Menueleiste, Dock)")
    func nonZeroLayerDoesNotCover() {
        let windows = [
            Self.window(1, .other, layer: 25, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Eigene Leiste/Panels verdecken nie")
    func ownShellNeverCovers() {
        let windows = [
            Self.window(1, .ownShell, 0, 0, 800, 600),
            Self.window(2, .target, 100, 100, 200, 200),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }

    @Test("Nur ein fremdes Fenster dahinter (fremdes Fenster verdeckt nichts, weil hinter dem Zielfenster)")
    func otherWindowBehindTargetDoesNotCover() {
        let windows = [
            Self.window(2, .target, 0, 0, 200, 200),
            Self.window(1, .other, 0, 0, 800, 600),
        ]
        #expect(DockWindowCover.nextCovered(in: windows) == nil)
    }
}
