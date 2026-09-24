import Testing
import AppKit
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("surfaces.<id>.width/height vom Host (9b-8) und Toast-Stapel über dem Kontrollzentrum (TO-14)")
struct SurfaceSizeTests {
    @Test("Host schreibt die gemessene Grösse; der Toast-Abstand folgt ihr")
    func toastAboveUtilities() async throws {
        let harness = try ShellHarness("""
        popup "utilities" anchor="bottom-right" { column { text "x" } }
        toast "default" anchor="bottom-right" offset-y="{surfaces.utilities.open ? surfaces.utilities.height + 12 : 0}" { text "{toast.title}" }
        """)
        try await harness.start()
        let key = ShellHarness.a.key
        #expect(harness.runtime.surfaceValue("utilities", screenKey: key, "height") == .null)
        harness.runtime.open("utilities", screenKey: key)
        harness.settle()
        let utilities = try #require(harness.window("utilities"))
        #expect(harness.runtime.surfaceValue("utilities", screenKey: key, "height") == .number(Double(utilities.frame.height)))
        #expect(harness.runtime.surfaceValue("utilities", screenKey: key, "width") == .number(Double(utilities.frame.width)))
        let toast = try #require(harness.shell.host.model.surfaces[SurfaceHost.key("default", key)])
        #expect(toast.property("offset-y") == .number(Double(utilities.frame.height) + 12))
        harness.runtime.close("utilities")
        harness.settle()
        #expect(toast.property("offset-y") == .number(0))
    }
}

@MainActor
@Suite("Oberflächen der Art window entstehen erst beim ersten Öffnen (11-11)")
struct LazyWindowTests {
    @Test("Marketplace und eigenes window: kein Fenster vor dem Öffnen, danach bleibt es")
    func lazy() async throws {
        let harness = try ShellHarness("window \"notes\" { column { text \"n\" } }\npanel \"bar\" { row { text \"a\" } }")
        try await harness.start()
        #expect(harness.window("notes") == nil)
        #expect(harness.window("marketplace") == nil)
        #expect(harness.window("bar") != nil)
        harness.runtime.open("notes", screenKey: ShellHarness.a.key)
        harness.settle()
        let notes = try #require(harness.window("notes"))
        #expect(notes.isShown)
        harness.runtime.close("notes")
        harness.settle()
        #expect(harness.window("notes") === notes)
    }
}
