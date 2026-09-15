import AppKit
import ApolloShellCore
import os

/// Laufzeit-Teil von `SingleInstance`: fragt LaunchServices nach anderen
/// Prozessen mit derselben Bundle-ID. Laeuft vor `NSApplication.run()`,
/// also bevor Fenster, Tastenkuerzel oder Apples Dock angefasst werden.
@MainActor
enum SingleInstanceGuard {
    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "app")

    /// `true`: Eine andere Instanz laeuft weiter, diese hier soll enden.
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
                log.notice("ApolloShell laeuft schon (\(others) Instanz), diese endet")
                return true
            }
        }
    }

    /// Die laufende Instanz zeigt Nexus (im Nur-Launcher-Modus den Launcher).
    /// `deliverImmediately`: Sonst haelt macOS die Mitteilung zurueck, bis die
    /// Hintergrund-App aktiv wird.
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
