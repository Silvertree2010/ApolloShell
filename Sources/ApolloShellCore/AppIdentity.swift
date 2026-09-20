import os

/// The app's identity in one place. Matches the bundle ID in
/// Support/Info.plist (build.sh and scripts/assemble-app.sh sign with it;
/// a test checks that both agree). Derived from it: the log subsystem,
/// queue labels, and our own pasteboard types. The log categories still
/// live with the callers (`Logger(category:)`).
public enum AppIdentity {
    public static let bundleID = "io.github.silvertree2010.apolloshell"

    /// For `Logger(category:)`, and thus also for
    /// `log stream --predicate 'subsystem == "…"'`.
    public static let logSubsystem = bundleID

    /// An identifier below the bundle ID, e.g. for queue labels:
    /// `scoped("bluetooth")` = "<bundleID>.bluetooth".
    public static func scoped(_ name: String) -> String {
        bundleID + "." + name
    }
}

public extension Logger {
    /// A logger under the app's subsystem. Previously every call site wrote
    /// out the subsystem itself, three of them as
    /// `Bundle.main.bundleIdentifier ?? "ApolloShell"` - without a bundle
    /// (`swift run`) their messages ended up under a different subsystem.
    init(category: String) {
        self.init(subsystem: AppIdentity.logSubsystem, category: category)
    }
}
