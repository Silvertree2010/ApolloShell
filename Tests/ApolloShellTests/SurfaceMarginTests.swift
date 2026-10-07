import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Oberflächen-margin wirkt nur einmal: als Abstand der Fläche, nicht zusätzlich als Polsterung")
struct SurfaceMarginTests {
    @Test("Panel mit margin: Bild so gross wie der Inhalt, der Rand rückt nur das Fenster ab")
    func marginOnce() throws {
        let kdl = "panel \"p\" anchor=\"bottom-right\" area=\"visible\" { stack class=\"box\" }"
        let css = ".box { width: 100px; height: 50px; background: rgb(255 0 0); } #p { margin: 16px; }"
        let shot = try RenderProbe.render(kdl, css: css)
        #expect(shot.size == CGSize(width: 100, height: 50), "\(shot.size)")
    }
}
