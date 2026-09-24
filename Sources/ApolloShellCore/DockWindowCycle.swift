import Foundation

public enum DockWindowCycle {
    public static func indexToRaise(isFrontmost: Bool, visibleWindows: Int) -> Int? {
        guard isFrontmost, visibleWindows > 1 else { return nil }
        return visibleWindows - 1
    }
}
