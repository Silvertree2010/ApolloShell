import AppKit
import ApolloShellCore
import os

@MainActor
enum SingleInstanceGuard {
    private static let log = Logger(category: "app")

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
