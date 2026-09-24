import Foundation

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

public enum DockLayout {
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
