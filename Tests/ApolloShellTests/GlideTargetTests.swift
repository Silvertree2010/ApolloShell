import Testing
import AppKit
import SwiftUI
@testable import ApolloShell

@MainActor
@Suite("glideTarget wird am Gleit-Ende gelöscht")
struct GlideTargetTests {
    @Test("nach Gleit-Ende und externer Verschiebung setzt derselbe Zielrahmen das Fenster wieder")
    func clearsAtEnd() {
        let stage = StageRecorder()
        let spec = SurfaceWindowSpec(kind: "panel", property: { _ in .null })
        let host = AppKitHostWindow(spec: spec, content: AnyView(Color.clear), stage: stage)
        let target = CGRect(x: 100, y: 100, width: 200, height: 40)
        host.setFrame(CGRect(x: 0, y: 100, width: 200, height: 40))
        stage.visible.insert(ObjectIdentifier(host.window))
        host.setFrame(target, glide: true)
        #expect(stage.glides == [target])
        stage.glideEnds.forEach { $0() }
        host.window.setFrame(CGRect(x: 300, y: 100, width: 200, height: 40), display: false)
        host.setFrame(target, glide: false)
        #expect(host.frame == target)
        host.close()
    }
}

@MainActor
@Suite("Fokus geht nach dem Entfernen des fokussierten Inhalts an die Werkzeugleiste zurück")
struct RestoreFocusTests {
    @Test("ein entfernter erster Responder wird durch die Hosting-Ansicht ersetzt")
    func replacesStale() {
        let stage = StageRecorder()
        let spec = SurfaceWindowSpec(kind: "popup", property: { _ in .null })
        let host = AppKitHostWindow(spec: spec, content: AnyView(Color.clear), stage: stage)
        stage.visible.insert(ObjectIdentifier(host.window))
        let inner = FocusView()
        host.hosting.addSubview(inner)
        #expect(host.window.makeFirstResponder(inner))
        #expect(host.window.firstResponder === inner)
        inner.removeFromSuperview()
        host.window.makeFirstResponder(nil)
        host.restoreFocus()
        #expect(host.window.firstResponder === host.hosting)
        host.close()
    }

    @Test("ein gültiger erster Responder bleibt")
    func keepsValid() {
        let stage = StageRecorder()
        let spec = SurfaceWindowSpec(kind: "popup", property: { _ in .null })
        let host = AppKitHostWindow(spec: spec, content: AnyView(Color.clear), stage: stage)
        stage.visible.insert(ObjectIdentifier(host.window))
        let inner = FocusView()
        host.hosting.addSubview(inner)
        host.window.makeFirstResponder(inner)
        host.restoreFocus()
        #expect(host.window.firstResponder === inner)
        host.close()
    }
}

private final class FocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
