import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: Anzeigen aus blocks.md 4.3", .serialized)
struct DisplayRenderTests {
    func panel(_ child: String, _ css: String, size: String = "width: 40px; height: 40px;") throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(child)\n}", css: "#t { width: 120px; height: 60px; align-items: start; }\n.d { \(size) }\n" + css)
    }

    func isRed(_ pixel: RGBA) -> Bool { pixel.r > 200 && pixel.g < 70 && pixel.b < 70 }
    func isBlue(_ pixel: RGBA) -> Bool { pixel.b > 200 && pixel.r < 70 && pixel.g < 70 }

    @Test("ring füllt ab -apollo-start-angle im Uhrzeigersinn, Spur in -apollo-track-color")
    func ring() throws {
        let shot = try panel("ring class=\"d\" value=0.25", ".d { color: #ff0000; -apollo-track-color: #0000ff; -apollo-stroke-width: 6px; }")
        #expect(isRed(shot.pixel(32, 8)))
        #expect(isBlue(shot.pixel(3, 20)))
        #expect(isBlue(shot.pixel(20, 37)))
        let half = try panel("ring class=\"d\" value=1", ".d { color: #ff0000; -apollo-stroke-width: 6px; -apollo-sweep-angle: 180deg; -apollo-start-angle: 180deg; }")
        #expect(isRed(half.pixel(20, 3)))
        #expect(!isRed(half.pixel(20, 37)))
    }

    @Test("ring gap lässt Abstand zwischen Füllung und Spur")
    func ringGap() throws {
        let shot = try panel("ring class=\"d\" value=0.25 gap=0.1", ".d { color: #ff0000; -apollo-track-color: #0000ff; -apollo-stroke-width: 6px; }")
        #expect(shot.pixel(37, 25).near(.white, tolerance: 60))
        #expect(isBlue(shot.pixel(3, 20)))
    }

    @Test("gauge: Bogen von -135° bis 135°, unten offen")
    func gauge() throws {
        let shot = try panel("gauge class=\"d\" value=1", ".d { color: #ff0000; -apollo-stroke-width: 6px; }")
        #expect(isRed(shot.pixel(20, 3)))
        #expect(isRed(shot.pixel(3, 20)))
        #expect(shot.pixel(20, 37).near(.white, tolerance: 30))
    }

    @Test("graph bars skaliert auf max, line und area zeichnen")
    func graph() throws {
        let bars = try panel("graph class=\"d\" kind=\"bars\" values=\"{[1, 0.5]}\"", ".d { color: #ff0000; }", size: "width: 40px; height: 20px;")
        #expect(isRed(bars.pixel(10, 2)))
        #expect(!isRed(bars.pixel(30, 5)))
        #expect(isRed(bars.pixel(30, 15)))
        let area = try panel("graph class=\"d\" kind=\"area\" values=\"{[0, 1, 0]}\"", ".d { color: #ff0000; -apollo-fill: #0000ff; -apollo-stroke-width: 2px; }", size: "width: 40px; height: 20px;")
        #expect(isBlue(area.pixel(20, 15)))
        let capped = try panel("graph class=\"d\" kind=\"bars\" capacity=1 values=\"{[1, 0.5]}\" max=1", ".d { color: #ff0000; }", size: "width: 40px; height: 20px;")
        #expect(!isRed(capped.pixel(20, 5)))
        #expect(isRed(capped.pixel(20, 15)))
    }

    @Test("progress füllt bis value, unbestimmt zeichnet einen Abschnitt")
    func progress() throws {
        let shot = try panel("progress class=\"d\" value=0.5", ".d { -apollo-fill-color: #ff0000; -apollo-track-color: #0000ff; }", size: "width: 100px; height: 10px;")
        #expect(isRed(shot.pixel(25, 5)))
        #expect(isBlue(shot.pixel(75, 5)))
        let vertical = try panel("progress class=\"d\" value=0.25 vertical=#true", ".d { -apollo-fill-color: #ff0000; -apollo-track-color: #0000ff; }", size: "width: 10px; height: 40px;")
        #expect(isRed(vertical.pixel(5, 36)))
        #expect(isBlue(vertical.pixel(5, 10)))
        let busy = try panel("progress class=\"d\"", ".d { -apollo-fill-color: #ff0000; -apollo-track-color: #0000ff; }", size: "width: 100px; height: 10px;")
        #expect(busy.count { isRed($0) } > 20)
    }
}
