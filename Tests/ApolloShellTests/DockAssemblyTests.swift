import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders
@testable import ApolloShell

@MainActor
final class NullHost: SurfaceHosting {
    func surfaceAdded(_ surface: SurfaceInstance) {}
    func surfaceChanged(_ surface: SurfaceInstance) {}
    func surfaceReplaced(_ surface: SurfaceInstance) {}
    func surfaceRemoved(id: String, screenKey: String) {}
}

@MainActor
enum DockSlice {
    static func build(host: any SurfaceHosting = NullHost()) throws -> (ShellAssembly, SurfaceInstance) {
        let scheduler = ManualFlushScheduler()
        let assembly = ShellAssembly(host: host, scheduler: scheduler, filterContext: ShellAssembly.fixedContext(now: Date(timeIntervalSince1970: 1_790_235_660)))
        let fixture = ProviderFixture.load(PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        #expect(fixture.diagnostics.isEmpty)
        assembly.install(FixtureProvider.all(fixture: fixture))
        let result = ConfigSource.load(PackageResources.dockRender, builtinConfigs: PackageResources.configs, id: "render-dock")
        let ir = try #require(result.ir)
        assembly.apply(ir, screens: ["render"])
        for _ in 0..<20 { scheduler.runPending() }
        let surface = try #require(assembly.runtime.surface("dock", screenKey: "render"))
        return (assembly, surface)
    }

    static func all(_ roots: [ElementInstance]) -> [ElementInstance] {
        roots.flatMap { [$0] + all($0.children) }
    }

    static func classes(_ element: ElementInstance) -> [String] {
        guard case .string(let text) = element.property("class") else { return [] }
        return text.split(separator: " ").map(String.init)
    }
}

@MainActor
@Suite("Dock-Durchstich Runtime")
struct DockAssemblyTests {
    @Test("Fixture-Apps ergeben drei dock-item mit Vordergrund, Punkten und Plakette")
    func dockItems() throws {
        let (assembly, surface) = try DockSlice.build()
        let elements = DockSlice.all(surface.root)
        let items = elements.filter { DockSlice.classes($0).contains("dock-item") }
        #expect(items.count == 3)
        #expect(items.map { $0.property("tooltip") } == [.string("Finder"), .string("Safari"), .string("Mail")])
        #expect(DockSlice.classes(items[1]).contains("front"))
        #expect(!DockSlice.classes(items[0]).contains("front"))
        let dots = elements.filter { DockSlice.classes($0).contains("dock-running-dot") }
        #expect(dots.count == 2)
        let icons = elements.filter { $0.kind == "app-icon" }
        #expect(icons.map { $0.property("badge") } == [.null, .null, .string("3")])
        #expect(assembly.warnings.isEmpty, "\(assembly.warnings.map(\.message))")
    }
}
