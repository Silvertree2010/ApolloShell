import Foundation

/// A window on the screen that was clicked on - only what the covered question
/// (`DockWindowCover`) needs. `id` is the window number out of
/// `CGWindowListCopyWindowInfo`, the coordinates its rectangle; which system
/// (Cocoa or Quartz) does not matter as long as all windows in the same call
/// use the same one - the overlap only works with distances.
public struct DockScreenWindow: Equatable, Sendable {
    public enum Owner: Equatable, Sendable {
        /// The app whose symbol was clicked.
        case target
        /// Some other app - it can cover a target window.
        case other
        /// ApolloShell's own bars and panels: they never count as covering,
        /// otherwise our own bar at the screen edge would constantly pass as
        /// "covering".
        case ownShell
    }

    public let id: Int
    public let owner: Owner
    /// The window level out of `kCGWindowLayer`; only level 0 (normal windows)
    /// can cover - the menu bar, the Dock and status icons lie higher and are
    /// narrower than any window, so they would count as covering wrongly.
    public let layer: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(id: Int, owner: Owner, layer: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.owner = owner
        self.layer = layer
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var area: Double { width * height }
}

/// Which window of the target app on the current screen should come forward
/// next when one clicks on its symbol that is at the front already - as with
/// Apple, paging only when something really is in the way. When several
/// windows lie freely side by side, everything stays as it is.
public enum DockWindowCover {
    /// From this much covered area on, a window counts as "in the way": a
    /// window that lies a few pixels under another one only at the edge (a
    /// shadow, a tight fit side by side) should not jump to the front just
    /// because of that - one still sees enough of it to go on working. Only
    /// from a noticeable part of the area on is it really in the way. 10 % is
    /// generous enough to ignore accidental overlaps when two windows dock
    /// tightly, but small enough to recognise a noticeably covered window.
    /// um ein spuerbar verdecktes Fenster zu erkennen.
    public static let coverThreshold = 0.1

    /// `windows` sorted front to back (the way `CGWindowListCopyWindowInfo`
    /// with `.optionOnScreenOnly` delivers it), narrowed to the one screen
    /// already. Hands back the `id` of the frontmost covered window of the
    /// target app (the next one a click should bring forward), `nil` when none
    /// is covered - with a single window or with all of them lying freely side
    /// by side as well.
    public static func nextCovered(in windows: [DockScreenWindow]) -> Int? {
        for (index, window) in windows.enumerated() where window.owner == .target {
            let inFront = windows[..<index].filter { $0.owner == .other && $0.layer == 0 }
            if inFront.contains(where: { overlapFraction(of: window, coveredBy: $0) > coverThreshold }) {
                return window.id
            }
        }
        return nil
    }

    /// The share of the area of `window` that `other` covers (0 to 1).
    static func overlapFraction(of window: DockScreenWindow, coveredBy other: DockScreenWindow) -> Double {
        guard window.area > 0 else { return 0 }
        let x = max(window.x, other.x)
        let y = max(window.y, other.y)
        let width = min(window.x + window.width, other.x + other.width) - x
        let height = min(window.y + window.height, other.y + other.height) - y
        guard width > 0, height > 0 else { return 0 }
        return (width * height) / window.area
    }
}
