import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Badges (unread etc.) from Apple's Dock: it's hidden, but still keeps
/// them and exposes them to Accessibility as an AXStatusLabel per icon.
/// Measured 14.09.: an AXList with AXApplicationDockItem children, each
/// with a title and an AXURL to the app.
enum DockBadges {
    /// Its own thread, not Swift's thread pool: the calls wait on Apple's
    /// Dock (see `AppleDockMenu.queue`).
    private static let queue = DispatchQueue(label: AppIdentity.scoped("dockbadges"), qos: .utility)

    static func readOffMain() async -> [String: String] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: read()) }
        }
    }

    private static func read() -> [String: String] {
        var badges: [String: String] = [:]
        for item in AppleDockItems.all(timeout: 0.3) {
            guard let label = AX.string(item, "AXStatusLabel"), !label.isEmpty,
                  let id = AppleDockItems.bundleID(of: item)
            else { continue }
            badges[id] = label
        }
        return badges
    }
}
