import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
final class SurfaceHost: SurfaceHosting {
    private(set) var surfaces: [String: SurfaceInstance] = [:]
    private(set) var order: [String] = []

    static func key(_ id: String, _ screenKey: String) -> String { id + "@" + screenKey }

    func surfaceAdded(_ surface: SurfaceInstance) {
        let key = Self.key(surface.id, surface.screenKey)
        if surfaces[key] == nil { order.append(key) }
        surfaces[key] = surface
    }

    func surfaceChanged(_ surface: SurfaceInstance) {}

    func surfaceReplaced(_ surface: SurfaceInstance) {
        surfaces[Self.key(surface.id, surface.screenKey)] = surface
    }

    func surfaceRemoved(id: String, screenKey: String) {
        let key = Self.key(id, screenKey)
        surfaces[key] = nil
        order.removeAll { $0 == key }
    }
}

struct SurfaceView: View {
    let surface: SurfaceInstance
    let context: RenderContext
    var insets = EdgeInsets()
    var painter: (any BackgroundPainter)?

    var body: some View {
        let subject = StyleResolver.subject(for: surface)
        let resolved = context.styles.resolve(subject, ancestors: [], parent: nil)
        let (style, painted) = SurfaceBackground.resolve(painter, surface: surface, style: resolved)
        let scope = RenderScope(context: context, ancestors: [subject], parentStyle: style, parentKind: "column")
        LayoutRenderers.flex(horizontal: false, style: style) {
            ElementChildren(children: surface.root, scope: scope)
        }
        .padding(insets)
        .modifier(SurfaceBox(surface: surface, style: style, context: context))
        .background { painted }
        .modifier(HitRegionCollector(surfaceKey: SurfaceHost.key(surface.id, surface.screenKey), regions: context.hits))
        .modifier(ElementFrameCollector(surfaceKey: SurfaceHost.key(surface.id, surface.screenKey), frames: context.elementFrames))
        .environment(\.surfaceShown, surface.isVisible)
    }
}
