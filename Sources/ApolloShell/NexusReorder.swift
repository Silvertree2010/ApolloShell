import ApolloShellCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let apolloReorder = UTType(exportedAs: AppIdentity.scoped("reorder"))
}

private struct NexusRowDrag: Codable, Transferable {
    let scope: String
    let i: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .apolloReorder)
    }
}

private struct NexusReorder: ViewModifier {
    let scope: String
    let i: Int
    let n: Int
    let move: (IndexSet, Int) -> Void
    @State private var hot = false

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .draggable(NexusRowDrag(scope: scope, i: i)) {
                content
                    .padding(.horizontal, 8)
                    .frame(width: 260, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
            }
            .dropDestination(for: NexusRowDrag.self) { ds, _ in
                hot = false
                guard let d = ds.first, d.scope == scope, d.i != i, (0..<n).contains(d.i) else { return false }
                move(IndexSet(integer: d.i), DragReorder.offset(from: d.i, onto: i))
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
