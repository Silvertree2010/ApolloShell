import ApolloWM
import AppKit
import Observation

/// What the TWM sees of the displays, for Nexus to show. Filled by
/// TWMController while the TWM runs, empty otherwise.
@MainActor
@Observable
final class TWMStatus {
    static let shared = TWMStatus()

    /// One line per display, main first: its name and the arrangement on it.
    private(set) var displays: [String] = []
    /// "Displays have separate Spaces" is off, so only the main display is
    /// arranged.
    private(set) var sharedSpaces = false
    private(set) var running = false

    func update(from engine: TilingEngine) {
        running = true
        sharedSpaces = engine.displaysShareSpaces
        let names = NSScreen.screens.map(\.localizedName)
        displays = engine.screens.enumerated().map { index, screen in
            let name = names.indices.contains(index) ? names[index] : "Display \(index + 1)"
            let windows = engine.desks(onDisplay: screen.uuid)
                .reduce(0) { $0 + engine.layouts[$1].ids.count }
            let size = "\(Int(screen.bounds.width))×\(Int(screen.bounds.height))"
            return index == 0 ? "\(name), \(size), main — \(windows) tiled" : "\(name), \(size) — \(windows) tiled"
        }
    }

    func clear() {
        running = false
        displays = []
        sharedSpaces = false
    }
}
