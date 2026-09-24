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

    var body: some View {
        let subject = StyleResolver.subject(for: surface)
        let style = context.styles.resolve(subject, ancestors: [], parent: nil)
        let scope = RenderScope(context: context, ancestors: [subject], parentStyle: style, parentKind: "column")
        VStack(alignment: StyleValues.horizontal(style["align-items"]), spacing: StyleValues.gap(style["gap"])) {
            ElementChildren(children: surface.root, scope: scope)
        }
        .modifier(StyledBox(style: style))
    }
}
