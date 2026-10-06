import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: weicher box-shadow mit Raum ums Bild", .serialized)
struct RenderShadowTests {
    @Test("Schatten der Fläche wird unscharf und ganz ins Bild gezeichnet")
    func soft() throws {
        let shot = try RenderProbe.render("panel \"t\" anchor=\"left\" { }", css: "#t { width: 40px; height: 40px; background: #ffffff; box-shadow: 0 10px 20px #000000; }")
        #expect(shot.size.width == 80 && shot.size.height == 80, "\(shot.size)")
        let near = shot.pixel(40, 53), far = shot.pixel(40, 72), side = shot.pixel(12, 30)
        #expect(near.r < far.r, "\(near) \(far)")
        #expect(far.r < 255, "\(far)")
        #expect(side.r < 250 && side.r > 5, "\(side)")
        #expect(shot.pixel(40, 30).r == 255)
    }
}
