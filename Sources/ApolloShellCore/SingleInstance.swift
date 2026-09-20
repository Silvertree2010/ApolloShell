import Foundation

/// Only one ApolloShell at a time. Two instances would mean two bars,
/// duplicate shortcuts and two owners of Apple's Dock setting.
///
/// A second instance (Finder, Launchpad, a login item next to the launchd
/// agent) asks the running one through a distributed notification to show
/// Nexus, and ends before it touches anything.
///
/// The exception: an instance that replaces another one starts while the old
/// one is still ending. That is the restart after a language change
/// (`relaunchArgument`) and `launchctl kickstart -k` of a launchd agent. So it
/// waits up to `replaceWait` before giving up.
public enum SingleInstance {
    /// The start argument of the restart (`AppRestart`).
    public static let relaunchArgument = "--relaunch"

    /// A replacing instance waits this long for the end of the old one. The old
    /// one can wait on an administrator prompt while quitting (Keep Awake with
    /// the lid closed) - if the new one gives up first, none runs afterwards.
    public static let replaceWait: TimeInterval = 60

    /// A distributed notification to the running instance: "show yourself".
    public static let showNotification = AppIdentity.scoped("show")

    public enum Decision: Equatable, Sendable {
        /// No other instance: start normally.
        case run
        /// Another one is probably ending right now: look again.
        case wait
        /// The other one stays: let it show its Nexus and end ourselves.
        case handOver
    }

    public static func decide(otherInstances: Int, replacesOld: Bool, waitedLongEnough: Bool) -> Decision {
        if otherInstances == 0 { return .run }
        if replacesOld && !waitedLongEnough { return .wait }
        return .handOver
    }

    /// Does this instance replace an old one? Yes on the language-change
    /// restart and when a launchd agent of our own started it.
    public static func replacesOld(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains(relaunchArgument) || OnboardingAutostart.launchdLabel(environment: environment) != nil
    }
}
