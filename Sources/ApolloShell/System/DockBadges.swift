import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

enum DockBadges {
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
