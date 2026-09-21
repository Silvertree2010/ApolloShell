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
        var best: (id: ID, distance: CGFloat, overlap: CGFloat)?
        for (other, frame) in frames where other != id {
            let distance: CGFloat
            let overlap: CGFloat
            switch direction {
            case .left:
                guard frame.midX < from.midX else { continue }
                distance = from.minX - frame.maxX
                overlap = min(from.maxY, frame.maxY) - max(from.minY, frame.minY)
            case .right:
                guard frame.midX > from.midX else { continue }
                distance = frame.minX - from.maxX
                overlap = min(from.maxY, frame.maxY) - max(from.minY, frame.minY)
            case .up:
                guard frame.midY < from.midY else { continue }
                distance = from.minY - frame.maxY
                overlap = min(from.maxX, frame.maxX) - max(from.minX, frame.minX)
            case .down:
                guard frame.midY > from.midY else { continue }
                distance = frame.minY - from.maxY
                overlap = min(from.maxX, frame.maxX) - max(from.minX, frame.minX)
            }
            guard overlap > 0 else { continue }
            if let current = best,
               distance > current.distance + 0.5 ||
               (abs(distance - current.distance) <= 0.5 && overlap <= current.overlap) { continue }
            best = (other, distance, overlap)
        }
        return best?.id
    }
}
