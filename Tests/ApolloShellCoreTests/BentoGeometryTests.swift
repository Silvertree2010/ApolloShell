import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bento-Geometrie: gueltige Lage und Massstab")
struct BentoGeometryTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    @Test("Auf der Seite")
    func inside() {
        #expect(BentoGeometry.isInside(f(0, 0, 839, 392)))
        #expect(!BentoGeometry.isInside(f(-1, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(740, 0, 100, 130)))
        #expect(!BentoGeometry.isInside(f(0, 263, 110, 130)))
    }

    @Test("Genau 12 Punkte Abstand ist erlaubt, 11 nicht, schraeg versetzt zaehlt nicht")
    func spacing() {
        let weather = f(0, 0, 275, 130)
        #expect(!BentoGeometry.tooClose(weather, f(287, 0, 340, 130)))
        #expect(BentoGeometry.tooClose(weather, f(286, 0, 340, 130)))
        #expect(!BentoGeometry.tooClose(weather, f(0, 142, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(0, 141, 110, 250)))
        #expect(BentoGeometry.tooClose(weather, f(280, 136, 100, 250)))            // 5 in x, 6 in y: zu nah
        #expect(!BentoGeometry.tooClose(weather, f(300, 200, 100, 130)))           // 25 in x: frei
        #expect(BentoGeometry.tooClose(weather, f(100, 50, 50, 50)))               // ueberlappt
    }

    @Test("Gueltig: auf der Seite, erlaubte Groesse, Abstand")
    func valid() {
        let others = [f(0, 0, 275, 130)]
        #expect(BentoGeometry.isValid(f(0, 142, 110, 250), kind: .clock, others: others))
        #expect(!BentoGeometry.isValid(f(0, 142, 100, 250), kind: .clock, others: others))   // zu schmal
        #expect(!BentoGeometry.isValid(f(0, 142, 110, 200), kind: .clock, others: others))   // Hoehe gibt es nicht
        #expect(!BentoGeometry.isValid(f(0, 130, 110, 250), kind: .clock, others: others))   // zu nah
    }

    @Test("Massstab: Automatik nach Breite, Regler, Hoehe begrenzt", arguments: [
        (1512.0, 2000.0, 1.0, 1.0),
        (2560, 2000, 1.0, 1.5),
        (1280, 2000, 1.0, 0.85),
        (1512, 2000, 1.2, 1.2),
        (2560, 2000, 1.5, 2.25),
        (1512, 400, 1.0, 400.0 / 460.0),
        (1512, 2000, 9.0, 1.5),
        (1512, 2000, .nan, 1.0),
    ])
    func scale(screenWidth: Double, availableHeight: Double, user: Double, expected: Double) {
        let value = BentoGeometry.scale(screenWidth: screenWidth, availableHeight: availableHeight,
                                        contentHeight: 460, userScale: user)
        #expect(abs(value - expected) < 0.0001)
    }
}

@Suite("Bento-Geometrie: Einrasten")
struct BentoSnapTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }
    private let weather = WidgetFrame(x: 0, y: 0, width: 275, height: 130)

    @Test("Ziehen: Seitenrand, Flucht, 12 Punkte daneben, sonst frei", arguments: [
        (WidgetFrame(x: 5, y: 300, width: 100, height: 50), 0.0, 300.0),     // linker Rand (y frei)
        (WidgetFrame(x: 636, y: 3, width: 200, height: 130), 639, 0),        // rechter Rand, oberer Rand
        (WidgetFrame(x: 290, y: 4, width: 200, height: 130), 287, 0),        // 12 neben dem Wetter
        (WidgetFrame(x: 400.4, y: 250.6, width: 100, height: 50), 400, 251), // kein Ziel: nur gerundet
        (WidgetFrame(x: 3, y: 146, width: 110, height: 250), 0, 142),        // Flucht links, 12 unter dem Wetter
    ])
    func move(proposed: WidgetFrame, x: Double, y: Double) {
        let snapped = BentoGeometry.snapMove(proposed, others: [weather])
        #expect(snapped.x == x)
        #expect(snapped.y == y)
        #expect(snapped.width == proposed.width.rounded())
    }

    @Test("Ziehen: das naechste Ziel gewinnt")
    func nearestWins() {
        // Rechte Kante buendig mit dem Wetter (x = 175) liegt 2 weg, alles andere weiter.
        let snapped = BentoGeometry.snapMove(f(177, 300, 100, 50), others: [weather])
        #expect(snapped.x == 175)
    }

    @Test("Groesse: Hoehe springt, Breite bleibt in der Spanne und rastet ein")
    func resize() {
        let clock = f(0, 142, 110, 250)
        // Hoehe 260 -> 250, Breite 115 frei (kein Ziel naeher als 8)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 115, proposedHeight: 260, others: []) == f(0, 142, 115, 250))
        // Hoehe 380 -> 392 passt nicht mehr auf die Seite; die Funktion rastet nur, gueltig prueft isValid
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 110, proposedHeight: 380, others: []).height == 392)
        // Breite unter dem Minimum -> Minimum
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 40, proposedHeight: 250, others: []).width == 110)
        // Breite rastet 12 vor dem Nachbarn ein: Nachbar bei x = 300 -> Breite 288
        let neighbour = f(300, 142, 110, 250)
        #expect(BentoGeometry.snapResize(clock, kind: .clock, proposedWidth: 283, proposedHeight: 250, others: [neighbour]).width == 288)
        // Feste Groesse bleibt fest
        let network = f(0, 203, 335, 189)
        #expect(BentoGeometry.snapResize(network, kind: .performanceNetwork, proposedWidth: 400, proposedHeight: 150, others: []) == network)
    }

    @Test("Ablegen: kleinste Groesse, mittig unter dem Zeiger, eingerastet")
    func drop() {
        let frame = BentoGeometry.dropFrame(kind: .clock, x: 60, y: 208, others: [weather])
        #expect(frame == f(0, 142, 110, 130))   // 60-55 = 5 -> Rand 0; 208-65 = 143 -> 142 (12 unter dem Wetter)
    }
}
