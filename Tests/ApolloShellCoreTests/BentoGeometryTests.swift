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
