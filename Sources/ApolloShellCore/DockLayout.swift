import Foundation

/// Ein Platz im Dock der Leiste.
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

/// Reihenfolge fuer das Dock in der Leiste, wie bei Apples Dock: erst die
/// angehefteten Apps in ihrer Reihenfolge, dann die uebrigen laufenden in
/// Startreihenfolge. Jede App nur einmal (manche laufen mehrfach).
public enum DockLayout {
    /// `isAvailable`: gibt es die App noch? Angeheftete, aber geloeschte Apps
    /// fallen weg, statt als leeres Symbol stehen zu bleiben. `hidden`: nie
    /// zeigen, auch wenn sie laeuft (Finder laeuft immer, soll aber weg).
    /// `alwaysRunning`: Punkt immer zeigen - der Dateimanager wie Finder im
    /// Apple-Dock, der dort immer einen hat (z. B. ForkLift).
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
