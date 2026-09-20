import Foundation

/// A slot in the bar's Dock.
public struct DockSlot: Equatable, Sendable {
    public var bundleID: String
    public var pinned: Bool
    public var running: Bool

    public init(bundleID: String, pinned: Bool, running: Bool) {
        self.bundleID = bundleID
        self.pinned = pinned
        self.running = running
    }
}

/// Order for the Dock in the bar, like Apple's Dock: pinned apps
/// first in their order, then the remaining running ones in
/// launch order. Every app only once (some run multiple times).
public enum DockLayout {
    /// `isAvailable`: does the app still exist? Pinned but deleted apps
    /// drop out instead of staying as an empty icon. `hidden`: never
    /// show, even if it is running (Finder is always running but should be gone).
    /// `alwaysRunning`: always show a dot - the file manager, like Finder in
    /// Apple's Dock, which always has one there (e.g. ForkLift).
    public static func slots(pinned: [String], running: [String], hidden: Set<String> = [],
                             alwaysRunning: Set<String> = [],
                             isAvailable: (String) -> Bool) -> [DockSlot] {
        let runningSet = Set(running).union(alwaysRunning)
        var seen = hidden
        var result: [DockSlot] = []
        for id in pinned where !seen.contains(id) && isAvailable(id) {
            seen.insert(id)
            result.append(DockSlot(bundleID: id, pinned: true, running: runningSet.contains(id)))
        }
        for id in running where !seen.contains(id) {
            seen.insert(id)
            result.append(DockSlot(bundleID: id, pinned: false, running: true))
        }
        return result
    }
}
