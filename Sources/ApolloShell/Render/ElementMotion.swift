import SwiftUI
import ApolloStyle
import ApolloRuntime

struct Motion: ViewModifier {
    let element: ElementInstance
    let style: ComputedStyle
    let context: RenderContext

    func body(content: Content) -> some View {
        content
    }
}
