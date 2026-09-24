import Testing
import SwiftUI
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Render öffnet geschlossene Oberflächen, Regler mit Griff in der Füllung wie das OSD von 0.1.4.2")
struct RenderOpenSurfaceTests {
    @Test("osd zeichnet mit aktiven Bindungen und ist danach wieder zu")
    func osdIsOpenedForCapture() throws {
        let kdl = "osd \"v\" anchor=\"right\" { slider value=\"{audio.volume}\" vertical=#true class=\"s\" }"
        let css = "#v { width: 52px; height: 182px; padding: 16px 11px; } .s { width: 30px; height: 150px; -apollo-thumb-size: 26px 26px; -apollo-track-color: white; -apollo-fill-color: rgb(0 0 255); -apollo-thumb-color: white; }"
        let shot = try RenderProbe.render(kdl, css: css)
        let blue = try #require(shot.bounds { $0.b > 200 && $0.r < 60 && $0.g < 60 })
        #expect(abs(blue.height - 52.5) <= 1)
        #expect(abs(blue.maxY - 166) <= 1)
        let (session, _) = try RenderProbe.session(kdl, css: css)
        let surface = try #require(session.surfaces.first)
        #expect(RenderSession.opensForCapture(surface))
        _ = try session.capture(surface, name: "v")
        #expect(!surface.isOpen)
    }

    @Test("Füllung und Griff: Griff liegt innen am Ende der Füllung, Füllung mindestens so lang wie die Spur breit")
    func insideGeometry() {
        let mid = SliderGeometry(length: 150, cross: 30, thumb: 26, thumbCross: 26, fraction: 0.35)
        #expect(mid.inside)
        #expect(mid.fill == 52.5)
        #expect(mid.thumbCenter == 37.5)
        #expect(SliderGeometry(length: 150, cross: 30, thumb: 26, thumbCross: 26, fraction: 0).fill == 30)
        #expect(SliderGeometry(length: 150, cross: 30, thumb: 26, thumbCross: 26, fraction: 1).thumbCenter == 135)
        #expect(mid.fraction(at: 75) == 0.5)
        let outside = SliderGeometry(length: 100, cross: 4, thumb: 20, thumbCross: 20, fraction: 0.5)
        #expect(!outside.inside)
        #expect(outside.thumbCenter == 50)
        #expect(outside.fill == 50)
    }
}
