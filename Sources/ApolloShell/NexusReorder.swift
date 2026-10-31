import ApolloShellCore
import SwiftUI

private struct NexusReorder: ViewModifier {
    let scope: String
    let i: Int
    let n: Int
    let move: (IndexSet, Int) -> Void
    @State private var hot = false

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .draggable(DragReorder.payload(scope, i)) {
                content
                    .padding(.horizontal, 8)
                    .frame(width: 260, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
            .dropDestination(for: String.self) { ps, _ in
                hot = false
                guard let s = ps.first.flatMap({ DragReorder.index($0, scope: scope) }), s != i, (0..<n).contains(s) else { return false }
                move(IndexSet(integer: s), DragReorder.offset(from: s, onto: i))
                return true
            } isTargeted: { hot = $0 }
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(hot ? 0.18 : 0))
                    .padding(-4)
            }
    }
}

extension View {
    func nexusReorder(_ scope: String, index: Int, count: Int, move: @escaping (IndexSet, Int) -> Void) -> some View {
        modifier(NexusReorder(scope: scope, i: index, n: count, move: move))
    }
}
