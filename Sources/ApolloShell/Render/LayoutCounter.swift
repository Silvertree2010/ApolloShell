import SwiftUI
import Synchronization

enum LayoutCounter {
    static let measures = Atomic<Int>(0)
    static let placements = Atomic<Int>(0)
    static let passes = Atomic<Int>(0)

    static func measured() {
        measures.add(1, ordering: .relaxed)
    }

    static func placed() {
        placements.add(1, ordering: .relaxed)
    }

    static func passed() {
        passes.add(1, ordering: .relaxed)
    }
}

protocol GuideFreeLayout: Layout {}

extension GuideFreeLayout {
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        nil
    }
}
