import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum ControlRenderers {
    static func button(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ButtonElement(element: element, style: style, scope: scope))
    }
}

struct ButtonElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope

    var body: some View {
        let label = element.property("label").plainText ?? element.property("tooltip").plainText ?? ""
        StackLayout(definite: Definite(style)) {
            ElementChildren(children: element.children, scope: scope)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}
