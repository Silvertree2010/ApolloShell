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
    @Environment(\.elementInteractive) private var interactive
    @FocusState private var focused: Bool

    var body: some View {
        let label = element.property("label").plainText ?? element.property("tooltip").plainText ?? ""
        let can = interactive && !element.property("disabled").isTruthy && element.ir.handlers.contains { $0.name == "on-click" }
        let rad = StyleValues.radius(style["border-radius"])
        StackLayout(definite: Definite(style)) {
            ElementChildren(children: element.children, scope: scope)
        }
        .contentShape(Rectangle())
        .contentShape(.focusEffect, RoundedRectangle(cornerRadius: rad, style: .continuous))
        .focusable(can)
        .focused($focused)
        .onKeyPress(keys: [.space, .return]) { _ in
            guard can else { return .ignored }
            scope.context.fire("on-click", element, Record([("modifiers", .list([]))]))
            return .handled
        }
        .onChange(of: focused) { _, now in
            if now { element.pseudo.insert(.focus) } else { element.pseudo.remove(.focus) }
        }
        .onDisappear { element.pseudo.remove(.focus) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}
