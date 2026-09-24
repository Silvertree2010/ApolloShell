import Testing
import SwiftUI
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Animationen ruhen bei verborgener Oberfläche, Emblem grüsst bei jedem Öffnen (Befund 9, SM-06)")
struct SurfaceShownTests {
    @Test("endlose animation pausiert, solange die Oberfläche nicht sichtbar ist")
    func animationPauses() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }", css: ".x { animation: spin 1s infinite; }")
        let element = try #require(session.surfaces.first?.root.first)
        let style = session.context.styles.resolve(StyleResolver.subject(for: element), ancestors: [], parent: nil)
        let spin = try #require(AnimationSpec(style))
        #expect(!RunningAnimation.paused(spec: spin, finished: false, shown: true))
        #expect(RunningAnimation.paused(spec: spin, finished: false, shown: false))
    }

    @Test("Emblem: Öffnen startet die Begrüssung neu, Schliessen lässt sie stehen")
    func greetsOnEveryOpen() {
        let again = MarkElement.onShow(true, greet: true, reaction: .idle, at: 500)
        #expect(again?.reaction == .greet)
        #expect(again?.startTime == 500)
        #expect(MarkElement.onShow(true, greet: false, reaction: .think, at: 9)?.reaction == .think)
        #expect(MarkElement.onShow(false, greet: true, reaction: .idle, at: 9) == nil)
    }
}
