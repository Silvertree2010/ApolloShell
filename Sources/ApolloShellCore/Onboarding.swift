import Foundation

/// Whether the introduction has been through (settings.json, section
/// "onboarding"). Fresh installations: no. When the section is missing in an
/// existing file, the shell was in use before the introduction existed - then
/// it counts as done and does not appear by itself.
public struct OnboardingSettings: Codable, Equatable, Sendable {
    public var completed: Bool

    public init(completed: Bool) {
        self.completed = completed
    }

    public static let firstLaunch = OnboardingSettings(completed: false)
    public static let existingInstall = OnboardingSettings(completed: true)

    /// Unreadable means done: turning up unasked is more of a nuisance than
    /// being missing - the menu bar item has it at any time (Introduction…).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? true
    }
}

/// When the introduction appears by itself.
public enum OnboardingRule {
    /// Only while it is not through, and not in launcher-only mode (there is
    /// neither a bar nor panels there for it to explain).
    public static func shouldShow(_ settings: ShellSettings, launcherOnly: Bool) -> Bool {
        !launcherOnly && !settings.onboarding.completed
    }
}

/// The steps of the introduction, in this order.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome, permissions, hotKeys, finish

    public var id: Self { self }

    /// As a `String`, not a `LocalizedStringKey`: `Text(step.title)` in
    /// `Onboarding.swift` would otherwise not translate (a String through a
    /// variable - see the contract).
    public var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to ApolloShell")
        case .permissions: String(localized: "Permissions")
        case .hotKeys: String(localized: "Launcher Key")
        case .finish: String(localized: "All Set")
        }
    }

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }

    /// The label of the main button.
    public var primaryButton: String {
        switch self {
        case .welcome: String(localized: "Get Started")
        case .permissions, .hotKeys: String(localized: "Continue")
        case .finish: String(localized: "Done")
        }
    }
}

/// Launcher-only mode (the app's UserDefaults): only the launcher, no bar,
/// panels, clock or toasts.
public enum LauncherOnlyFlag {
    public static let key = "launcherOnly"
    /// The earlier spelling, still read.
    public static let legacyKey = "nurLauncher"

    /// `value`: reads a key out of the UserDefaults (`object(forKey:)`).
    /// The new key wins as soon as it is set - as `false` too.
    public static func isOn(_ value: (String) -> Any?) -> Bool {
        if let current = value(key) { return bool(current) }
        return value(legacyKey).map(bool) ?? false
    }

    /// Like `UserDefaults.bool(forKey:)`: numbers and "YES"/"true" count.
    private static func bool(_ value: Any) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        case let text as String: ["1", "yes", "true"].contains(text.lowercased())
        default: false
        }
    }
}

/// Start at login (SMAppService.mainApp) - what the switch shows and whether
/// it can be used.
public enum OnboardingAutostart {
    /// A mirror of `SMAppService.Status`, so that the rule is testable without
    /// ServiceManagement.
    public enum Status: Sendable {
        case notRegistered, enabled, requiresApproval, notFound
    }

    public struct State: Equatable, Sendable {
        public var isOn: Bool
        public var canToggle: Bool
        /// Waits for the permission under General > Login Items.
        public var needsApproval: Bool
        public var note: String?

        public init(isOn: Bool, canToggle: Bool, needsApproval: Bool = false, note: String? = nil) {
            self.isOn = isOn
            self.canToggle = canToggle
            self.needsApproval = needsApproval
            self.note = note
        }
    }

    /// The id of the launchd job that started this process. launchd sets
    /// XPC_SERVICE_NAME to the label of the job; apps LaunchServices opens
    /// (Finder, Dock, `open`, login items) carry "application.<bundle-id>.…",
    /// and ones started from the terminal inherit the value of the terminal
    /// ("application.…" as well). Measured 14.09., macOS 26.6.
    public static func launchdLabel(environment: [String: String]) -> String? {
        guard let name = environment["XPC_SERVICE_NAME"]?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name != "0", !name.hasPrefix("application.")
        else { return nil }
        return name
    }

    /// - When a launchd agent of our own starts the shell, the switch stays
    ///   off and locked: both together started it twice. When the login item
    ///   is on all the same, it can be switched off.
    /// - Without an app bundle (development, `swift run`) locked: otherwise a
    ///   build folder would stand in the login items.
    public static func state(status: Status, launchdLabel: String?, isAppBundle: Bool) -> State {
        let on = status == .enabled || status == .requiresApproval
        if let launchdLabel {
            return State(isOn: on, canToggle: on, note: String(localized: "Already starts via the launchd agent “\(launchdLabel)”. This switch therefore stays off – both together would start ApolloShell twice."))
        }
        guard isAppBundle else {
            return State(isOn: on, canToggle: on, note: String(localized: "Only works in the finished app (ApolloShell.app), not in a development build."))
        }
        switch status {
        case .enabled:
            return State(isOn: true, canToggle: true)
        case .requiresApproval:
            return State(isOn: true, canToggle: true, needsApproval: true,
                         note: String(localized: "macOS is waiting for your approval under General > Login Items."))
        case .notRegistered, .notFound:
            return State(isOn: false, canToggle: true)
        }
    }
}
