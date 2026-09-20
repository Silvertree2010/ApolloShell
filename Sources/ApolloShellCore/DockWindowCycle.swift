import Foundation

/// Clicking the app that's already frontmost: bring its next window to the
/// front, like ⌘`. The window list comes front-to-back
/// (Accessibility); bringing the backmost one to the front leaves a
/// different one in front on each click, until all have had their turn.
/// Minimized ones don't count - those are brought up via the menu.
public enum DockWindowCycle {
    /// Index of the window to raise; `nil` = nothing to switch (app not
    /// frontmost, or only one window), so the normal click applies.
    public static func indexToRaise(isFrontmost: Bool, visibleWindows: Int) -> Int? {
        guard isFrontmost, visibleWindows > 1 else { return nil }
        return visibleWindows - 1
    }
}
