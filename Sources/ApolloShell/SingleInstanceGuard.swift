import AppKit
import ApolloShellCore
import os

/// Runtime part of `SingleInstance`: asks LaunchServices about other
/// processes with the same bundle ID. Runs before `NSApplication.run()`,
/// so before windows, keyboard shortcuts, or Apple's Dock are touched.
@MainActor
enum SingleInstanceGuard {
    private static let log = Logger(category: "app")

    /// `true`: another instance keeps running, this one should end.
    static func otherInstanceKeepsRunning() -> Bool {
        let replacesOld = SingleInstance.replacesOld(
            arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment
        )
        let deadline = Date().addingTimeInterval(SingleInstance.replaceWait)
        while true {
            let others = otherInstances()
            switch SingleInstance.decide(
                otherInstances: others, replacesOld: replacesOld, waitedLongEnough: Date() >= deadline
            ) {
            case .run:
                return false
            case .wait:
                Thread.sleep(forTimeInterval: 0.1)
            case .handOver:
                log.notice("ApolloShell is already running (\(others) instance), this one ends")
                return true
            }
        }
    }

    /// The running instance shows Nexus (the launcher in launcher-only mode).
    /// `deliverImmediately`: otherwise macOS holds the notification back
    /// until the background app becomes active.
    static func showRunningInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(SingleInstance.showNotification), object: nil, userInfo: nil, deliverImmediately: true
        )
    }

    private static func otherInstances() -> Int {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .filter { $0.processIdentifier != own && !$0.isTerminated }
            .count
    }
}
