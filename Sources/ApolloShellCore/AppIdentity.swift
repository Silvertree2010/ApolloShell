import os

public enum AppIdentity {
    public static let bundleID = "io.github.silvertree2010.apolloshell"

    public static let logSubsystem = bundleID

    public static func scoped(_ name: String) -> String {
        bundleID + "." + name
    }
}

public extension Logger {
    init(category: String) {
        self.init(subsystem: AppIdentity.logSubsystem, category: category)
    }
}
