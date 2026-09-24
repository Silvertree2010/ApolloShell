import Foundation

public enum SingleInstance {
    public static let relaunchArgument = "--relaunch"

    public static let replaceWait: TimeInterval = 60

    public static let showNotification = AppIdentity.scoped("show")

    public enum Decision: Equatable, Sendable {
        case run
        case wait
        case handOver
    }

    public static func decide(otherInstances: Int, replacesOld: Bool, waitedLongEnough: Bool) -> Decision {
        if otherInstances == 0 { return .run }
        if replacesOld && !waitedLongEnough { return .wait }
        return .handOver
    }

    public static func replacesOld(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains(relaunchArgument) || OnboardingAutostart.launchdLabel(environment: environment) != nil
    }
}
