import Foundation

public struct DockScreenWindow: Equatable, Sendable {
    public enum Owner: Equatable, Sendable {
        case target
        case other
        case ownShell
    }

    public let id: Int
    public let owner: Owner
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

public enum DockWindowCover {
    public static let coverThreshold = 0.1

    public static func nextCovered(in windows: [DockScreenWindow]) -> Int? {
        for (index, window) in windows.enumerated() where window.owner == .target {
            let inFront = windows[..<index].filter { $0.owner == .other && $0.layer == 0 }
            if inFront.contains(where: { overlapFraction(of: window, coveredBy: $0) > coverThreshold }) {
                return window.id
            }
        }
        return nil
    }

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
