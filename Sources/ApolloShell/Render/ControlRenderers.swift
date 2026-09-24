import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum ControlRenderers {
    static func button(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ButtonElement(element: element, scope: scope))
    }
}

struct ButtonElement: View {
    let element: ElementInstance
    let scope: RenderScope

    var body: some View {
        let label = element.property("label").plainText ?? element.property("tooltip").plainText ?? ""
        ZStack {
            ElementChildren(children: element.children, scope: scope)
        }
        .contentShape(Rectangle())
        .onTapGesture { scope.context.trigger("on-click", element.identity, Record([("modifiers", .list([]))])) }
        .onHover { inside in
            if inside { element.pseudo.insert(.hover) } else { element.pseudo.remove(.hover) }
        }
        .help(element.property("tooltip").plainText ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}
