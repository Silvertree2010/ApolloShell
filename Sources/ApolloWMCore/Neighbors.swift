import CoreGraphics

public enum Direction: Sendable, CaseIterable {
    case left, right, up, down
}

/// Finds the window next to another one on screen, for keyboard focus and
/// swapping. Works on frames, so it does not care how the tree is built.
public enum Neighbors {
    /// The frame's nearest neighbor in `direction`: it must lie on that side
    /// and overlap on the other axis (so "right" never jumps diagonally);
    /// among those, the closest edge wins, then the most overlap.
    public static func neighbor<ID: Hashable>(of id: ID, _ direction: Direction,
                                              in frames: [ID: CGRect]) -> ID? {
        guard let from = frames[id] else { return nil }
        // Ranked by: edge distance, then overlap (more is better), then how
        // far the centers are apart across the axis, then top/left first, so
        // ties never depend on dictionary order.
        var best: (id: ID, key: [CGFloat])?
        for (other, frame) in frames where other != id {
            let distance: CGFloat
            let overlap: CGFloat
            let across: CGFloat
            switch direction {
            case .left, .right:
                guard direction == .left ? frame.midX < from.midX : frame.midX > from.midX else { continue }
                distance = direction == .left ? from.minX - frame.maxX : frame.minX - from.maxX
                overlap = min(from.maxY, frame.maxY) - max(from.minY, frame.minY)
                across = abs(frame.midY - from.midY)
            case .up, .down:
                guard direction == .up ? frame.midY < from.midY : frame.midY > from.midY else { continue }
                distance = direction == .up ? from.minY - frame.maxY : frame.minY - from.maxY
                overlap = min(from.maxX, frame.maxX) - max(from.minX, frame.minX)
                across = abs(frame.midX - from.midX)
            }
            guard overlap > 0 else { continue }
            let key = [distance.rounded(), -overlap.rounded(), across.rounded(), frame.minY, frame.minX]
            if let current = best, !key.lexicographicallyPrecedes(current.key) { continue }
            best = (other, key)
        }
        return best?.id
    }
}
