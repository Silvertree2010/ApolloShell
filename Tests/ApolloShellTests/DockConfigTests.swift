import Testing
import ApolloBase
import ApolloConfig
import ApolloStyle

@Suite("Dock-Config")
struct DockConfigTests {
    @Test("Default-Config lädt ohne Fehler")
    func defaultConfigLoads() {
        let result = PackageResources.load(PackageResources.configs.appendingPathComponent("apolloshell-default"), id: "apolloshell-default")
        #expect(result.ir != nil)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
    }

    @Test("Render-Config hängt das Dock-Modul der Leiste in ein panel")
    func dockPanel() throws {
        let result = PackageResources.load(PackageResources.dockRender, allDefines: true)
        let ir = try #require(result.ir)
        let panel = try #require(ir.surfaces.first { $0.id == "dock" })
        #expect(panel.kind == "panel")
        #expect(ir.defines["m-dock"] != nil)
        #expect(ir.vars.contains { $0.name == "bm" })
        #expect(ir.styleSheets.contains { $0.url.lastPathComponent == "style.css" })
    }
}

@Suite("Dock-Stylesheet")
struct DockStyleSheetTests {
    @Test("style.css parst ohne Warnung")
    func parsesCleanly() throws {
        let url = PackageResources.configs.appendingPathComponent("apolloshell-default/style.css")
        let text = try String(contentsOf: url, encoding: .utf8)
        let (_, diagnostics) = StyleSheet.parse(text, file: url.path, origin: .config)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }
}
