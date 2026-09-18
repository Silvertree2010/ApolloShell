import AppKit
import ApolloShellCore
import ApplicationServices
import CoreGraphics
import SwiftUI

/// Zaehler (Ungelesen usw.) aus Apples Dock: der ist ausgeblendet, fuehrt
/// sie aber weiter und zeigt sie den Bedienungshilfen als AXStatusLabel je
/// Symbol. Gemessen 14.09.: eine AXList mit AXApplicationDockItem-Kindern,
/// jedes mit Titel und AXURL auf die App.
enum DockBadges {
    /// Eigener Faden, nicht der Faden-Vorrat von Swift: die Aufrufe warten
    /// auf Apples Dock (siehe `AppleDockMenu.queue`).
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
