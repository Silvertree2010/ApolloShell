import Testing
import Foundation
import ApolloConfig
import ApolloStyle
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Dock-Stile im Renderer")
struct DockStyleTests {
    func styled() throws -> [(ElementInstance, ComputedStyle)] {
        let (_, surface) = try DockSlice.build()
        let ir = try #require(ConfigSource.load(PackageResources.dockRender, builtinConfigs: PackageResources.configs, id: "render-dock").ir)
        let (sheets, diagnostics) = StyleSheets.load(ir)
        #expect(diagnostics.isEmpty)
        let resolver = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: false))
        var result: [(ElementInstance, ComputedStyle)] = []
        func walk(_ element: ElementInstance, _ ancestors: [StyleSubject], _ parent: ComputedStyle) {
            let subject = StyleResolver.subject(for: element)
            let style = resolver.resolve(subject, ancestors: ancestors, parent: parent)
            result.append((element, style))
            for child in element.children { walk(child, ancestors + [subject], style) }
        }
        let root = StyleResolver.subject(for: surface)
        let rootStyle = resolver.resolve(root, ancestors: [], parent: nil)
        #expect(StyleValues.points(rootStyle["width"]) == 44)
        #expect(StyleValues.points(rootStyle["height"]) == 300)
        for element in surface.root { walk(element, [root], rootStyle) }
        return result
    }

    @Test("dock-item 36 pt, Radius 11, Tönung nur im Vordergrund")
    func items() throws {
        let items = try styled().filter { DockSlice.classes($0.0).contains("dock-item") }
        #expect(items.count == 3)
        for (_, style) in items {
            #expect(StyleValues.points(style["width"]) == 36)
            #expect(StyleValues.radius(style["border-radius"]) == 11)
        }
        #expect(items[1].1["background"] == .layers([.color(.system(name: "-apple-system-label", alpha: 0.09))]))
        #expect(items[0].1["background"] == nil || items[0].1["background"] == .layers([]))
    }

    @Test("Symbol 28 pt, Punkt 4 pt links am Rand")
    func iconAndDot() throws {
        let all = try styled()
        let icon = try #require(all.first { $0.0.kind == "app-icon" })
        #expect(StyleValues.points(icon.1["width"]) == 28)
        let dot = try #require(all.first { DockSlice.classes($0.0).contains("dock-running-dot") })
        #expect(StyleValues.points(dot.1["width"]) == 4)
        #expect(StyleValues.keyword(dot.1["align-self"]) == "start")
    }

    @Test("Plakette per CSS: Farbe, Versatz, Erscheinen")
    func badge() throws {
        let icon = try #require(try styled().first { $0.0.kind == "app-icon" })
        let badge = BadgeStyle(icon.1)
        #expect(badge.offset == CGSize(width: 3, height: -3))
        #expect(icon.1["-apollo-badge-color"] == .color(.system(name: "-apple-system-red", alpha: 1)))
        #expect(badge.animation != nil)
    }
}
